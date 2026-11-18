// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import CoreGraphics
import Foundation
import SPFKBase

extension OrientationEdit {
    /// A copy of `image` with this edit performed, or `image` itself for no edit. `nil` when no
    /// bitmap context can be made for it.
    public func apply(to image: CGImage) -> CGImage? {
        guard !isIdentity else { return image }

        let size = CGSize(width: image.width, height: image.height)
        let outputSize = swapsDimensions ? CGSize(width: size.height, height: size.width) : size
        let space = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil, width: Int(outputSize.width), height: Int(outputSize.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) ?? CGContext(
            data: nil, width: Int(outputSize.width), height: Int(outputSize.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // The edit is defined with y down; a bitmap context and an image's own coordinates are y up.
        let imageToDisplay = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: size.height)
        let displayToContext = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: outputSize.height)

        context.interpolationQuality = .none
        context.concatenate(imageToDisplay.concatenating(transform(displaying: size)).concatenating(displayToContext))
        context.draw(image, in: CGRect(origin: .zero, size: size))

        return context.makeImage()
    }
}
