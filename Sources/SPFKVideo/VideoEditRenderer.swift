// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import AVFoundation
import Foundation
import SPFKBase
import UniformTypeIdentifiers

/// Applies a ``TrimDescription`` and an `OrientationEdit` to a video file and writes the result to an
/// output URL.
///
/// Uses `AVAssetExportPresetPassthrough`, so the media is remuxed rather than re-encoded: every
/// track is copied bit-for-bit and the export costs milliseconds rather than minutes. Trimming is
/// still exact on both ends - the export retains the partial leading GOP and writes an edit list
/// that starts presentation at the requested time, so the first presented frame is the frame at
/// the in-point even when the preceding keyframe is more than a second earlier. Measured against a
/// 23.976 long-GOP source with keyframes ~1.25 s apart. **This is why the editor must not snap trim
/// handles to keyframes** - there is no drift to compensate for, and snapping would move the
/// user's in-point for nothing.
///
/// The one cost of that mechanism is that up to one extra GOP of leading video stays in the file.
/// Anything honoring edit lists - all of AVFoundation, and ffmpeg by default - sees the exact
/// trim; a tool that ignores them sees the lead-in. That is inherent to lossless trimming.
///
/// Metadata needs no special handling: a passthrough export preserves the iTunes, QuickTime
/// `udta` and QuickTime `mdta` keyspaces intact, including capture date, device and GPS. There is
/// deliberately no metadata-copy pass here, unlike ``AudioEditRenderer`` which must re-copy
/// everything through its converter. `PassthroughMetadataProbeTests` guards that assumption.
///
/// An orientation is written as each video track's matrix, so it re-encodes nothing either. A render
/// with no orientation reads the source as an `AVURLAsset`, and one with an orientation as an
/// `AVMutableMovie` - never a composition, which drops the asset's metadata.
///
/// A ``filter`` is the exception: it changes pixels, so the render re-encodes with
/// ``reencodePreset(for:)`` through a ``VideoFrameFilter`` composition, which bakes the orientation in.
///
/// Takes a ``TrimDescription`` rather than an audio edit type on purpose: this package must stay
/// free of any audio dependency so TorchTag can reach it too.
public actor VideoEditRenderer {
    /// The source video file to read.
    public let sourceURL: URL

    /// The trim window to apply. An `outPoint` of 0 means "keep to the end of the file".
    public let trim: TrimDescription

    /// Performed after what each video track displays now. `.up` changes nothing.
    public let orientation: OrientationEdit

    /// Run on every frame. Non-nil re-encodes the video.
    public let filter: VideoFrameFilter?

    /// The destination URL for the rendered output. Must not already exist.
    public let outputURL: URL

    /// Fraction of the export completed, 0...1. Readable while ``render()`` is in flight so a
    /// caller can drive a progress indicator; a passthrough export of a large file is fast but
    /// not instant.
    public var progress: Double {
        session.map { Double($0.progress) } ?? 0
    }

    private var session: AVAssetExportSession?

    /// Forces the pre-macOS 15 export path regardless of the running OS.
    ///
    /// `#available(macOS 15, *)` is true on every current development and CI machine, so without
    /// this the branch macOS 13/14 users run would ship having never executed anywhere. Defaults
    /// from ``OSVersion/macOS15``, so simulating an older system reaches this path app-wide;
    /// tests set it per instance, which keeps them independent of that global. Not public.
    var usesLegacyExportPath = !OSVersion.macOS15.isAvailable

    public init(
        sourceURL: URL,
        trim: TrimDescription,
        orientation: OrientationEdit = .up,
        filter: VideoFrameFilter? = nil,
        outputURL: URL
    ) {
        self.sourceURL = sourceURL
        self.trim = trim
        self.orientation = orientation
        self.filter = filter
        self.outputURL = outputURL
    }

    /// Applies the trim and orientation and writes the result to ``outputURL``.
    ///
    /// - Returns: The URL written, always ``outputURL``.
    /// - Throws: ``VideoEditError`` when the output exists, the container can't be written, the
    ///   trim falls outside the source, the export fails or is cancelled, or the output does not
    ///   carry the orientation.
    @discardableResult
    public func render() async throws -> URL {
        try await render(progress: nil)
    }

    /// ``render()``, calling `progress` with the export's fraction, 0...1, at once and then every 200 ms
    /// until the export returns. Nothing is reported after this returns.
    @discardableResult
    public func render(progress: (@Sendable (Double) async -> Void)?) async throws -> URL {
        try Task.checkCancellation()

        guard !outputURL.exists else {
            throw VideoEditError.outputExists(outputURL)
        }

        let outputFileType = try Self.fileType(for: outputURL)

        let didStartAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let oriented = try await VideoExport.orientedMovie(of: sourceURL, orientation: orientation)
        let asset: AVAsset = oriented?.movie ?? AVURLAsset(url: sourceURL)
        let timeRange = try await VideoExport.timeRange(for: trim, in: asset)

        let presetName = filter == nil ? AVAssetExportPresetPassthrough : try await reencodePresetName(for: asset)

        guard let session = AVAssetExportSession(asset: asset, presetName: presetName) else {
            throw VideoEditError.exportUnavailable(sourceURL)
        }

        if let filter {
            session.videoComposition = try await VideoFrameFilter.composition(for: asset, filter: filter)
        }

        // Asked of the session rather than checked against a list of known-bad extensions, so a
        // container this build can't write is refused without anyone maintaining that list.
        guard session.supportedFileTypes.contains(outputFileType) else {
            throw VideoEditError.unsupportedOutputContainer(
                outputURL.pathExtension,
                alternatives: Self.pathExtensions(for: session.supportedFileTypes)
            )
        }

        session.timeRange = timeRange

        self.session = session
        defer { self.session = nil }

        do {
            try await VideoExport.run(
                session, to: outputURL, as: outputFileType, legacy: usesLegacyExportPath, progress: progress
            )
        } catch {
            // A failed or cancelled export can still leave a partial file behind, and the
            // caller's next step is typically to replace the original with it.
            try? FileManager.default.removeItem(at: outputURL)
            throw Self.renderError(from: error, sourceURL: sourceURL)
        }

        try await verifyTracksSurvived(from: asset, to: outputURL)

        if filter != nil {
            try await verifyOrientationRendered(from: asset, to: outputURL)
        } else if let oriented {
            try await verifyOrientationWritten(oriented.transforms, to: outputURL)
        }

        return outputURL
    }

    /// Tests only - see ``usesLegacyExportPath``.
    func setUsesLegacyExportPath(_ value: Bool) {
        usesLegacyExportPath = value
    }

    // MARK: - Private

    /// Normalizes what the export throws into a single ``VideoEditError``. Task cancellation
    /// arrives as `CancellationError`.
    private static func renderError(from error: any Error, sourceURL: URL) -> VideoEditError {
        if let error = error as? VideoEditError {
            return error
        }
        if error is CancellationError {
            return .cancelled
        }
        return .exportFailed(sourceURL, underlying: error)
    }

    /// Throws unless every video track of the render carries the matrix it was given.
    private func verifyOrientationWritten(_ transforms: [CGAffineTransform], to url: URL) async throws {
        guard try await VideoExport.videoTransforms(at: url, match: transforms) else {
            try? FileManager.default.removeItem(at: url)
            throw VideoEditError.orientationNotWritten(sourceURL)
        }
    }

    /// Throws unless the render still carries the audio and video the source had.
    ///
    /// A passthrough export writes what the destination container accepts and reports `.completed`
    /// either way, so a dropped track arrives as success. The caller's next step is to replace the
    /// user's original with this file, which is the point of no return.
    private func verifyTracksSurvived(from asset: AVAsset, to url: URL) async throws {
        let missing = try await VideoExport.missingTracks(
            source: asset, sourceURL: sourceURL, output: url, comparing: filter == nil ? .count : .presence
        )

        guard missing.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            throw VideoEditError.tracksLost(
                sourceURL,
                missing: missing.map { $0 == .audio ? "audio" : "video" }
            )
        }
    }

    /// Whether the file's audio decodes, which is not the same question as whether `AVURLAsset`
    /// lists an audio track.
    ///
    /// The two readings come from different parsers and disagree on a malformed container: a trak
    /// AVFoundation's asset parser rejects can still open through `AVAudioFile`. Use this wherever
    /// "does this file have audio to lose" has to be answered about a file whose track list may
    /// not be trustworthy.
    public static func hasDecodableAudio(at url: URL) -> Bool {
        ((try? AVAudioFile(forReading: url))?.length ?? 0) > 0
    }

    /// Which of audio and video came out with fewer tracks than went in.
    ///
    /// Only those two are checked. Timecode, metadata and text tracks are routinely dropped by a
    /// passthrough export - a GoPro's `tmcd` and `gpmd` do not survive one - and refusing those
    /// renders would block ordinary edits to protect data the container was never going to keep.
    public static func missingEssentialTracks(
        source: [AVMediaType],
        output: [AVMediaType]
    ) -> [AVMediaType] {
        [.audio, .video].filter { type in
            output.filter { $0 == type }.count < source.filter { $0 == type }.count
        }
    }

    /// Maps the output URL's path extension to the `AVFileType` the export session expects.
    ///
    /// Runs before the session exists, so it has no alternatives to offer -- that answer belongs
    /// to the session.
    /// Whether AVFoundation can *write* this container - and so whether a trim of it can be applied
    /// at all.
    ///
    /// Reading and writing are different capabilities here, and MXF is the case that separates
    /// them: the Pro Video Formats readers make it readable, while
    /// `AVAssetExportSession.supportedFileTypes` still excludes `org.smpte.mxf` - measured
    /// 2026-09-08 on both a Resolve OP-Atom export and an Adobe OP1a file. A trim writes back to
    /// the source's own extension, so offering one would fail at
    /// ``VideoEditError/unsupportedOutputContainer(_:alternatives:)`` after the user had made the
    /// edit.
    ///
    /// Asked of the container rather than the session because a UI gate is synchronous and per
    /// selection; the session's own check at render time is what actually refuses.
    public static func canWriteContainer(of url: URL) -> Bool {
        !MXFMetadata.isMXF(url: url)
    }

    /// Whether an orientation can be written into this container without re-encoding: MOV, MP4 and
    /// M4V. A protected file is refused by the caller, since that is not a container question.
    public static func canWriteOrientation(of url: URL) -> Bool {
        canWriteContainer(of: url) && ["mov", "mp4", "m4v"].contains(url.pathExtension.lowercased())
    }

    private static func fileType(for url: URL) throws -> AVFileType {
        guard let utType = UTType(filenameExtension: url.pathExtension) else {
            throw VideoEditError.unsupportedOutputContainer(url.pathExtension, alternatives: [])
        }
        return AVFileType(rawValue: utType.identifier)
    }

    /// The path extensions naming a set of `AVFileType`s -- an `AVFileType` is a UTI, and printing
    /// one at the user would be unreadable. A type the system has no extension for is dropped.
    static func pathExtensions(for fileTypes: [AVFileType]) -> [String] {
        Set(fileTypes.compactMap { UTType($0.rawValue)?.preferredFilenameExtension }).sorted()
    }
}
