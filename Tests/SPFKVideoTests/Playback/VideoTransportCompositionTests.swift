// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import AVFoundation
import Foundation
import SPFKTesting
import Testing

@testable import SPFKVideo

@MainActor
struct VideoTransportCompositionTests {
    private func until(_ condition: () -> Bool) async -> Bool {
        for _ in 0 ..< 300 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    /// Removing a composition from a playing item makes the player pause itself; listeners must hear
    /// that it stopped.
    @Test func aPauseThePlayerMakesItselfIsReported() async throws {
        let transport = await VideoTransport.loaded(url: TestBundleResources.shared.sample_mov)
        let asset = try #require(transport.asset)
        transport.videoComposition = try await VideoFrameFilter.composition(
            for: asset,
            filter: VideoFrameFilter { image, _, _ in image }
        )

        var reported: [Bool] = []
        transport.eventHandler = { [weak transport] event in
            if case .rateChanged = event, let transport { reported.append(transport.isPlaying) }
        }

        transport.play()
        #expect(await until { transport.player.timeControlStatus == .playing })

        transport.videoComposition = nil
        try #require(await until { transport.player.timeControlStatus == .paused })

        #expect(!transport.isPlaying)
        #expect(reported.last == false)
    }
}
