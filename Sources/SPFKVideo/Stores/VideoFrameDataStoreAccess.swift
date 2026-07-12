// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import CoreGraphics
import Foundation

public protocol VideoFrameDataStoreAccess: Sendable {
    func insertVideoFrame(_ tier: VideoFrameTier, cgImage: CGImage, timestamp: TimeInterval, for url: URL) async throws
    func fetchVideoFrame(_ tier: VideoFrameTier, timestamp: TimeInterval, for url: URL) async -> CGImage?
    func videoFrameExists(_ tier: VideoFrameTier, timestamp: TimeInterval, for url: URL) async -> Bool

    @discardableResult
    func pruneVideoFrames(activeURLs: Set<URL>) async -> Int
}
