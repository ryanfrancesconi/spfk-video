// Copyright Ryan Francesconi. All Rights Reserved.

import AVFoundation
import Foundation
import SPFKBase
import SPFKTesting
import SwiftTimecode
import Testing

@testable import SPFKVideo

/// A `tmcd` track states both a rate and a start position, and the reader long kept only the rate.
@Suite
final class VideoTrackStartTimecodeTests {
    @Test func readsNonZeroDropFrameStart() async throws {
        let url = TestBundleResources.shared.sample_timecode_offset_mov

        let properties = try #require(await VideoTrackReader.read(from: url).videoTrack)

        #expect(properties.preciseFrameRate == .fps29_97d)
        #expect(properties.startTimecodeString == "01:00:00;01")

        let start = try #require(properties.startTimecode)
        #expect(start.frameRate == .fps29_97d)
        #expect(start.components.hours == 1)
        #expect(start.components.frames == 1)
    }

    /// A file whose timecode track reads zero is stating a start, not failing to state one — the
    /// resolver's precedence depends on telling those apart.
    @Test func readsZeroStartAsPresent() async throws {
        let url = TestBundleResources.shared.sample_timecode_mov

        let properties = try #require(await VideoTrackReader.read(from: url).videoTrack)

        #expect(properties.startTimecodeString == "00:00:00:00")
        #expect(properties.startTimecode?.realTimeValue == 0)
    }

    /// A container with no timecode track has to report absence rather than a zero start.
    @Test func fileWithoutTimecodeTrackHasNoStart() async throws {
        let url = TestBundleResources.shared.sample_mov

        let properties = try #require(await VideoTrackReader.read(from: url).videoTrack)

        #expect(properties.startTimecodeString == nil)
        #expect(properties.startTimecode == nil)
    }

    /// The string is stored rather than a frame count because the separator carries the drop flag,
    /// and `Timecode` is not `Codable`. A round trip through the cache has to preserve both.
    @Test func startTimecodeSurvivesCodableRoundTrip() throws {
        let properties = VideoTrackProperties(
            nominalFrameRate: 29.97,
            preciseFrameRate: .fps29_97d,
            startTimecodeString: "01:00:00;01"
        )

        let data = try JSONEncoder().encode(properties)
        let decoded = try JSONDecoder().decode(VideoTrackProperties.self, from: data)

        #expect(decoded.startTimecodeString == "01:00:00;01")
        #expect(decoded.startTimecode?.frameRate == .fps29_97d)
    }

    /// Anything cached before the `tmcd` start value was read is missing it, and only the parser
    /// version distinguishes that from a file that legitimately has none.
    @Test func valueCachedBeforeStartTimecodeReadsAsOutdated() {
        let stale = VideoTrackProperties(preciseFrameRate: .fps29_97d, parserVersion: 3)
        #expect(stale.isOutdated)

        let current = VideoTrackProperties(preciseFrameRate: .fps29_97d)
        #expect(!current.isOutdated)
    }

    /// The rate and the stored string come from one read and have to stay consistent. When they
    /// aren't, the position is unrepresentable rather than approximately right — 30 frames is not a
    /// valid frame number at 29.97.
    @Test func startTimecodeIsNilWhenStringDoesNotFitTheRate() {
        let properties = VideoTrackProperties(
            preciseFrameRate: .fps29_97d,
            startTimecodeString: "01:00:00;45"
        )

        #expect(properties.startTimecode == nil)
    }
}
