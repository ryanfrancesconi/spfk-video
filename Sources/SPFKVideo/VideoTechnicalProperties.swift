// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import Foundation
import OrderedCollections
import SwiftTimecode

/// Read-only video-technical fields (resolution, frame rate, codec, pixel aspect ratio,
/// rotation, GPS location, device make/model/software, capture date), pre-formatted as
/// localized display strings keyed by ``Key``. The GPS coordinate is additionally kept as raw
/// values (``latitude``/``longitude``) for consumers that need to do more than print it.
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
        case duration = "Duration"
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
            case .duration: localized("Duration")
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
        .duration: nil,
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

    /// The raw capture coordinate behind `dictionary[.gpsLocation]`'s display string, carried
    /// alongside it as data. A consumer feeding a map (e.g. `SPFKUI`'s `PropertiesGroupGPSView`)
    /// needs the actual values -- reformatting them into a string here and parsing them back out
    /// there is lossy and breaks as soon as anything else is appended to the display text.
    public var latitude: Double?
    public var longitude: Double?

    /// A duration as SMPTE timecode, which is how an edit is actually specified.
    ///
    /// Falls back to seconds when the rate is not a standard one `Timecode` can represent — better
    /// a coarse number than a blank row. `nil` only when there is no duration at all.
    static func durationString(seconds: TimeInterval?, frameRate: TimecodeFrameRate?) -> String? {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return nil }

        guard
            let frameRate,
            let timecode = try? Timecode(.realTime(seconds: seconds), at: frameRate)
        else {
            return String(format: "%.2f s", seconds)
        }

        return timecode.stringValue()
    }

    public init() {}

    public init(videoTrack: VideoTrackProperties?, quickTimeUserData: QuickTimeUserData?) {
        if let videoTrack {
            if let width = videoTrack.width, let height = videoTrack.height {
                dictionary[.resolution] = "\(width) \u{00D7} \(height)"
            }
            if let frameRate = videoTrack.nominalFrameRate {
                dictionary[.frameRate] = String(format: "%.2f fps", frameRate)
            }
            dictionary[.duration] = Self.durationString(
                seconds: videoTrack.duration,
                frameRate: videoTrack.preciseFrameRate
            )
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
                self.latitude = latitude
                self.longitude = longitude
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
