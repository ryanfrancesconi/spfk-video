// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

/// Identifies which variant of a cached video frame to read or write.
public enum VideoFrameTier: Sendable {
    /// Small frame sized for UI scrubber display.
    case thumbnail
    /// Larger frame sized for classification input.
    case fullQuality
}
