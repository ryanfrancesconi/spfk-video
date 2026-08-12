// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import Foundation
import SPFKBase
import Testing

@testable import SPFKVideo

/// Pure data-formatting tests for `VideoTechnicalProperties` — no video fixture needed,
/// since population is driven entirely by synthetic `VideoTrackProperties`/
/// `QuickTimeUserData` structs, not file I/O.
@Suite
struct VideoTechnicalPropertiesTests {
    @Test func defaultInitHasAllNilValues() {
        let properties = VideoTechnicalProperties()

        for (_, value) in properties.dictionary {
            #expect(value == nil)
        }
    }

    @Test func nilVideoTrackAndQuickTimeUserDataLeavesAllNil() {
        let properties = VideoTechnicalProperties(videoTrack: nil, quickTimeUserData: nil)

        for (_, value) in properties.dictionary {
            #expect(value == nil)
        }
    }

    @Test func formatsResolutionFromWidthAndHeight() {
        let videoTrack = VideoTrackProperties(width: 1920, height: 1080)
        let properties = VideoTechnicalProperties(videoTrack: videoTrack, quickTimeUserData: nil)

        #expect(properties.dictionary[.resolution] == "1920 \u{00D7} 1080")
    }

    @Test func resolutionStaysNilWhenWidthOrHeightMissing() {
        let videoTrack = VideoTrackProperties(width: 1920, height: nil)
        let properties = VideoTechnicalProperties(videoTrack: videoTrack, quickTimeUserData: nil)

        // dictionary[key] is String?? (every key is present with an explicit String?
        // value) — flatten with `?? nil` before comparing, or `== nil` checks "key
        // missing" (never true here) instead of "value is nil".
        #expect((properties.dictionary[.resolution] ?? nil) == nil)
    }

    @Test func showsTheTimecodeTrackStartValue() {
        let videoTrack = VideoTrackProperties(
            preciseFrameRate: .fps29_97d,
            startTimecodeString: "01:00:00;01"
        )
        let properties = VideoTechnicalProperties(videoTrack: videoTrack, quickTimeUserData: nil)

        #expect(properties.dictionary[.startTimecode] == "01:00:00;01")
    }

    /// Unlike a duration, which exists whether or not it can be expressed at a known rate, a
    /// container with no timecode track states no start at all — so the row is blank rather than
    /// falling back to a zero timecode the file never claimed.
    @Test func startTimecodeStaysNilWithoutATimecodeTrack() {
        let videoTrack = VideoTrackProperties(nominalFrameRate: 29.97, duration: 120)
        let properties = VideoTechnicalProperties(videoTrack: videoTrack, quickTimeUserData: nil)

        #expect((properties.dictionary[.startTimecode] ?? nil) == nil)
        #expect(properties.dictionary[.duration] != nil)
    }

    @Test func formatsFrameRateToTwoDecimalPlaces() {
        let videoTrack = VideoTrackProperties(nominalFrameRate: 29.97)
        let properties = VideoTechnicalProperties(videoTrack: videoTrack, quickTimeUserData: nil)

        #expect(properties.dictionary[.frameRate] == "29.97 fps")
    }

    @Test func passesCodecThroughUnmodified() {
        let videoTrack = VideoTrackProperties(codec: "hvc1")
        let properties = VideoTechnicalProperties(videoTrack: videoTrack, quickTimeUserData: nil)

        #expect(properties.dictionary[.codec] == "hvc1")
    }

    /// A container with no explicit PixelAspectRatio extension implies 1:1 square pixels
    /// (the common case), not "unknown" — the row should show "1.000", not be blank.
    @Test func pixelAspectRatioDefaultsToOneWhenNil() {
        let videoTrack = VideoTrackProperties(pixelAspectRatio: nil)
        let properties = VideoTechnicalProperties(videoTrack: videoTrack, quickTimeUserData: nil)

        #expect(properties.dictionary[.pixelAspectRatio] == "1.000")
    }

    @Test func formatsExplicitPixelAspectRatio() {
        let videoTrack = VideoTrackProperties(pixelAspectRatio: 1.306)
        let properties = VideoTechnicalProperties(videoTrack: videoTrack, quickTimeUserData: nil)

        #expect(properties.dictionary[.pixelAspectRatio] == "1.306")
    }

    @Test func formatsRotationWithDegreeSymbol() {
        let videoTrack = VideoTrackProperties(rotationDegrees: 90)
        let properties = VideoTechnicalProperties(videoTrack: videoTrack, quickTimeUserData: nil)

        #expect(properties.dictionary[.rotation] == "90\u{00B0}")
    }

    @Test func rotationStaysNilWhenNotPresent() {
        let videoTrack = VideoTrackProperties(rotationDegrees: nil)
        let properties = VideoTechnicalProperties(videoTrack: videoTrack, quickTimeUserData: nil)

        #expect((properties.dictionary[.rotation] ?? nil) == nil)
    }

    @Test func formatsGPSLocationToFiveDecimalPlaces() {
        let quickTimeUserData = QuickTimeUserData(latitude: 45.3496, longitude: -121.8368)
        let properties = VideoTechnicalProperties(videoTrack: nil, quickTimeUserData: quickTimeUserData)

        #expect(properties.dictionary[.gpsLocation] == "45.34960, -121.83680")
    }

    @Test func gpsLocationStaysNilWhenOnlyLatitudePresent() {
        let quickTimeUserData = QuickTimeUserData(latitude: 45.3496, longitude: nil)
        let properties = VideoTechnicalProperties(videoTrack: nil, quickTimeUserData: quickTimeUserData)

        #expect((properties.dictionary[.gpsLocation] ?? nil) == nil)
    }

    @Test func passesDeviceMakeModelSoftwareThroughUnmodified() {
        let quickTimeUserData = QuickTimeUserData(
            deviceMake: "Apple", deviceModel: "iPhone 15 Pro", deviceSoftware: "26.5"
        )
        let properties = VideoTechnicalProperties(videoTrack: nil, quickTimeUserData: quickTimeUserData)

        #expect(properties.dictionary[.deviceMake] == "Apple")
        #expect(properties.dictionary[.deviceModel] == "iPhone 15 Pro")
        #expect(properties.dictionary[.deviceSoftware] == "26.5")
    }

    @Test func captureDateStaysNilWhenNotPresent() {
        let quickTimeUserData = QuickTimeUserData()
        let properties = VideoTechnicalProperties(videoTrack: nil, quickTimeUserData: quickTimeUserData)

        #expect((properties.dictionary[.captureDate] ?? nil) == nil)
    }

    @Test func formatsCaptureDateAsNonEmptyString() {
        let date = Date(timeIntervalSince1970: 0)
        let quickTimeUserData = QuickTimeUserData(creationDate: date)
        let properties = VideoTechnicalProperties(videoTrack: nil, quickTimeUserData: quickTimeUserData)

        let captureDate = properties.dictionary[.captureDate] ?? nil
        #expect(!(captureDate ?? "").isEmpty)
    }

    // MARK: - Key

    @Test func displayNameIsNotEmptyForAllCases() {
        for key in VideoTechnicalProperties.Key.allCases {
            #expect(!key.displayName.isEmpty)
        }
    }
}
