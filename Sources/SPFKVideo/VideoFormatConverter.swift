// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import AVFoundation
import Foundation
import SPFKBase
import SPFKFileSystem

/// Converts one video file with an `AVAssetExportSession` preset.
///
/// The output is written elsewhere and moved into place only once it is checked for the audio and video the
/// input had, so it never exists half-written. Cancelling the calling task stops the export.
public struct VideoFormatConverter: Sendable {
    public let source: VideoConversionSource

    /// Exports to run at once. The hardware encoder is shared, so more add little: measured on seven camera
    /// clips to HEVC 1080p, 1.1 s a clip one at a time, 0.9 s two at a time and 0.84 s four at a time.
    public static let preferredBatchSize = 2

    /// Forces the pre-macOS 15 export path. See ``VideoEditRenderer``.
    var usesLegacyExportPath = !OSVersion.macOS15.isAvailable

    public init(source: VideoConversionSource) {
        self.source = source
    }

    /// Converts the source and returns it as written, its output renamed by a `.unique` conflict. Neither
    /// `input` nor `originalInput` is ever written.
    public func convert() async throws -> VideoConversionSource {
        try Task.checkCancellation()

        // Ahead of the conflict handling, which replaces an existing output.
        for protected in [source.input, source.originalInput].compactMap({ $0 })
            where FileSystem.isSameFile(source.output, protected)
        {
            throw VideoConversionError.outputReplacesInput(protected)
        }

        var converted = source

        if converted.output.exists {
            switch converted.conflictScheme {
            case .overwrite:
                break

            case .error:
                throw VideoConversionError.outputExists(converted.output)

            case .unique:
                converted.output = FileSystem.nextAvailableURL(converted.output)
            }
        }

        let asset = AVURLAsset(url: source.input)
        let session = try await makeSession(for: asset)

        let workDirectory = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: converted.output,
            create: true
        )

        defer { try? FileManager.default.removeItem(at: workDirectory) }

        let written = workDirectory.appending(component: converted.output.lastPathComponent, directoryHint: .notDirectory)

        do {
            try await VideoExport.run(session, to: written, as: source.options.container.fileType, legacy: usesLegacyExportPath)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw VideoConversionError.exportFailed(source.input, underlying: error)
        }

        let missing = try await VideoExport.missingTracks(
            source: asset,
            sourceURL: source.input,
            output: written,
            comparing: source.options.preset.copiesTracks ? .count : .presence
        )

        guard missing.isEmpty else {
            throw VideoConversionError.tracksLost(source.input, missing: missing.map { $0 == .audio ? "audio" : "video" })
        }

        #if os(macOS)
            if source.copiesFinderTags {
                try (source.originalInput ?? source.input).copyFinderTags(to: written)
            }
        #endif

        try Task.checkCancellation()

        if converted.output.exists {
            // New metadata only, or the replaced file's own Finder tags survive into its replacement.
            _ = try FileManager.default.replaceItemAt(converted.output, withItemAt: written, options: .usingNewMetadataOnly)
        } else {
            try FileManager.default.moveItem(at: written, to: converted.output)
        }

        return converted
    }

    /// The session for the preset and container, its time range set from the trim.
    private func makeSession(for asset: AVURLAsset) async throws -> AVAssetExportSession {
        let options = source.options
        let isProtected: Bool

        do {
            isProtected = try await asset.load(.hasProtectedContent)
        } catch {
            throw VideoConversionError.unreadable(source.input, underlying: error)
        }

        guard !isProtected else {
            throw VideoConversionError.protectedContent(source.input)
        }

        guard let session = AVAssetExportSession(asset: asset, presetName: options.preset.presetName) else {
            throw VideoConversionError.presetUnavailable(options.preset)
        }

        guard session.supportedFileTypes.contains(options.container.fileType) else {
            throw VideoConversionError.unsupportedContainer(
                options.container,
                preset: options.preset,
                alternatives: VideoEditRenderer.pathExtensions(for: session.supportedFileTypes)
            )
        }

        if let trim = source.trim, !trim.isEmpty {
            session.timeRange = try await VideoExport.timeRange(for: trim, in: asset)
        }

        return session
    }
}
