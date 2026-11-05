// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import AVFoundation
import Foundation
import UniformTypeIdentifiers

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

    /// The system's name for the type and its extension, as the image formats are listed.
    public var title: String {
        "\(UTType(fileType.rawValue)?.localizedDescription ?? rawValue) (\(pathExtension))"
    }
}
