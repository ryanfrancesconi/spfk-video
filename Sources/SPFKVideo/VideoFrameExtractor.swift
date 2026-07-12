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
    /// - Returns: Images keyed by the requested timestamp. Every timestamp in the input
    ///   array appears as a key if extraction succeeds.
    /// - Throws: ``VideoFrameExtractionError`` if the asset is not playable, or if any
    ///   individual frame extraction fails.
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

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        if let maximumSize {
            generator.maximumSize = maximumSize
        }

        let toleranceCMTime = CMTime(seconds: tolerance, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = toleranceCMTime
        generator.requestedTimeToleranceAfter = toleranceCMTime

        let cmTimes = timestamps.map { CMTime(seconds: $0, preferredTimescale: 600) }

        // Reverse lookup by CMTime so the returned dictionary keys are the original
        // TimeInterval values without floating-point conversion loss through CMTime.seconds.
        let cmTimeToTimestamp = Dictionary(
            zip(cmTimes, timestamps),
            uniquingKeysWith: { first, _ in first }
        )

        var results = [TimeInterval: CGImage](minimumCapacity: timestamps.count)

        defer { generator.cancelAllCGImageGeneration() }

        for await result in generator.images(for: cmTimes) {
            switch result {
            case .success(let requestedTime, let image, _):
                results[cmTimeToTimestamp[requestedTime] ?? requestedTime.seconds] = image

            case .failure(let requestedTime, let error):
                throw VideoFrameExtractionError.frameFailed(
                    timestamp: cmTimeToTimestamp[requestedTime] ?? requestedTime.seconds,
                    underlyingError: error
                )
            }
        }

        return results
    }
}
