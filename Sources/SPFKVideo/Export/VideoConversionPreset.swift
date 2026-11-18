// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import AVFoundation
import Foundation

/// An `AVAssetExportSession` preset a video converts with. The raw values are stored in saved settings.
///
/// A preset that names a size scales down to fit it and never scales up.
public enum VideoConversionPreset: String, Codable, CaseIterable, Sendable {
    /// Copies the tracks without re-encoding, into another container.
    case passthrough
    case h264_720p
    case h264_1080p
    case h264_2160p
    case hevc1080p
    case hevc2160p
    case hevcHighestQuality
    case proRes422
    case proRes4444

    public var presetName: String {
        switch self {
        case .passthrough: AVAssetExportPresetPassthrough
        case .h264_720p: AVAssetExportPreset1280x720
        case .h264_1080p: AVAssetExportPreset1920x1080
        case .h264_2160p: AVAssetExportPreset3840x2160
        case .hevc1080p: AVAssetExportPresetHEVC1920x1080
        case .hevc2160p: AVAssetExportPresetHEVC3840x2160
        case .hevcHighestQuality: AVAssetExportPresetHEVCHighestQuality
        case .proRes422: AVAssetExportPresetAppleProRes422LPCM
        case .proRes4444: AVAssetExportPresetAppleProRes4444LPCM
        }
    }

    public var title: String {
        switch self {
        case .passthrough: localized("Passthrough")
        case .h264_720p: "H.264 720p"
        case .h264_1080p: "H.264 1080p"
        case .h264_2160p: "H.264 4K"
        case .hevc1080p: "HEVC 1080p"
        case .hevc2160p: "HEVC 4K"
        case .hevcHighestQuality: localized("HEVC Highest Quality")
        case .proRes422: "ProRes 422"
        case .proRes4444: "ProRes 4444"
        }
    }

    /// ProRes is written only to QuickTime movies.
    public var requiresMOV: Bool {
        switch self {
        case .proRes422, .proRes4444: true
        default: false
        }
    }

    /// Every track is copied, so the output keeps as many as the source had. A re-encode mixes the
    /// audio tracks into one.
    var copiesTracks: Bool {
        self == .passthrough
    }
}
