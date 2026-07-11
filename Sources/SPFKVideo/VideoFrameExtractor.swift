// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import Foundation

/// Extracts still frames from video at given timestamps.
///
/// Fills a real gap in Apple's own frameworks — Vision has no video-native classification or
/// sampling API, only single-image requests. Built on `AVAssetImageGenerator`, UI-agnostic,
/// with a wide-tolerance-by-default design for extraction speed (see the implementation plan
/// for the reasoning, validated against a prior working implementation).
///
/// Not yet implemented — this is a scaffold. See `spfk-video-plan.md` Phase 1.
public enum VideoFrameExtractor {}
