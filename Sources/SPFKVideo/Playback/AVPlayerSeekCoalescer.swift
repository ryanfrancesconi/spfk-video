// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import AVFoundation
import Foundation

/// Collapses seek requests that arrive faster than `AVPlayer` can serve them.
///
/// A drag emits one seek per mouse-move. Issued directly, each one cancels the one still in flight,
/// so the picture can starve — no seek survives long enough to deliver a frame. Performing the
/// first and the newest, and dropping what fell between, lands on the position last asked for.
///
/// Shared rather than written per player owner: both surfaces that drive an `AVPlayer` here need it,
/// and a second copy would be a second set of in-flight bookkeeping to get wrong.
@MainActor
public final class AVPlayerSeekCoalescer {
    /// Called when the playhead settles — after a seek that nothing superseded. Intermediate
    /// positions do not report: a playhead seed rebuilt against one is stale before it is used.
    public var onSettled: (() -> Void)?

    private var isSeekInFlight = false
    private var pendingSeek: (time: CMTime, tolerance: CMTime)?

    /// Whether a request is waiting on the one currently running.
    public var hasPendingSeek: Bool { pendingSeek != nil }

    public var isSeeking: Bool { isSeekInFlight }

    public init() {}

    public func seek(_ player: AVPlayer, to time: CMTime, tolerance: CMTime = .zero) {
        guard !isSeekInFlight else {
            pendingSeek = (time: time, tolerance: tolerance)
            return
        }

        perform(player, time: time, tolerance: tolerance)
    }

    /// Drops anything in flight or waiting. For an owner replacing or clearing its item — a pending
    /// seek names a position in a file that is going away.
    public func cancelPending() {
        isSeekInFlight = false
        pendingSeek = nil
    }

    private func perform(_ player: AVPlayer, time: CMTime, tolerance: CMTime) {
        isSeekInFlight = true

        player.seek(to: time, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }

                self.isSeekInFlight = false

                guard let next = self.pendingSeek else {
                    self.onSettled?()
                    return
                }

                self.pendingSeek = nil
                self.perform(player, time: next.time, tolerance: next.tolerance)
            }
        }
    }
}
