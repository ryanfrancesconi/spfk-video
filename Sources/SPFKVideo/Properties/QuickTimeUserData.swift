// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import Foundation

/// QuickTime user-data metadata (GPS location, capture device info, creation date), read via
/// AVFoundation (`AVMetadataItem`) rather than TagLib. Read-only. `nil` for files with no
/// QuickTime user-data (including most pure-audio files).
public struct QuickTimeUserData: Hashable, Sendable, Codable {
    /// Latitude in decimal degrees, parsed from the QuickTime ISO 6709 location string.
    public var latitude: Double?

    /// Longitude in decimal degrees, parsed from the QuickTime ISO 6709 location string.
    public var longitude: Double?

    /// Capture device manufacturer (e.g. "Apple").
    public var deviceMake: String?

    /// Capture device model (e.g. "iPhone 15 Pro").
    public var deviceModel: String?

    /// Capture software/firmware identifier.
    public var deviceSoftware: String?

    /// Original capture creation date, as reported by QuickTime user-data.
    public var creationDate: Date?

    public init(
        latitude: Double? = nil,
        longitude: Double? = nil,
        deviceMake: String? = nil,
        deviceModel: String? = nil,
        deviceSoftware: String? = nil,
        creationDate: Date? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.deviceMake = deviceMake
        self.deviceModel = deviceModel
        self.deviceSoftware = deviceSoftware
        self.creationDate = creationDate
    }
}
