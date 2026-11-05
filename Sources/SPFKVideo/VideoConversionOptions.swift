// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import Foundation

/// How a video converts: the preset it encodes with and the container it is written to.
public struct VideoConversionOptions: Codable, Hashable, Sendable {
    public var preset: VideoConversionPreset
    public var container: VideoConversionContainer

    public init(preset: VideoConversionPreset = .hevc1080p, container: VideoConversionContainer = .mov) {
        self.preset = preset
        self.container = container
    }

    private enum CodingKeys: String, CodingKey {
        case preset
        case container
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = VideoConversionOptions()

        preset = try container.decodeIfPresent(VideoConversionPreset.self, forKey: .preset) ?? defaults.preset
        self.container = try container.decodeIfPresent(VideoConversionContainer.self, forKey: .container) ?? defaults.container
    }
}
