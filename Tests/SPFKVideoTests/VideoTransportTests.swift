// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import AVFoundation
import Foundation
import SPFKTesting
import Testing

@testable import SPFKVideo

@MainActor
struct VideoTransportTests {
    private func loadedTransport() async -> VideoTransport {
        let transport = VideoTransport()
        transport.player.isMuted = true
        transport.load(url: TestBundleResources.shared.sample_mov)

        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, !transport.isReady {
            try? await Task.sleep(for: .milliseconds(25))
        }

        return transport
    }

    // MARK: - Speed availability

    /// Every ready item plays between 1x and 2x whatever the capability flags say -- per
    /// `AVPlayerItem`, `canPlayFastForward` reports whether rates *beyond* 2x work. Reading that
    /// flag as "can play above 1x" would hide speeds that are always available.
    @Test func speedsBetweenOneAndTwoNeedNoCapability() async {
        let transport = await loadedTransport()
        guard let item = transport.player.currentItem, transport.isReady else {
            Issue.record("item never became ready")
            return
        }

        #expect(PlaybackSpeed.normal.isAvailable(on: item))
        #expect(PlaybackSpeed.oneAndAHalf.isAvailable(on: item))
        #expect(PlaybackSpeed.double.isAvailable(on: item))
    }

    /// Nothing is playable until the item is ready, so a speed menu built too early would offer
    /// choices that silently do nothing.
    @Test func noSpeedIsAvailableBeforeTheItemIsReady() {
        let transport = VideoTransport()
        #expect(transport.availableSpeeds.isEmpty)

        let item = AVPlayerItem(url: TestBundleResources.shared.sample_mov)
        #expect(PlaybackSpeed.normal.isAvailable(on: item) == false)
    }

    @Test func availableSpeedsAreAscending() async {
        let transport = await loadedTransport()
        let speeds = transport.availableSpeeds.map(\.rawValue)

        #expect(speeds == speeds.sorted())
        #expect(speeds.isEmpty == false)
    }

    // MARK: - Selection survives an item that cannot manage it

    /// A speed the current file cannot play stays selected rather than being reset, so loading a
    /// file that can play it honors what the user asked for instead of silently dropping them
    /// back to 1x.
    @Test func anUnavailableSpeedRemainsSelected() async {
        let transport = await loadedTransport()
        transport.speed = .quadruple

        #expect(transport.speed == .quadruple)
    }

    // MARK: - Duration and time

    /// Zero rather than NaN when nothing is loaded, so callers do not each have to guard
    /// `CMTimeGetSeconds`.
    @Test func anUnloadedTransportReportsZeroNotNaN() {
        let transport = VideoTransport()

        #expect(transport.duration == 0)
        #expect(transport.currentTime == 0)
        #expect(transport.duration.isNaN == false)
        #expect(transport.currentTime.isNaN == false)
    }

    @Test func loadingReportsTheItemsDuration() async {
        let transport = await loadedTransport()
        #expect(abs(transport.duration - 2) < 0.1)
    }

    // MARK: - Seeking

    @Test func seekingClampsToTheItem() async {
        let transport = await loadedTransport()
        guard transport.isReady else {
            Issue.record("item never became ready")
            return
        }

        transport.seek(to: 99)
        try? await Task.sleep(for: .milliseconds(300))
        #expect(transport.currentTime <= transport.duration + 0.01)

        transport.seek(to: -5)
        try? await Task.sleep(for: .milliseconds(300))
        #expect(transport.currentTime >= 0)
    }

    /// Seeking an empty transport does nothing rather than trapping on a zero duration.
    @Test func seekingAnUnloadedTransportIsSafe() {
        let transport = VideoTransport()
        transport.seek(to: 1)

        #expect(transport.currentTime == 0)
    }

    // MARK: - Unloading

    @Test func unloadingClearsTheItem() async {
        let transport = await loadedTransport()
        #expect(transport.url != nil)

        transport.unload()

        #expect(transport.url == nil)
        #expect(transport.player.currentItem == nil)
        #expect(transport.isPlaying == false)
        #expect(transport.duration == 0)
    }

    // MARK: - Events

    /// A view re-reads state on these, and a seed for the playhead is stale until it does -- so a
    /// seek that reported nothing would leave the playhead extrapolating from the old position.
    @Test func seekingReportsDidSeek() async {
        let transport = await loadedTransport()
        guard transport.isReady else {
            Issue.record("item never became ready")
            return
        }

        var events: [VideoTransport.Event] = []
        transport.eventHandler = { events.append($0) }

        transport.seek(to: 1)

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, !events.contains(.didSeek) {
            try? await Task.sleep(for: .milliseconds(25))
        }

        #expect(events.contains(.didSeek))
    }
}

// MARK: -

struct PlaybackSpeedTests {
    /// The label is what a menu shows, so a whole number must not read as "1.0x".
    @Test func wholeNumbersDropTheDecimal() {
        #expect(PlaybackSpeed.normal.label == "1x")
        #expect(PlaybackSpeed.double.label == "2x")
        #expect(PlaybackSpeed.quadruple.label == "4x")
        #expect(PlaybackSpeed.half.label == "0.5x")
        #expect(PlaybackSpeed.oneAndAHalf.label == "1.5x")
    }

    @Test func rateMatchesTheRawValue() {
        for speed in PlaybackSpeed.allCases {
            #expect(speed.rate == speed.rawValue)
        }
    }
}

// MARK: -

@MainActor
struct VideoTransportSteppingTests {
    private func loadedTransport() async -> VideoTransport {
        let transport = VideoTransport()
        transport.player.isMuted = true
        transport.load(url: TestBundleResources.shared.sample_mov)

        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, !transport.isReady {
            try? await Task.sleep(for: .milliseconds(25))
        }
        return transport
    }

    /// Nothing loaded means nothing to step — and no trap on a nil item.
    @Test func steppingAnUnloadedTransportIsSafe() {
        let transport = VideoTransport()

        transport.stepFrames(1)
        transport.step(by: 1)

        #expect(transport.currentTime == 0)
        #expect(transport.canStepFrames(forward: true) == false)
        #expect(transport.canStepFrames(forward: false) == false)
    }

    /// A zero step is a no-op rather than a seek to the same place, which would still cost a
    /// `didSeek` and a playhead re-anchor.
    @Test func aZeroFrameStepDoesNothing() async {
        let transport = await loadedTransport()

        var events: [VideoTransport.Event] = []
        transport.eventHandler = { events.append($0) }

        transport.stepFrames(0)

        #expect(events.isEmpty)
    }

    /// Stepping by seconds clamps rather than running past either end.
    @Test func steppingBySecondsClampsToTheClip() async {
        let transport = await loadedTransport()
        guard transport.isReady else {
            Issue.record("item never became ready")
            return
        }

        transport.step(by: -5)
        try? await Task.sleep(for: .milliseconds(300))
        #expect(transport.currentTime >= 0)

        transport.step(by: 99)
        try? await Task.sleep(for: .milliseconds(300))
        #expect(transport.currentTime <= transport.duration + 0.01)
    }

    /// A frame step during playback would be immediately overtaken, so it pauses first — otherwise
    /// the command reads as having done nothing.
    @Test func steppingPausesPlayback() async {
        let transport = await loadedTransport()
        guard transport.isReady else {
            Issue.record("item never became ready")
            return
        }

        transport.play()
        try? await Task.sleep(for: .milliseconds(300))

        transport.stepFrames(1)

        #expect(transport.isPlaying == false)
    }
}

// MARK: -

struct VideoDurationDisplayTests {
    /// Duration reads as SMPTE timecode, which is how an edit is actually specified — and how the
    /// transport's own position readout reads, so the two agree.
    @Test func aDurationWithAFrameRateReadsAsTimecode() throws {
        let text = try #require(
            VideoTechnicalProperties.durationString(seconds: 61.5, frameRate: .fps30)
        )

        #expect(text.filter { $0 == ":" }.count == 3)
        #expect(text.hasPrefix("00:01:01"))
    }

    /// A rate SMPTE cannot represent falls back to seconds rather than leaving the row blank — a
    /// coarse number beats nothing.
    @Test func noFrameRateFallsBackToSeconds() {
        #expect(VideoTechnicalProperties.durationString(seconds: 61.5, frameRate: nil) == "61.50 s")
    }

    /// Nothing to show when there is no duration, rather than a zero that reads as a real value.
    @Test func anAbsentOrInvalidDurationShowsNothing() {
        #expect(VideoTechnicalProperties.durationString(seconds: nil, frameRate: .fps30) == nil)
        #expect(VideoTechnicalProperties.durationString(seconds: .nan, frameRate: .fps30) == nil)
        #expect(VideoTechnicalProperties.durationString(seconds: -1, frameRate: .fps30) == nil)
    }

    /// Adding a field the reader populates has to bump the parser version, or everything cached
    /// under the old reader keeps its missing duration forever.
    @Test func theParserVersionWasBumpedForDuration() {
        #expect(VideoTrackProperties.currentParserVersion >= 2)

        var old = VideoTrackProperties(width: 1920, height: 1080, parserVersion: 1)
        #expect(old.isOutdated)

        old.parserVersion = VideoTrackProperties.currentParserVersion
        #expect(old.isOutdated == false)
    }

    /// The Duration row is part of the tab's field set, so it renders wherever those are shown.
    @Test func durationIsAKeyOnTheVideoTab() {
        #expect(VideoTechnicalProperties.Key.allCases.contains(.duration))
        #expect(VideoTechnicalProperties().dictionary.keys.contains(.duration))
    }
}
