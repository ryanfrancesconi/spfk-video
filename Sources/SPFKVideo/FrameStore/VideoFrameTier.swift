// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

/// Identifies which variant of a cached video frame to read or write.
public enum VideoFrameTier: Sendable {
    /// Small frame sized for UI scrubber display.
    case thumbnail
    /// Larger frame sized for classification input. Not yet consumed by any caller —
    /// reserved for `spfk-image-analysis`'s deferred video classification phase, which
    /// shares this store rather than building its own frame cache.
    case fullQuality
}
