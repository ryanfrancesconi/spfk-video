// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import AVFoundation
import CoreGraphics
import Foundation
import SPFKBase

/// Extracts still frames from a video asset at given timestamps.
///
/// Built on `AVAssetImageGenerator` and `images(for:)`, Apple's native async sequence API.
/// Wide-tolerance-by-default lets the generator pick the nearest already-decoded frame rather
/// than forcing exact decoding, which is significantly faster for thumbnail and classification
/// use cases that don't require frame-perfect accuracy.
///
/// The returned dictionary is keyed by the *requested* timestamp, not the actual extraction
/// time. This means thumbnail grids driven by an evenly-spaced request array stay visually
/// uniform regardless of how wide the tolerance window is.
public enum VideoFrameExtractor {
    /// Maximum deviation before and after each requested time allowed during frame extraction.
    ///
    /// 0.3 s matches the validated prior implementation and Apple's own guidance from
    /// WWDC22 "Create a more responsive media app". At a typical 2 s sampling interval
    /// this avoids forced I-frame decodes while keeping frames visually near their position.
    public static let defaultTolerance: TimeInterval = 0.3

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
