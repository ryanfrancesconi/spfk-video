// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import CoreImage
import Foundation
import ImageIO
import SPFKBase
import Testing

@testable import SPFKVideo

/// ``OrientationEdit/apply(to:)-(CGImage)`` against CoreImage's EXIF orientation of the same raw value.
struct OrientationEditCGImageTests {
    /// Six wide, four tall, every pixel a different value.
    private static func source() throws -> CGImage {
        let width = 6, height = 4
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        let pixels = try #require(context.data?.bindMemory(to: UInt8.self, capacity: width * height * 4))

        for index in 0 ..< width * height {
            pixels[index * 4] = UInt8(index * 10)
            pixels[index * 4 + 1] = UInt8(255 - index * 10)
            pixels[index * 4 + 2] = UInt8(index % 2 * 200)
        }

        return try #require(context.makeImage())
    }

    static func pixels(_ image: CGImage) throws -> [UInt8] {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))

        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        return bytes
    }

    static func reference(_ image: CGImage, _ edit: OrientationEdit) throws -> CGImage {
        let orientation = try #require(CGImagePropertyOrientation(rawValue: UInt32(edit.rawValue)))
        let oriented = CIImage(cgImage: image).oriented(orientation)
        let atOrigin = oriented.transformed(by: CGAffineTransform(translationX: -oriented.extent.minX, y: -oriented.extent.minY))
        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        let space = try #require(image.colorSpace)

        return try #require(context.createCGImage(atOrigin, from: atOrigin.extent, format: .RGBA8, colorSpace: space))
    }

    /// Not `.up`, which returns its input: CoreImage's own round trip of an untouched image is not
    /// byte-identical to it.
    @Test(arguments: OrientationEdit.allCases.filter { !$0.isIdentity })
    func matchesCoreImage(edit: OrientationEdit) throws {
        let source = try Self.source()
        let oriented = try #require(edit.apply(to: source))
        let expected = try Self.reference(source, edit)

        #expect(oriented.width == expected.width && oriented.height == expected.height)
        #expect(try Self.pixels(oriented) == Self.pixels(expected))
    }

    @Test func noEditReturnsTheSameImage() throws {
        let source = try Self.source()
        #expect(OrientationEdit.up.apply(to: source) === source)
    }
}
