// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import Foundation
import OrderedCollections

/// Read-only video-technical fields (resolution, frame rate, codec, pixel aspect ratio,
/// rotation, GPS location, device make/model/software, capture date), pre-formatted as
/// localized display strings keyed by ``Key``.
///
/// This is the presentation-ready data model only — it has no view-layer dependency.
/// Consumers that wire these fields into an AppKit UI (row insertion, GPS map-pin buttons,
/// etc.) do so via their own extension of this type, e.g. `spfk-shadowtag-ui`'s
/// `VideoTechnicalProperties+PropertiesGroupView.swift`.
///
/// `.captureDate` is deliberately distinct from filesystem creation/modification dates:
/// it's the QuickTime user-data creation date, i.e. when the footage was actually recorded.
public struct VideoTechnicalProperties: Sendable, Hashable {
    public enum Key: String, CaseIterable, Sendable {
        case resolution = "Resolution"
        case frameRate = "Frame Rate"
        case codec = "Codec"
        case pixelAspectRatio = "Pixel Aspect Ratio"
        case rotation = "Rotation"
        case gpsLocation = "GPS Location"
        case deviceMake = "Device Make"
        case deviceModel = "Device Model"
        case deviceSoftware = "Device Software"
        case captureDate = "Capture Date"

        /// - Note: a per-case `switch` with literal `localized(...)` calls, not
        /// `NSLocalizedString(rawValue, ...)` — Xcode's string-catalog extraction only
        /// picks up literal arguments at the call site, not a value resolved through an
        /// enum's `rawValue` at runtime.
        public var displayName: String {
            switch self {
            case .resolution: localized("Resolution")
            case .frameRate: localized("Frame Rate")
            case .codec: localized("Codec")
            case .pixelAspectRatio: localized("Pixel Aspect Ratio")
            case .rotation: localized("Rotation")
            case .gpsLocation: localized("GPS Location")
            case .deviceMake: localized("Device Make")
            case .deviceModel: localized("Device Model")
            case .deviceSoftware: localized("Device Software")
            case .captureDate: localized("Capture Date")
            }
        }
    }

    public var dictionary: OrderedDictionary<Key, String?> = [
        .resolution: nil,
        .frameRate: nil,
        .codec: nil,
        .pixelAspectRatio: nil,
        .rotation: nil,
        .gpsLocation: nil,
        .deviceMake: nil,
        .deviceModel: nil,
        .deviceSoftware: nil,
        .captureDate: nil,
    ]

    public init() {}

    public init(videoTrack: VideoTrackProperties?, quickTimeUserData: QuickTimeUserData?) {
        if let videoTrack {
            if let width = videoTrack.width, let height = videoTrack.height {
                dictionary[.resolution] = "\(width) \u{00D7} \(height)"
            }
            if let frameRate = videoTrack.nominalFrameRate {
                dictionary[.frameRate] = String(format: "%.2f fps", frameRate)
            }
            dictionary[.codec] = videoTrack.codec
            // nil means the container has no explicit PixelAspectRatio extension, which
            // implies 1:1 square pixels (the common case) rather than "unknown" — display
            // that default rather than leaving the row blank.
            dictionary[.pixelAspectRatio] = String(format: "%.3f", videoTrack.pixelAspectRatio ?? 1.0)
            if let rotationDegrees = videoTrack.rotationDegrees {
                dictionary[.rotation] = "\(rotationDegrees)\u{00B0}"
            }
        }

        if let quickTimeUserData {
            if let latitude = quickTimeUserData.latitude, let longitude = quickTimeUserData.longitude {
                dictionary[.gpsLocation] = String(format: "%.5f, %.5f", latitude, longitude)
            }
            dictionary[.deviceMake] = quickTimeUserData.deviceMake
            dictionary[.deviceModel] = quickTimeUserData.deviceModel
            dictionary[.deviceSoftware] = quickTimeUserData.deviceSoftware
            if let creationDate = quickTimeUserData.creationDate {
                dictionary[.captureDate] = captureDateFormatter.string(from: creationDate)
            }
        }
    }
}

/// Matches `SPFKUtils`' `Date.mediumString` style (medium date, short time, current locale) —
/// duplicated here rather than depending on `SPFKUtils`, which would pull in `spfk-audio-base`,
/// `spfk-filesystem`, and other unrelated packages transitively for a single formatter.
private let captureDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    formatter.locale = .current
    return formatter
}()
