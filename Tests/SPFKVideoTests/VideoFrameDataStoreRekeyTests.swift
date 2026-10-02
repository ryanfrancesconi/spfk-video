// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import CoreGraphics
import Foundation
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKVideo

/// A relinked video keeps its extracted frames under the new path's key.
@MainActor
@Suite(.tags(.file))
final class VideoFrameDataStoreRekeyTests: BinTestCase {
    private func image(red: CGFloat) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: red, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        return try #require(context.makeImage())
    }

    private let old = URL(fileURLWithPath: "/Old Drive/Movies/clip.mov")
    private let new = URL(fileURLWithPath: "/New Drive/Movies/clip.mov")

    @Test func everyFrameMovesToTheNewKey() async throws {
        deleteBinOnExit = true
        let store = try VideoFrameDataStore(inDirectory: bin)

        try await store.insert(.thumbnail, cgImage: image(red: 1), timestamp: 0.5, for: old)
        try await store.insert(.fullQuality, cgImage: image(red: 1), timestamp: 2, for: old)

        try await store.rekey(from: old, to: new)

        #expect(await store.exists(.thumbnail, timestamp: 0.5, for: new))
        #expect(await store.exists(.fullQuality, timestamp: 2, for: new))
        #expect(await !store.exists(.thumbnail, timestamp: 0.5, for: old))
    }

    /// On a merge the file already in the library keeps its own frames, and the old ones go.
    @Test func existingFramesAtTheNewKeyWin() async throws {
        deleteBinOnExit = true
        let store = try VideoFrameDataStore(inDirectory: bin)

        try await store.insert(.thumbnail, cgImage: image(red: 1), timestamp: 0.5, for: old)
        try await store.insert(.thumbnail, cgImage: image(red: 0.5), timestamp: 1, for: new)

        try await store.rekey(from: old, to: new)

        #expect(await store.exists(.thumbnail, timestamp: 1, for: new))
        #expect(await !store.exists(.thumbnail, timestamp: 0.5, for: new))
        #expect(await store.count() == 1)
    }
}
