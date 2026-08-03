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
