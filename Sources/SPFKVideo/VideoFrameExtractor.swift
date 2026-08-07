// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import AVFoundation
import CoreGraphics
import Foundation
import SPFKBase

/// Extracts still frames from a video asset at given timestamps.
///
/// Wide tolerance by default, so the generator takes the nearest decoded frame instead of forcing
/// an exact decode — much faster, and thumbnails do not need frame accuracy.
///
/// Keyed by the *requested* timestamp rather than the extracted one, so an evenly spaced request
/// comes back evenly spaced however wide the tolerance.
public enum VideoFrameExtractor {
    /// Maximum deviation before and after each requested time allowed during frame extraction.
    ///
    /// 0.3 s follows Apple's guidance (WWDC22, "Create a more responsive media app"). At a 2 s
    /// sampling interval it avoids forced I-frame decodes while staying visually near position.
    public static let defaultTolerance: TimeInterval = 0.3

    /// Where in a video the poster frame is taken from: **the midpoint, uncapped.**
    ///
    /// Uncapped because seeking deep costs nothing: at ``defaultTolerance``, 90% into a 211s H.264
    /// clip took 16 ms against 23 ms at 2%, and a 4K HEVC clip was 52–58 ms at every position.
    /// A cap costs correctness instead — of 400 clips measured, 348 ran 4 to 60 seconds and a 2.0s
    /// cap posted every one of them at 2.0s, while a feature returned its distributor's logo card.
    ///
    /// **Any poster-frame path must call this**, whatever extracts the picture, or thumbnails
    /// disagree between formats sitting next to each other in a list.
    public static func posterFrameTimestamp(duration: TimeInterval) -> TimeInterval {
        guard duration > 0 else { return 0 }
        return duration * 0.5
    }

    /// Loads the duration of a video asset's own video track, independent of any sibling
    /// audio track's duration in the same container.
    ///
    /// Container formats routinely have audio and video tracks of slightly different
    /// lengths (e.g. a DaVinci Resolve export where the audio track outlasts the video
    /// track by ~80ms) — `AVAsset.load(.duration)` reflects the container's overall
    /// duration, which is not guaranteed to match the video track specifically. Callers
    /// that sample timestamps for frame extraction should use this instead of a
    /// separately-sourced (e.g. audio-track) duration to avoid requesting frames past the
    /// video's actual last frame.
    ///
    /// - Throws: ``VideoFrameExtractionError/assetNotPlayable(_:)`` if the asset isn't
    ///   playable, has no video track, or its video track duration isn't a usable finite value.
    public static func duration(of url: URL) async throws -> TimeInterval {
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isPlayable) else {
            throw VideoFrameExtractionError.assetNotPlayable(url)
        }
        return try await videoTrackDuration(of: asset, url: url).seconds
    }

    /// Loads and validates the given asset's video track duration.
    ///
    /// - Throws: ``VideoFrameExtractionError/assetNotPlayable(_:)`` if there's no video
    ///   track, or its duration isn't valid and finite (`CMTimeCompare` orders invalid and
    ///   indefinite times as greater than every finite value, which would otherwise make a
    ///   downstream `< duration` filter silently accept every requested timestamp).
    private static func videoTrackDuration(of asset: AVURLAsset, url: URL) async throws -> CMTime {
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoFrameExtractionError.assetNotPlayable(url)
        }
        let duration = try await videoTrack.load(.timeRange).duration
        guard duration.isValid, !duration.isIndefinite else {
            throw VideoFrameExtractionError.assetNotPlayable(url)
        }
        return duration
    }

    /// Extracts frames from a video asset at each requested timestamp.
    ///
    /// - Parameters:
    ///   - url: File URL of the video asset.
    ///   - timestamps: Times in seconds at which to extract frames. Duplicates produce one
    ///     result per unique time; order within the returned dictionary is not guaranteed.
    ///   - maximumSize: Maximum output dimensions, preserving aspect ratio. Pass `nil` for
    ///     native resolution. Set one dimension to `0` to scale proportionally
    ///     (e.g. `CGSize(width: 300, height: 0)` constrains width and scales height).
    ///   - tolerance: Maximum deviation before and after each requested time, in seconds.
    ///     Zero forces frame-accurate extraction; larger values allow the generator to use
    ///     the nearest already-decoded frame for better throughput. Defaults to
    ///     ``defaultTolerance``.
    /// - Returns: Images keyed by the requested timestamp. A timestamp whose frame fails to
    ///   extract (logged, not thrown) is simply absent from the result — one bad frame doesn't
    ///   discard the rest of the batch.
    /// - Throws: ``VideoFrameExtractionError/assetNotPlayable(_:)`` if the asset itself is not
    ///   playable (missing, corrupt, or unsupported format), or has no usable video track.
    public static func frames(
        from url: URL,
        at timestamps: [TimeInterval],
        maximumSize: CGSize? = nil,
        tolerance: TimeInterval = defaultTolerance
    ) async throws -> [TimeInterval: CGImage] {
        guard !timestamps.isEmpty else { return [:] }

        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isPlayable) else {
            throw VideoFrameExtractionError.assetNotPlayable(url)
        }

        let duration = try await videoTrackDuration(of: asset, url: url)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        if let maximumSize {
            generator.maximumSize = maximumSize
        }

        let toleranceCMTime = CMTime(seconds: tolerance, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = toleranceCMTime
        generator.requestedTimeToleranceAfter = toleranceCMTime

        // A timestamp at or beyond the video track's own duration (e.g. sampled against a
        // sibling audio track whose duration doesn't exactly match) fails extraction outright
        // ("Cannot Open") rather than clamping to the nearest valid frame — drop it before ever
        // making the request instead of relying on the per-frame failure handling below.
        let validTimestamps = timestamps.filter {
            CMTimeCompare(CMTime(seconds: $0, preferredTimescale: 600), duration) < 0
        }
        guard !validTimestamps.isEmpty else {
            Log.error(
                "All \(timestamps.count) requested timestamp(s) for \(url.lastPathComponent) are at or beyond the video track duration (\(duration.seconds)s); returning no frames"
            )
            return [:]
        }

        let cmTimes = validTimestamps.map { CMTime(seconds: $0, preferredTimescale: 600) }

        // Reverse lookup by CMTime so the returned dictionary keys are the original
        // TimeInterval values without floating-point conversion loss through CMTime.seconds.
        let cmTimeToTimestamp = Dictionary(
            zip(cmTimes, validTimestamps),
            uniquingKeysWith: { first, _ in first }
        )

        var results = [TimeInterval: CGImage](minimumCapacity: validTimestamps.count)

        defer { generator.cancelAllCGImageGeneration() }

        for await result in generator.images(for: cmTimes) {
            switch result {
            case let .success(requestedTime, image, _):
                results[cmTimeToTimestamp[requestedTime] ?? requestedTime.seconds] = image

            case let .failure(requestedTime, error):
                // One unreadable frame (e.g. a corrupt GOP, a decoder resource conflict) shouldn't
                // discard every other frame in the batch — skip it and keep collecting the rest.
                let timestamp = cmTimeToTimestamp[requestedTime] ?? requestedTime.seconds
                Log.error("Failed to extract video frame at \(timestamp)s from \(url.lastPathComponent)", error)
            }
        }

        return results
    }
}
