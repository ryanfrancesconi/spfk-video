// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

/// Errors thrown by ``VideoFrameDataStore``.
public enum VideoFrameDataStoreError: Error {
    /// JPEG encoding of a frame failed.
    case encodingFailed
    /// JPEG decoding of cached frame data failed.
    case decodingFailed
}
