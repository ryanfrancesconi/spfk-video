// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import Foundation

/// Video stream technical properties (resolution, frame rate, codec, pixel aspect ratio,
/// rotation), read via AVFoundation (`AVAssetTrack`) rather than TagLib — these are
/// stream-technical facts, not tags. `nil` for pure-audio files.
public struct VideoTrackProperties: Hashable, Sendable, Codable {
    /// Pixel width of the video track's natural (untransformed) size.
    public var width: Int?

    /// Pixel height of the video track's natural (untransformed) size.
    public var height: Int?

    /// Nominal frame rate in frames per second, as reported by `AVAssetTrack.nominalFrameRate`.
    public var frameRate: Float?

    /// Video codec identifier (e.g. a four-character-code string like "avc1", "hvc1"),
    /// derived from `AVAssetTrack.formatDescriptions`.
    public var codec: String?

    /// Pixel aspect ratio (width/height of a single pixel — 1.0 for square pixels).
    public var pixelAspectRatio: Double?

    /// Rotation baked into `AVAssetTrack.preferredTransform`, normalized to the nearest
    /// multiple of 90 degrees (0, 90, 180, or 270). This is what a portrait phone-shot
    /// video needs applied to preview right-side-up.
    public var rotationDegrees: Int?

    public init(
        width: Int? = nil,
        height: Int? = nil,
        frameRate: Float? = nil,
        codec: String? = nil,
        pixelAspectRatio: Double? = nil,
        rotationDegrees: Int? = nil
    ) {
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.codec = codec
        self.pixelAspectRatio = pixelAspectRatio
        self.rotationDegrees = rotationDegrees
    }
}
