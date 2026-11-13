// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import AVFoundation
import CoreMedia
import Foundation

extension VideoEditRenderer {
    /// Whether a ``VideoFrameFilter`` can be rendered into this container: the containers an
    /// orientation can be written to.
    public static func canWriteAdjustments(of url: URL) -> Bool {
        canWriteOrientation(of: url)
    }

    /// The preset a filtered render of `url` re-encodes with: ProRes stays ProRes in a QuickTime movie,
    /// and everything else becomes HEVC at its highest quality.
    ///
    /// - Throws: ``VideoEditError/cannotReencode(_:)`` for ProRes RAW, which has no export preset.
    public static func reencodePreset(for url: URL) async throws -> VideoConversionPreset {
        let codec = try await videoCodec(of: AVURLAsset(url: url))
        return try reencodePreset(codec: codec, pathExtension: url.pathExtension, url: url)
    }

    static func reencodePreset(codec: CMVideoCodecType?, pathExtension: String, url: URL) throws -> VideoConversionPreset {
        let preset: VideoConversionPreset

        switch codec {
        case kCMVideoCodecType_AppleProResRAW, kCMVideoCodecType_AppleProResRAWHQ:
            throw VideoEditError.cannotReencode(url)
        case kCMVideoCodecType_AppleProRes4444, kCMVideoCodecType_AppleProRes4444XQ:
            preset = .proRes4444
        case kCMVideoCodecType_AppleProRes422, kCMVideoCodecType_AppleProRes422HQ,
             kCMVideoCodecType_AppleProRes422LT, kCMVideoCodecType_AppleProRes422Proxy:
            preset = .proRes422
        default:
            preset = .hevcHighestQuality
        }

        if preset.requiresMOV, pathExtension.lowercased() != "mov" {
            return .hevcHighestQuality
        }

        return preset
    }

    /// The first video track's codec, or nil when it has none.
    private static func videoCodec(
        of asset: AVAsset,
        isolation: isolated (any Actor)? = #isolation
    ) async throws -> CMVideoCodecType? {
        guard let track = try await asset.loadTracks(withMediaType: .video).first,
              let format = try await track.load(.formatDescriptions).first
        else { return nil }

        return CMFormatDescriptionGetMediaSubType(format)
    }

    /// The preset name for a filtered render of `asset`, read from the source file.
    ///
    /// A re-encode mixes every audio track into one, so a file with more than one is refused rather
    /// than have the rest dropped.
    func reencodePresetName(for asset: AVAsset) async throws -> String {
        guard try await asset.loadTracks(withMediaType: .audio).count <= 1 else {
            throw VideoEditError.multipleAudioTracks(sourceURL)
        }

        let codec = try await Self.videoCodec(of: asset)
        return try Self.reencodePreset(codec: codec, pathExtension: outputURL.pathExtension, url: sourceURL).presetName
    }

    /// Throws unless every video track of the render shows `asset`'s displayed picture upright: an
    /// identity matrix, and the size the source displays after its matrix, within a pixel.
    func verifyOrientationRendered(from asset: AVAsset, to url: URL) async throws {
        guard let sourceTrack = try await asset.loadTracks(withMediaType: .video).first else { return }

        let expected = try await Self.displayedSize(of: sourceTrack)
        let outputTracks = try await AVURLAsset(url: url).loadTracks(withMediaType: .video)
        var rendered = !outputTracks.isEmpty

        for track in outputTracks {
            let transform = try await track.load(.preferredTransform)
            let size = try await track.load(.naturalSize)

            if !transform.isIdentity || abs(size.width - expected.width) > 1 || abs(size.height - expected.height) > 1 {
                rendered = false
            }
        }

        guard rendered else {
            try? FileManager.default.removeItem(at: url)
            throw VideoEditError.orientationNotWritten(sourceURL)
        }
    }

    private static func displayedSize(
        of track: AVAssetTrack,
        isolation: isolated (any Actor)? = #isolation
    ) async throws -> CGSize {
        let size = try await track.load(.naturalSize).applying(track.load(.preferredTransform))
        return CGSize(width: abs(size.width), height: abs(size.height))
    }
}
