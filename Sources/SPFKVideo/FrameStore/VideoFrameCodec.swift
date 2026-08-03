// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Minimal JPEG encode/decode used by ``VideoFrameDataStore``.
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

        // ImageIO's default JPEG quality is unstated/undocumented when omitted — set an
        // explicit value so cached frame quality is a known, deliberate choice rather than
        // whatever the platform happens to default to.
        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.8]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)

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
