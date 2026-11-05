// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import AVFoundation
import Foundation

/// The file a video converts into. The raw values are stored in saved settings.
public enum VideoConversionContainer: String, Codable, CaseIterable, Sendable {
    case mov
    case mp4

    public var fileType: AVFileType {
        switch self {
        case .mov: .mov
        case .mp4: .mp4
        }
    }

    public var pathExtension: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .mov: "QuickTime Movie (mov)"
        case .mp4: "MPEG-4 Movie (mp4)"
        }
    }
}
