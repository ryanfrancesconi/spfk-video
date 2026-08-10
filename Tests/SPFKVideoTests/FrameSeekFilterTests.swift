// Copyright Ryan Francesconi. All Rights Reserved.

import Foundation
import Testing

@testable import SPFKVideo

/// Which drag samples reach `AVPlayer`.
///
/// Measured from a real scrub of a 30 fps file: consecutive seeks 0.042s, 0.031s, 0.024s and 0.016s
/// apart, ending in an exact duplicate timestamp. Everything under a frame period is a decode that
/// cannot change what is on screen.
@MainActor
@Suite
final class FrameSeekFilterTests {
    private let fps = 30.0

    @Test func aSecondTargetInsideTheSameFrameIsDropped() {
        let filter = FrameSeekFilter()

        #expect(filter.allows(1.0, fps: fps))
        #expect(!filter.allows(1.0 + 1.0 / 60, fps: fps))
    }

    @Test func anExactDuplicateIsDropped() {
        let filter = FrameSeekFilter()

        #expect(filter.allows(38.4928, fps: fps))
        #expect(!filter.allows(38.4928, fps: fps))
    }

    @Test func adjacentFramesBothPass() {
        let filter = FrameSeekFilter()

        #expect(filter.allows(1.0, fps: fps))
        #expect(filter.allows(1.0 + 1.0 / fps, fps: fps))
    }

    /// Seeking away and back is two changes of picture, not one target repeated.
    @Test func returningToAnEarlierFramePasses() {
        let filter = FrameSeekFilter()

        #expect(filter.allows(1.0, fps: fps))
        #expect(filter.allows(2.0, fps: fps))
        #expect(filter.allows(1.0, fps: fps))
    }

    /// An unknown rate has to fail open — a dropped seek is a picture that never moves.
    @Test func anAbsentRateAllowsEverything() {
        let filter = FrameSeekFilter()

        #expect(filter.allows(1.0, fps: nil))
        #expect(filter.allows(1.0, fps: nil))
    }

    @Test func aNonPositiveRateAllowsEverything() {
        let filter = FrameSeekFilter()

        #expect(filter.allows(1.0, fps: 0))
        #expect(filter.allows(1.0, fps: 0))
    }

    /// The picture moved by some other means, so the frame last asked for is no longer the frame
    /// being shown, and a seek back to it has work to do.
    @Test func resetLetsTheLastTargetThroughAgain() {
        let filter = FrameSeekFilter()

        #expect(filter.allows(1.0, fps: fps))

        filter.reset()

        #expect(filter.allows(1.0, fps: fps))
    }

    /// 23.976 rather than 24: the frame a target falls in is decided by the real rate, and the two
    /// diverge by a whole frame within the first minute.
    @Test func aFractionalRateIndexesByTheRealRate() {
        let filter = FrameSeekFilter()
        let fps = 24000.0 / 1001

        // 60s * 23.976 = 1438.56 → frame 1438, where 24 fps would say 1440.
        #expect(filter.allows(60.0, fps: fps))
        #expect(!filter.allows(1438.5 / fps, fps: fps))
        #expect(filter.allows(1440 / fps, fps: fps))
    }
}
