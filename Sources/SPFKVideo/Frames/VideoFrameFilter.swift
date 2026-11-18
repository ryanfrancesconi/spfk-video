// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import AVFoundation
import CoreImage
import Foundation

/// A Core Image transform run on every frame of a video, for playback and for export alike.
///
/// `frameIndex` counts frames from the start of the asset at its nominal frame rate. `sourceScale` is
/// the image's size relative to the full-resolution frame, so a filter sized in pixels looks the same
/// at the player's size as in the export.
public struct VideoFrameFilter: Sendable {
    public let apply: @Sendable (_ image: CIImage, _ frameIndex: Int64, _ sourceScale: Double) -> CIImage

    public init(_ apply: @escaping @Sendable (_ image: CIImage, _ frameIndex: Int64, _ sourceScale: Double) -> CIImage) {
        self.apply = apply
    }

    /// A composition running `filter` on each frame of `asset`, rendered at `renderScale` of the
    /// displayed size (capped at 1).
    ///
    /// A composition bakes each track's matrix into its pixels, so an orientation to keep must already
    /// be on `asset`'s tracks (an `AVMutableMovie`).
    public static func composition(
        for asset: AVAsset,
        filter: VideoFrameFilter,
        renderScale: Double = 1,
        isolation: isolated (any Actor)? = #isolation
    ) async throws -> AVMutableVideoComposition {
        let scale = min(1, max(renderScale, 0.01))
        let frameRate = try await asset.loadTracks(withMediaType: .video).first?.load(.nominalFrameRate) ?? 0

        let handler: @Sendable (AVAsynchronousCIImageFilteringRequest) -> Void = { request in
            var image = request.sourceImage

            if scale < 1 {
                image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            }

            let frameIndex = frameRate > 0 ? Int64((request.compositionTime.seconds * Double(frameRate)).rounded()) : 0
            request.finish(with: filter.apply(image, frameIndex, scale).cropped(to: image.extent), context: nil)
        }

        // The completion-handler form takes the asset synchronously, so it never leaves the caller's
        // isolation.
        let built = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UncheckedComposition, any Error>) in
            AVMutableVideoComposition.videoComposition(with: asset, applyingCIFiltersWithHandler: handler) { composition, error in
                if let composition {
                    continuation.resume(returning: UncheckedComposition(composition: composition))
                } else {
                    continuation.resume(throwing: error ?? CocoaError(.featureUnsupported))
                }
            }
        }
        let composition = built.composition

        if scale < 1 {
            composition.renderSize = CGSize(
                width: (composition.renderSize.width * scale).rounded(),
                height: (composition.renderSize.height * scale).rounded()
            )
        }

        return composition
    }
}

/// Carries a freshly built composition out of its completion handler; nothing else holds it.
private struct UncheckedComposition: @unchecked Sendable {
    let composition: AVMutableVideoComposition
}
