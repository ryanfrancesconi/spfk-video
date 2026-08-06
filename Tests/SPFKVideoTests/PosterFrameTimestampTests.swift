// Copyright Ryan Francesconi. All Rights Reserved.

import Foundation
import Testing

@testable import SPFKVideo

/// Where the poster frame is sampled from.
///
/// Split out because the rule is the part that was wrong, and it is worth asserting without
/// decoding anything. The previous `min(duration * 0.5, 2.0)` posted every video longer than four
/// seconds at exactly 2.0s — measured on a real library, 348 of 400 clips. On feature-length video
/// that returned a distributor logo card.
struct PosterFrameTimestampTests {
    /// The headline regression. A long video must not be sampled near its opening.
    @Test func aFeatureLengthVideoIsSampledFromItsMiddleNotItsOpening() {
        let duration: TimeInterval = 7675.7 // a real 2h08m film
        let timestamp = VideoFrameExtractor.posterFrameTimestamp(duration: duration)

        #expect(timestamp > 60)
        let expected: TimeInterval = 7675.7 / 2
        #expect(timestamp == expected)
    }

    /// The band the old cap actually hurt most in practice — the bulk of a real library.
    @Test func typicalClipLengthsScaleWithDuration() {
        let shortTimestamp = VideoFrameExtractor.posterFrameTimestamp(duration: 15)
        let longTimestamp = VideoFrameExtractor.posterFrameTimestamp(duration: 60)

        #expect(shortTimestamp == 7.5)
        #expect(longTimestamp == 30)

        // The defect the cap produced: two clips of very different length sampled at the same
        // instant, so the rule stopped tracking the content at all.
        #expect(shortTimestamp != longTimestamp)
    }

    /// Must clear ``VideoFrameExtractor/defaultTolerance`` (0.3s, both directions) or the generator
    /// can legitimately return frame zero — the frame this exists to avoid.
    @Test func theOffsetClearsTheExtractorTolerance() {
        #expect(VideoFrameExtractor.posterFrameTimestamp(duration: 4) > VideoFrameExtractor.defaultTolerance)
    }

    /// A zero or unknown duration has no midpoint; sampling zero is the only option and must not
    /// produce a negative or NaN timestamp for the generator.
    @Test func zeroAndNegativeDurationsCollapseToZero() {
        #expect(VideoFrameExtractor.posterFrameTimestamp(duration: 0) == 0)
        #expect(VideoFrameExtractor.posterFrameTimestamp(duration: -5) == 0)
    }
}
