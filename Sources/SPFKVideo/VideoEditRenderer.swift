// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import AVFoundation
import Foundation
import SPFKBase
import UniformTypeIdentifiers

/// Applies a ``TrimDescription`` to a video file and writes the result to an output URL.
///
/// Uses `AVAssetExportPresetPassthrough`, so the media is remuxed rather than re-encoded: every
/// track is copied bit-for-bit and the export costs milliseconds rather than minutes. Trimming is
/// still exact on both ends — the export retains the partial leading GOP and writes an edit list
/// that starts presentation at the requested time, so the first presented frame is the frame at
/// the in-point even when the preceding keyframe is more than a second earlier. Measured against a
/// 23.976 long-GOP source with keyframes ~1.25 s apart; see
/// `shadowtag-video-edit-rendering.md` Phase 2. **This is why the editor must not snap trim
/// handles to keyframes** — there is no drift to compensate for, and snapping would move the
/// user's in-point for nothing.
///
/// The one cost of that mechanism is that up to one extra GOP of leading video stays in the file.
/// Anything honoring edit lists — all of AVFoundation, and ffmpeg by default — sees the exact
/// trim; a tool that ignores them sees the lead-in. That is inherent to lossless trimming.
///
/// Metadata needs no special handling: a passthrough export preserves the iTunes, QuickTime
/// `udta` and QuickTime `mdta` keyspaces intact, including capture date, device and GPS. There is
/// deliberately no metadata-copy pass here, unlike ``AudioEditRenderer`` which must re-copy
/// everything through its converter. `PassthroughMetadataProbeTests` guards that assumption.
///
/// Takes a ``TrimDescription`` rather than an audio edit type on purpose: this package must stay
/// free of any audio dependency so TorchTag can reach it too.
public actor VideoEditRenderer {
    /// The source video file to read.
    public let sourceURL: URL

    /// The trim window to apply. An `outPoint` of 0 means "keep to the end of the file".
    public let trim: TrimDescription

    /// The destination URL for the rendered output. Must not already exist.
    public let outputURL: URL

    /// Fraction of the export completed, 0...1. Readable while ``render()`` is in flight so a
    /// caller can drive a progress indicator; a passthrough export of a large file is fast but
    /// not instant.
    public var progress: Double {
        session.map { Double($0.progress) } ?? 0
    }

    private var session: AVAssetExportSession?

    public init(sourceURL: URL, trim: TrimDescription, outputURL: URL) {
        self.sourceURL = sourceURL
        self.trim = trim
        self.outputURL = outputURL
    }

    /// Applies the trim and writes the result to ``outputURL``.
    ///
    /// - Returns: The URL written, always ``outputURL``.
    /// - Throws: ``VideoEditError`` when the output exists, the container can't be written, the
    ///   trim falls outside the source, or the export fails or is cancelled.
    @discardableResult
    public func render() async throws -> URL {
        try Task.checkCancellation()

        guard !outputURL.exists else {
            throw VideoEditError.outputExists(outputURL)
        }

        let outputFileType = try Self.fileType(for: outputURL)

        let didStartAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let asset = AVURLAsset(url: sourceURL)
        let timeRange = try await resolveTimeRange(in: asset)

        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw VideoEditError.exportUnavailable(sourceURL)
        }

        // Asked of the session rather than checked against a list of known-bad extensions, so a
        // container this build can't write is refused without anyone maintaining that list.
        guard session.supportedFileTypes.contains(outputFileType) else {
            throw VideoEditError.unsupportedOutputContainer(outputURL.pathExtension)
        }

        session.outputURL = outputURL
        session.outputFileType = outputFileType
        session.timeRange = timeRange

        self.session = session
        defer { self.session = nil }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { continuation.resume() }
        }

        switch session.status {
        case .completed:
            return outputURL

        case .cancelled:
            try? FileManager.default.removeItem(at: outputURL)
            throw VideoEditError.cancelled

        default:
            // A failed export can still leave a partial file behind, and the caller's next step
            // is typically to replace the original with it.
            try? FileManager.default.removeItem(at: outputURL)
            throw VideoEditError.exportFailed(sourceURL, underlying: session.error)
        }
    }

    /// Cancels an in-flight ``render()``, which then throws ``VideoEditError/cancelled`` and
    /// removes the partial output. No effect when no render is running.
    public func cancel() {
        session?.cancelExport()
    }

    // MARK: - Private

    /// Resolves the trim's seconds against the asset's real duration.
    ///
    /// An `outPoint` of 0 means "to the end"; an `outPoint` past the end is clamped rather than
    /// refused, since a trim stored against a slightly different duration (a container whose
    /// audio and video tracks disagree by a few frames) is a rounding artifact, not a mistake.
    private func resolveTimeRange(in asset: AVURLAsset) async throws -> CMTimeRange {
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

    /// Maps the output URL's path extension to the `AVFileType` the export session expects.
    private static func fileType(for url: URL) throws -> AVFileType {
        guard let utType = UTType(filenameExtension: url.pathExtension) else {
            throw VideoEditError.unsupportedOutputContainer(url.pathExtension)
        }
        return AVFileType(rawValue: utType.identifier)
    }
}
