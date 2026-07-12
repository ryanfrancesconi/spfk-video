// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Minimal JPEG encode/decode used by ``VideoFrameDataStore``.
///
/// Written directly against ImageIO rather than depending on `spfk-utils`'s `CGImage`
/// extensions, which would transitively pull in `spfk-audio-base` — a dependency this
/// package deliberately avoids to stay usable by non-audio consumers (see
/// `spfk-video-plan.md`'s Phase 5 dependency check).
enum VideoFrameCodec {
    static func jpegData(from cgImage: CGImage) throws -> Data {
        guard
            let mutableData = CFDataCreateMutable(nil, 0),
            let destination = CGImageDestinationCreateWithData(
                mutableData,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            )
        else {
            throw VideoFrameDataStoreError.encodingFailed
        }

        CGImageDestinationAddImage(destination, cgImage, nil)

        guard CGImageDestinationFinalize(destination) else {
            throw VideoFrameDataStoreError.encodingFailed
        }

        return mutableData as Data
    }

    static func cgImage(from data: Data) throws -> CGImage {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw VideoFrameDataStoreError.decodingFailed
        }

        return image
    }
}
