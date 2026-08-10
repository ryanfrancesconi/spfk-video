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

    /// Forces the pre-macOS 15 export path regardless of the running OS. Tests only.
    ///
    /// Exists because `#available(macOS 15, *)` is always true on any current development or CI
    /// machine, so that fallback would otherwise ship to macOS 13/14 users having never executed
    /// anywhere. Deliberately not public.
    var usesLegacyExportPath = false

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

        session.timeRange = timeRange

        self.session = session
        defer { self.session = nil }

        do {
            if #available(macOS 15, *), !usesLegacyExportPath {
                // Native async: reports failure by throwing rather than through a status
                // property, and its `isolation` parameter defaults to `#isolation`, so it stays
                // on this actor without a continuation bridge. Takes the destination directly —
                // `outputURL`/`outputFileType` must not also be set on the session.
                try await session.export(to: outputURL, as: outputFileType)
            } else {
                try await exportPreMacOS15(session, to: outputURL, as: outputFileType)
            }
        } catch {
            // A failed or cancelled export can still leave a partial file behind, and the
            // caller's next step is typically to replace the original with it.
            try? FileManager.default.removeItem(at: outputURL)
            throw Self.renderError(from: error, sourceURL: sourceURL)
        }

        try await verifyTracksSurvived(from: asset, to: outputURL)

        return outputURL
    }

    /// Cancels an in-flight ``render()``, which then throws ``VideoEditError/cancelled`` and
    /// removes the partial output. No effect when no render is running.
    public func cancel() {
        session?.cancelExport()
    }

    /// Tests only — see ``usesLegacyExportPath``.
    func setUsesLegacyExportPath(_ value: Bool) {
        usesLegacyExportPath = value
    }

    // MARK: - Private

    /// The export path for macOS 13 and 14, where `export(to:as:)` is unavailable.
    ///
    /// Sets the destination on the session, bridges the completion handler to async, and turns
    /// the resulting `status` into a throw so both paths fail the same way for the caller.
    ///
    /// Deletes cleanly along with its call site once this package's deployment target reaches
    /// macOS 15 — nothing else here depends on the pre-15 shape.
    private func exportPreMacOS15(
        _ session: AVAssetExportSession,
        to url: URL,
        as fileType: AVFileType
    ) async throws {
        session.outputURL = url
        session.outputFileType = fileType

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { continuation.resume() }
        }

        switch session.status {
        case .completed:
            return
        case .cancelled:
            throw VideoEditError.cancelled
        default:
            throw VideoEditError.exportFailed(sourceURL, underlying: session.error)
        }
    }

    /// Normalizes what the two export paths throw into a single ``VideoEditError``.
    ///
    /// The macOS 15 path reports cancellation by throwing rather than through a status property,
    /// and does so as `AVError.operationCancelled` when ``cancel()`` was called or as a
    /// `CancellationError` when the enclosing task was cancelled — both mean the same thing here.
    private static func renderError(from error: any Error, sourceURL: URL) -> VideoEditError {
        if let error = error as? VideoEditError {
            return error
        }
        if error is CancellationError {
            return .cancelled
        }
        if let error = error as? AVError, error.code == .operationCancelled {
            return .cancelled
        }
        return .exportFailed(sourceURL, underlying: error)
    }

    /// Throws unless the render still carries the audio and video the source had.
    ///
    /// A passthrough export writes what the destination container accepts and reports `.completed`
    /// either way, so a dropped track arrives as success. The caller's next step is to replace the
    /// user's original with this file, which is the point of no return.
    private func verifyTracksSurvived(from asset: AVURLAsset, to url: URL) async throws {
        let sourceTypes = try await asset.load(.tracks).map(\.mediaType)
        let outputTypes = try await AVURLAsset(url: url).load(.tracks).map(\.mediaType)

        let missing = Self.missingEssentialTracks(source: sourceTypes, output: outputTypes)

        guard missing.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            throw VideoEditError.tracksLost(
                sourceURL,
                missing: missing.map { $0 == .audio ? "audio" : "video" }
            )
        }
    }

    /// Which of audio and video came out with fewer tracks than went in.
    ///
    /// Only those two are checked. Timecode, metadata and text tracks are routinely dropped by a
    /// passthrough export — a GoPro's `tmcd` and `gpmd` do not survive one — and refusing those
    /// renders would block ordinary edits to protect data the container was never going to keep.
    public static func missingEssentialTracks(
        source: [AVMediaType],
        output: [AVMediaType]
    ) -> [AVMediaType] {
        [.audio, .video].filter { type in
            output.filter { $0 == type }.count < source.filter { $0 == type }.count
        }
    }

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
