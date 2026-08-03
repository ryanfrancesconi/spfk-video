// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import AVFoundation
import Foundation

/// A selectable playback speed.
///
/// A fixed set rather than a free rate, because these are menu choices. `AVPlayer.rate` still takes
/// any `Float`, so a caller wanting a scrub rate is not blocked by this type -- it exists to give
/// the UI a stable list with stable labels.
/// Raw value is `Float` to match `AVPlayer.rate` and `playImmediately(atRate:)`, which are the only
/// things a speed is ever handed to. (The `Double` on `PlaybackAnimation.rate` is a different
/// quantity — a `Float64` *measured* off the timebase, not a selected one.)
public enum PlaybackSpeed: Float, CaseIterable, Sendable {
    case quarter = 0.25
    case half = 0.5
    case threeQuarter = 0.75
    case normal = 1
    case oneAndAHalf = 1.5
    case double = 2
    case quadruple = 4

    public var rate: Float { rawValue }

    /// Display label, e.g. `1x` or `0.5x`. Deliberately not localized: these are numerals with an
    /// `x`, and they read the same in every language TorchTag ships.
    public var label: String {
        rawValue == rawValue.rounded()
            ? "\(Int(rawValue))x"
            : "\(rawValue)x"
    }
}

// MARK: - Availability

extension PlaybackSpeed {
    /// Whether an item can actually play at this speed.
    ///
    /// Per `AVPlayerItem`'s documentation, **every ready item plays between 1x and 2x inclusive**
    /// regardless of `canPlayFastForward` -- that flag reports whether rates *beyond* 2x are
    /// possible. Anything below 1x needs `canPlaySlowForward`. Getting this backwards would hide
    /// speeds that work, or offer ones that silently do nothing.
    public func isAvailable(on item: AVPlayerItem) -> Bool {
        guard item.status == .readyToPlay else { return false }

        if rawValue < 1 { return item.canPlaySlowForward }
        if rawValue > 2 { return item.canPlayFastForward }
        return true
    }

    /// The speeds an item can play, in ascending order.
    public static func available(on item: AVPlayerItem) -> [PlaybackSpeed] {
        allCases.filter { $0.isAvailable(on: item) }
    }
}
