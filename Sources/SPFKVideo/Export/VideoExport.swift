// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import AVFoundation
import Foundation
import SPFKBase

/// What ``VideoEditRenderer`` and ``VideoFormatConverter`` share about running an `AVAssetExportSession`:
/// the two export paths, the trim's time range, and the check that the output kept its tracks.
enum VideoExport {
    /// How ``missingTracks(source:sourceURL:output:comparing:)`` counts.
    enum TrackComparison {
        /// Each kind keeps as many tracks as it had. A passthrough export copies every track.
        case count

        /// Each kind present in the source is present in the output. A re-encoding preset mixes
        /// every audio track into one.
        case presence
    }

    /// Runs `session` into `url`. Throws `CancellationError` when the session or the enclosing task
    /// was cancelled, and otherwise the session's own error.
    ///
    /// `legacy` takes the pre-macOS 15 path, where `export(to:as:)` is unavailable. Runs on the caller's
    /// actor, which may hold the session. `progress` is called with the session's fraction, 0...1, at once
    /// and then every 200 ms until the export returns.
    static func run(
        _ session: AVAssetExportSession,
        to url: URL,
        as fileType: AVFileType,
        legacy: Bool,
        progress: (@Sendable (Double) async -> Void)? = nil,
        isolation: isolated (any Actor)? = #isolation
    ) async throws {
        let poller = progress.map { report in
            let shared = SharedSession(session: session)

            return Task {
                while !Task.isCancelled {
                    await report(Double(shared.session.progress))
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
        }

        do {
            if #available(macOS 15, iOS 18, *), !legacy {
                // Takes the destination directly: `outputURL`/`outputFileType` must not also be set.
                try await session.export(to: url, as: fileType)
            } else {
                try await runPreMacOS15(session, to: url, as: fileType)
            }
        } catch let error as AVError where error.code == .operationCancelled {
            await stop(poller)
            throw CancellationError()
        } catch {
            await stop(poller)
            throw error
        }

        await stop(poller)
    }

    /// Awaited so that no report arrives after ``run(_:to:as:legacy:progress:isolation:)`` returns.
    private static func stop(_ poller: Task<Void, Never>?) async {
        poller?.cancel()
        await poller?.value
    }

    /// Deletes cleanly along with its call site once the deployment target reaches macOS 15.
    private static func runPreMacOS15(
        _ session: AVAssetExportSession,
        to url: URL,
        as fileType: AVFileType,
        isolation: isolated (any Actor)? = #isolation
    ) async throws {
        session.outputURL = url
        session.outputFileType = fileType

        let cancel = SharedSession(session: session)

        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                session.exportAsynchronously { continuation.resume() }
            }
        } onCancel: {
            cancel.session.cancelExport()
        }

        switch session.status {
        case .completed:
            return
        case .cancelled:
            throw CancellationError()
        default:
            throw session.error ?? CocoaError(.fileWriteUnknown)
        }
    }

    /// `cancelExport()` and `progress` may be called from any thread.
    private final class SharedSession: @unchecked Sendable {
        let session: AVAssetExportSession

        init(session: AVAssetExportSession) {
            self.session = session
        }
    }

    /// Which of audio and video the output at `url` lost.
    ///
    /// A track list is not the only reading of a file's audio, and where the two disagree the
    /// comparison is blind: the export carries over what `AVURLAsset` lists, so a track absent from the
    /// source's list is absent from both sides. ``VideoEditRenderer/hasDecodableAudio(at:)`` is the
    /// second opinion.
    static func missingTracks(
        source asset: AVAsset,
        sourceURL: URL,
        output url: URL,
        comparing comparison: TrackComparison,
        isolation: isolated (any Actor)? = #isolation
    ) async throws -> [AVMediaType] {
        let sourceTypes = try await asset.load(.tracks).map(\.mediaType)
        let outputTypes = try await AVURLAsset(url: url).load(.tracks).map(\.mediaType)

        let missing = switch comparison {
        case .count:
            VideoEditRenderer.missingEssentialTracks(source: sourceTypes, output: outputTypes)
        case .presence:
            VideoEditRenderer.missingEssentialTracks(source: Array(Set(sourceTypes)), output: Array(Set(outputTypes)))
        }

        if missing.isEmpty,
           VideoEditRenderer.hasDecodableAudio(at: sourceURL),
           !VideoEditRenderer.hasDecodableAudio(at: url) {
            return [.audio]
        }

        return missing
    }

    /// A movie of `url` whose video tracks display `orientation` after what they display now, with the
    /// matrix set on each track in order; `nil` for no edit. Every export preset honors the movie:
    /// passthrough writes the matrix, and a re-encoding preset renders the pixels through it.
    static func orientedMovie(
        of url: URL,
        orientation: OrientationEdit,
        isolation: isolated (any Actor)? = #isolation
    ) async throws -> (movie: AVMutableMovie, transforms: [CGAffineTransform])? {
        guard !orientation.isIdentity else { return nil }

        let movie = AVMutableMovie(url: url, options: nil)
        var transforms: [CGAffineTransform] = []

        for track in try await movie.loadTracks(withMediaType: .video) {
            let transform = try await track.load(.preferredTransform)
            let naturalSize = try await track.load(.naturalSize)
            let oriented = transform.applying(orientation, naturalSize: naturalSize)

            track.preferredTransform = oriented
            transforms.append(oriented)
        }

        return (movie, transforms)
    }

    /// Whether the video tracks at `url` carry `transforms`, in order, within 1e-6 on each field.
    static func videoTransforms(at url: URL, match transforms: [CGAffineTransform]) async throws -> Bool {
        var written: [CGAffineTransform] = []

        for track in try await AVURLAsset(url: url).loadTracks(withMediaType: .video) {
            written.append(try await track.load(.preferredTransform))
        }

        guard written.count == transforms.count else { return false }

        return zip(transforms, written).allSatisfy { lhs, rhs in
            zip([lhs.a, lhs.b, lhs.c, lhs.d, lhs.tx, lhs.ty], [rhs.a, rhs.b, rhs.c, rhs.d, rhs.tx, rhs.ty])
                .allSatisfy { abs($0 - $1) <= 1e-6 }
        }
    }

    /// Resolves the trim's seconds against the asset's real duration.
    ///
    /// An `outPoint` of 0 means "to the end"; one past the end is clamped rather than refused, since a
    /// trim stored against a slightly different duration (a container whose audio and video tracks
    /// disagree by a few frames) is a rounding artifact, not a mistake.
    static func timeRange(
        for trim: TrimDescription,
        in asset: AVAsset,
        isolation: isolated (any Actor)? = #isolation
    ) async throws -> CMTimeRange {
        let duration = try await asset.load(.duration)

        guard duration.isValid, !duration.isIndefinite, duration.seconds > 0 else {
            throw VideoEditError.trimOutOfRange(
                inPoint: trim.inPoint, outPoint: trim.outPoint, duration: duration.seconds
            )
        }

        let start = CMTime(seconds: trim.inPoint, preferredTimescale: 600)
        let requestedEnd = trim.outPoint > 0
            ? CMTime(seconds: trim.outPoint, preferredTimescale: 600)
            : duration
        let end = min(requestedEnd, duration)

        guard start < end else {
            throw VideoEditError.trimOutOfRange(
                inPoint: trim.inPoint, outPoint: trim.outPoint, duration: duration.seconds
            )
        }

        return CMTimeRange(start: start, end: end)
    }
}
