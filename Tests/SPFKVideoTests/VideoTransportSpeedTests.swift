// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import AVFoundation
import Foundation
import SPFKTesting
import Testing

@testable import SPFKVideo

/// What the transport will actually play at, as against what has been selected.
@MainActor
struct VideoTransportSpeedTests {
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

    /// Nothing loaded plays at nothing but 1x, so a selection made before a file arrives does not
    /// claim a rate the player is not running at.
    @Test func reportsNormalWithNothingLoaded() {
        let transport = VideoTransport()
        transport.speed = .quadruple

        #expect(transport.speed == .quadruple)
        #expect(transport.effectiveSpeed == .normal)
    }

    /// The whole invariant in one line: what the bar shows is a rate the item can actually play.
    /// A readout free to show anything else is how `0.25x` ends up over a file playing at `1x`.
    @Test func theEffectiveSpeedIsAlwaysOneTheItemCanPlay() async {
        let transport = await loadedTransport()

        guard let item = transport.player.currentItem, transport.isReady else {
            Issue.record("item never became ready")
            return
        }

        for speed in PlaybackSpeed.allCases {
            transport.speed = speed
            #expect(transport.effectiveSpeed.isAvailable(on: item))
        }
    }

    /// An available selection is played as chosen — the clamp must not be a blanket reset.
    @Test func anAvailableSelectionIsTheEffectiveSpeed() async {
        let transport = await loadedTransport()

        guard transport.isReady else { return }

        transport.speed = .double

        #expect(transport.effectiveSpeed == .double)
    }

    /// The selection survives a file that cannot manage it, so opening one that can resumes the
    /// user's intent rather than silently resetting them to 1x.
    @Test func theSelectionOutlivesAFileThatCannotManageIt() async {
        let transport = await loadedTransport()

        transport.speed = .quadruple
        transport.unload()

        #expect(transport.speed == .quadruple)
        #expect(transport.effectiveSpeed == .normal)
    }
}
