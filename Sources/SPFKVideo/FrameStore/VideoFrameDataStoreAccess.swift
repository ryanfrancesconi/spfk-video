// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import CoreGraphics
import Foundation

public protocol VideoFrameDataStoreAccess: Sendable {
    func insertVideoFrame(_ tier: VideoFrameTier, cgImage: CGImage, timestamp: TimeInterval, for url: URL) async throws
    func fetchVideoFrame(_ tier: VideoFrameTier, timestamp: TimeInterval, for url: URL) async -> CGImage?

    /// Not currently called by any consumer — `fetchVideoFrame` returning `nil` already
    /// serves as the practical existence check callers use. Kept for API symmetry with
    /// `insertVideoFrame`/`fetchVideoFrame` and to mirror `ImageDataStoreAccess`'s shape.
    func videoFrameExists(_ tier: VideoFrameTier, timestamp: TimeInterval, for url: URL) async -> Bool

    /// Drops every cached frame for one file.
    ///
    /// Frames are keyed by URL and timestamp with no freshness check, so a file whose content
    /// changed at the same path — a trim rendered in place — would otherwise keep serving frames
    /// from the old timeline. Call this after rewriting a video, not on eviction; whole-cache
    /// housekeeping is ``pruneVideoFrames(activeURLs:)``.
    func deleteVideoFrames(for url: URL) async

    @discardableResult
    func pruneVideoFrames(activeURLs: Set<URL>) async -> Int
}
