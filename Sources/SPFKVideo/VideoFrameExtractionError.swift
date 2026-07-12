// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import Foundation

/// Errors thrown by ``VideoFrameExtractor``.
public enum VideoFrameExtractionError: Error {
    /// The asset at the given URL cannot be played (missing, corrupt, or unsupported format).
    case assetNotPlayable(URL)
    /// Extraction of the frame at the given timestamp failed.
    case frameFailed(timestamp: TimeInterval, underlyingError: any Error)
}
