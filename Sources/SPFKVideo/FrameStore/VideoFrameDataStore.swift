// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import CoreGraphics
import Foundation
import SPFKBase

/// Disk cache for extracted video frames, keyed by source video and requested timestamp.
///
/// Layout: `<inDirectory>/Data/Video/<fileKey>/<timestampMs>_thumb.jpg` and
/// `.../<timestampMs>_full.jpg` — one subdirectory per video (keyed by `url.sha256`), tier
/// distinguished by filename suffix. This mirrors `ImageDataStore`'s `_thumb`/`_full`
/// convention combined with a per-source-file subdirectory, the right shape for
/// many-frames-per-file data (as opposed to `BookmarkDataStore`'s 256-shard hash-prefix
/// scheme, built for one-entry-per-file data).
///
/// Frames are stored as JPEG — many frames per file makes format choice matter more here
/// than for a one-entry-per-file cache.
public actor VideoFrameDataStore {
    public nonisolated let directoryURL: URL

    static let thumbSuffix = "_thumb.jpg"
    static let fullSuffix = "_full.jpg"

    public init(inDirectory: URL) throws {
        directoryURL = inDirectory.appendingPathComponent("Data/Video")
        try Self.ensureDirectory(at: directoryURL)
    }

    private static func ensureDirectory(at url: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    // MARK: - Private Filename Helpers

    private func fileDirectory(for fileKey: String) -> URL {
        directoryURL.appendingPathComponent(fileKey)
    }

    private func suffix(for tier: VideoFrameTier) -> String {
        switch tier {
        case .thumbnail: Self.thumbSuffix
        case .fullQuality: Self.fullSuffix
        }
    }

    /// Millisecond-precision integer key, avoiding floating-point string inconsistency
    /// (e.g. `0.3` vs `0.30000000000000004`) across insert/fetch round-trips.
    private func timestampKey(_ timestamp: TimeInterval) -> String {
        String(Int((timestamp * 1000).rounded()))
    }

    private func frameURL(_ tier: VideoFrameTier, timestamp: TimeInterval, fileKey: String) -> URL {
        fileDirectory(for: fileKey).appendingPathComponent("\(timestampKey(timestamp))\(suffix(for: tier))")
    }

    private func ensureFileDirectory(for fileKey: String) throws {
        let dir = fileDirectory(for: fileKey)
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}

// MARK: - Public

extension VideoFrameDataStore {
    public func insert(_ tier: VideoFrameTier, cgImage: CGImage, timestamp: TimeInterval, for url: URL) throws {
        let fileKey = url.sha256
        try ensureFileDirectory(for: fileKey)

        let data = try VideoFrameCodec.jpegData(from: cgImage)
        let destURL = frameURL(tier, timestamp: timestamp, fileKey: fileKey)
        try data.write(to: destURL, options: .atomic)
    }

    /// Returns the cached frame for the given video, tier, and timestamp, or nil if not cached.
    public func fetch(_ tier: VideoFrameTier, timestamp: TimeInterval, for url: URL) -> CGImage? {
        let destURL = frameURL(tier, timestamp: timestamp, fileKey: url.sha256)
        guard let data = try? Data(contentsOf: destURL) else { return nil }
        return try? VideoFrameCodec.cgImage(from: data)
    }

    /// Returns true if a frame exists for the given video, tier, and timestamp (does not load it).
    public func exists(_ tier: VideoFrameTier, timestamp: TimeInterval, for url: URL) -> Bool {
        FileManager.default.fileExists(atPath: frameURL(tier, timestamp: timestamp, fileKey: url.sha256).path)
    }

    /// Removes every cached frame (both tiers, all timestamps) for the given video.
    ///
    /// Not currently called in production — `prune(activeURLs:)`/`prune(activeKeys:)` handle
    /// the app's actual cache-eviction path. Kept as public API for explicit single-video
    /// invalidation (e.g. "re-extract this video's thumbnails"), mirroring the equivalent
    /// method on sibling stores (`ImageDataStore`, `WaveformDataStore`).
    public func delete(url: URL) {
        try? FileManager.default.removeItem(at: fileDirectory(for: url.sha256))
    }

    /// Removes every cached video whose fileKey is not present in `activeURLs`.
    /// Each removal deletes the video's whole subdirectory in one operation, not a per-frame scan.
    @discardableResult
    public func prune(activeURLs: Set<URL>) -> Int {
        prune(activeKeys: Set(activeURLs.map(\.sha256)))
    }

    @discardableResult
    public func prune(activeKeys: Set<String>) -> Int {
        let fm = FileManager.default
        guard let fileDirs = try? fm.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            return 0
        }

        var removedCount = 0
        for dir in fileDirs {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            let key = dir.lastPathComponent
            guard !activeKeys.contains(key) else { continue }
            Log.debug("pruning orphaned video frame cache: \(key)")
            do {
                try fm.removeItem(at: dir)
                removedCount += 1
            } catch {
                Log.error("Failed to prune orphaned video frame cache: \(key)", error)
            }
        }
        return removedCount
    }

    /// Total number of cached frames (both tiers, across every video).
    ///
    /// Not currently called in production — kept for diagnostics/debugging and to mirror
    /// `count()` on sibling stores.
    public func count() -> Int {
        let fm = FileManager.default
        guard let fileDirs = try? fm.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            return 0
        }

        var total = 0
        for dir in fileDirs {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            total += files.count
        }
        return total
    }
}
