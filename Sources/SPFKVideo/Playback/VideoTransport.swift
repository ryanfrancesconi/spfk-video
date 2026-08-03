// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import AVFoundation
import Foundation

/// Playback control for a single video: load, play, pause, seek and speed.
///
/// Owns an `AVPlayer` and nothing visual, so the same transport drives an inline preview or a
/// detached window without knowing either exists. A view observes ``eventHandler`` and reads back
/// whatever it needs; the transport never reaches into a view.
///
/// **This does not drive the playhead.** A playhead animation is seeded from the player's timebase
/// so the render server can carry the motion -- see `PlaybackAnimation(player:)` in spfk-ui. The
/// transport's job is to report *when* the seed became stale (``Event/rateChanged``,
/// ``Event/didSeek``), not to interpolate position itself.
@MainActor
public final class VideoTransport {
    /// Everything a view needs to know to re-read state. Deliberately one handler with an event
    /// enum rather than a closure per concern, matching the convention across these packages.
    public enum Event: Sendable, Equatable {
        /// A file finished loading, or failed to. Speeds and duration are only meaningful after this.
        case readyChanged
        /// Playback started, stopped, or changed speed. Any playhead seed is now stale.
        case rateChanged
        /// A seek completed. Any playhead seed is now stale.
        case didSeek
        /// Playback reached the end of the segment.
        case reachedEnd
    }

    public var eventHandler: ((Event) -> Void)?

    public let player = AVPlayer()

    public private(set) var url: URL?

    /// The speed `play()` will use. Setting this while playing changes speed immediately.
    ///
    /// A speed the current item cannot manage is kept as the *selection* but not applied, so
    /// switching to a file that supports it resumes the user's intent rather than silently
    /// resetting them to 1x.
    public var speed: PlaybackSpeed = .normal {
        didSet {
            guard speed != oldValue else { return }
            guard isPlaying else { return }
            applySpeed()
        }
    }

    private var statusObservation: NSKeyValueObservation?
    private var rateObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?

    /// `nonisolated(unsafe)` because `deinit` has to remove the observer and cannot hop to the main
    /// actor to do it. The token is written only from main-actor methods, and `deinit` runs when no
    /// other reference survives, so there is no concurrent access to guard against.
    private nonisolated(unsafe) var endObserver: (any NSObjectProtocol)?

    public init() {
        player.actionAtItemEnd = .pause

        rateObservation = player.observe(\.rate, options: [.new, .old]) { [weak self] _, change in
            guard change.newValue != change.oldValue else { return }
            MainActor.assumeIsolated { self?.eventHandler?(.rateChanged) }
        }

        // `rate` alone is not enough for anything that reads the timebase. It flips to its target
        // the instant playback is *requested*, while the timebase's effective rate stays zero until
        // playback actually begins -- so a listener that anchors an animation on `rate` gets no
        // usable clock and silently falls back to whatever coarse updates it has. `timeControlStatus`
        // reaching `.playing` is the moment the timebase is live.
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new, .old]) {
            [weak self] _, change in
            guard change.newValue != change.oldValue else { return }
            MainActor.assumeIsolated { self?.eventHandler?(.rateChanged) }
        }
    }

    deinit {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    // MARK: - Loading

    public func load(url: URL) {
        unload()
        self.url = url

        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.eventHandler?(.readyChanged) }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.eventHandler?(.reachedEnd) }
        }
    }

    public func unload() {
        player.pause()
        statusObservation = nil

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }

        player.replaceCurrentItem(with: nil)
        url = nil
    }

    // MARK: - State

    public var isReady: Bool {
        player.currentItem?.status == .readyToPlay
    }

    public var isPlaying: Bool {
        player.timeControlStatus != .paused
    }

    /// Seconds, or zero when nothing is loaded. An unloaded transport reporting zero rather than
    /// NaN keeps every caller from having to guard `CMTimeGetSeconds` themselves.
    public var duration: TimeInterval {
        guard let item = player.currentItem else { return 0 }
        let seconds = CMTimeGetSeconds(item.duration)
        return seconds.isFinite ? seconds : 0
    }

    public var currentTime: TimeInterval {
        let seconds = CMTimeGetSeconds(player.currentTime())
        return seconds.isFinite ? seconds : 0
    }

    /// The speeds the loaded item can actually play. Empty until the item is ready.
    public var availableSpeeds: [PlaybackSpeed] {
        guard let item = player.currentItem else { return [] }
        return PlaybackSpeed.available(on: item)
    }

    // MARK: - Transport

    public func play() {
        guard isReady else { return }

        // Restarting from the end is what a user means by pressing play there, rather than nothing
        // happening because the playhead is already parked at the last frame.
        if duration > 0, currentTime >= duration - Self.endEpsilon {
            player.seek(to: .zero)
        }

        applySpeed()
    }

    public func pause() {
        player.pause()
    }

    public func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    /// Steps whole frames, forward on a positive count and backward on a negative one.
    ///
    /// Uses `AVPlayerItem.step(byCount:)` rather than seeking by a computed frame duration, so it
    /// lands on real frame boundaries without this type needing to know the frame rate — which is
    /// not constant in every container anyway.
    ///
    /// Stepping pauses first: a frame step during playback is immediately overtaken and reads as
    /// nothing having happened.
    public func stepFrames(_ count: Int) {
        guard let item = player.currentItem, isReady, count != 0 else { return }
        guard count > 0 ? item.canStepForward : item.canStepBackward else { return }

        pause()
        item.step(byCount: count)
        eventHandler?(.didSeek)
    }

    /// Whether frame stepping is possible in a direction. Once an item is ready these do not change,
    /// even at the very start or end of the clip.
    public func canStepFrames(forward: Bool) -> Bool {
        guard let item = player.currentItem, isReady else { return false }
        return forward ? item.canStepForward : item.canStepBackward
    }

    /// Moves the playhead by `seconds` relative to where it is, clamped to the clip.
    public func step(by seconds: TimeInterval) {
        guard isReady else { return }
        pause()
        seek(to: currentTime + seconds)
    }

    public func seek(to time: TimeInterval, precise: Bool = true) {
        guard isReady else { return }

        let clamped = min(max(0, time), duration)
        let target = CMTime(seconds: clamped, preferredTimescale: 600)
        let tolerance = precise ? CMTime.zero : CMTime.positiveInfinity

        player.seek(to: target, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] _ in
            MainActor.assumeIsolated { self?.eventHandler?(.didSeek) }
        }
    }

    // MARK: - Private

    /// Playback within a frame of the end counts as being at the end.
    private static let endEpsilon: TimeInterval = 1.0 / 60

    private func applySpeed() {
        guard let item = player.currentItem, speed.isAvailable(on: item) else {
            player.playImmediately(atRate: PlaybackSpeed.normal.rate)
            return
        }

        player.playImmediately(atRate: speed.rate)
    }
}
