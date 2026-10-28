// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import Foundation
import Testing

@testable import SPFKVideo

@MainActor
extension VideoTransport {
    /// A muted transport that has loaded `url`, returned once the item is ready (or has failed)
    /// and `condition` holds. Woken by the transport's own events rather than a polling deadline,
    /// so a loaded machine delays it instead of failing it.
    ///
    /// Leaves `eventHandler` nil; a test that observes events sets its own after this returns.
    static func loaded(
        url: URL,
        timeout: Duration = .seconds(120),
        until condition: @escaping @MainActor (VideoTransport) -> Bool = { _ in true }
    ) async -> VideoTransport {
        let transport = VideoTransport()
        transport.player.isMuted = true

        let (events, continuation) = AsyncStream.makeStream(of: Event.self)
        transport.eventHandler = { continuation.yield($0) }

        // A backstop against a hang only; the wait ends on an event.
        let backstop = Task {
            try? await Task.sleep(for: timeout)
            continuation.finish()
        }

        transport.load(url: url)

        let isSettled = {
            transport.player.currentItem?.status == .failed || (transport.isReady && condition(transport))
        }

        if !isSettled() {
            for await _ in events where isSettled() {
                break
            }
        }

        backstop.cancel()
        continuation.finish()
        transport.eventHandler = nil

        return transport
    }
}
