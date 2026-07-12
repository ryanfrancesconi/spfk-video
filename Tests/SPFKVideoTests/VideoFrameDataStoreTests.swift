// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import CoreGraphics
import Foundation
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKVideo

@MainActor
@Suite(.serialized, .tags(.file))
final class VideoFrameDataStoreTests: BinTestCase {
    // MARK: - Helpers

    private func syntheticImage(
        width: Int = 64,
        height: Int = 64,
        red: CGFloat = 1,
        green: CGFloat = 0,
        blue: CGFloat = 0
    ) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func fakeURL(index: Int) -> URL {
        URL(string: "file:///fake/video/clip_\(index).mp4")!
    }

    // MARK: - Round-trip

    @Test func insertAndFetchThumbnail() async throws {
        deleteBinOnExit = true
        let store = try VideoFrameDataStore(inDirectory: bin)
        let url = fakeURL(index: 0)

        try await store.insert(.thumbnail, cgImage: syntheticImage(), timestamp: 2.0, for: url)

        let fetched = await store.fetch(.thumbnail, timestamp: 2.0, for: url)
        #expect(fetched?.width == 64)
    }

    @Test func insertAndFetchFullQuality() async throws {
        deleteBinOnExit = true
        let store = try VideoFrameDataStore(inDirectory: bin)
        let url = fakeURL(index: 1)

        try await store.insert(.fullQuality, cgImage: syntheticImage(width: 600, height: 400), timestamp: 4.0, for: url)

        let fetched = await store.fetch(.fullQuality, timestamp: 4.0, for: url)
        #expect(fetched?.width == 600)
    }

    @Test func bothTiersRoundTripIndependentlyForSameTimestamp() async throws {
        deleteBinOnExit = true
        let store = try VideoFrameDataStore(inDirectory: bin)
        let url = fakeURL(index: 2)

        try await store.insert(.thumbnail, cgImage: syntheticImage(width: 64, height: 64), timestamp: 1.0, for: url)
        try await store.insert(.fullQuality, cgImage: syntheticImage(width: 640, height: 360), timestamp: 1.0, for: url)

        let thumb = await store.fetch(.thumbnail, timestamp: 1.0, for: url)
        let full = await store.fetch(.fullQuality, timestamp: 1.0, for: url)
        #expect(thumb?.width == 64)
        #expect(full?.width == 640)
    }

    @Test func fetchMissingTimestampReturnsNil() async throws {
        deleteBinOnExit = true
        let store = try VideoFrameDataStore(inDirectory: bin)
        let url = fakeURL(index: 3)

        let fetched = await store.fetch(.thumbnail, timestamp: 99.0, for: url)
        #expect(fetched == nil)
    }

    // MARK: - exists

    @Test func existsReflectsInsertedTierOnly() async throws {
        deleteBinOnExit = true
        let store = try VideoFrameDataStore(inDirectory: bin)
        let url = fakeURL(index: 4)

        try await store.insert(.thumbnail, cgImage: syntheticImage(), timestamp: 3.0, for: url)

        let thumbExists = await store.exists(.thumbnail, timestamp: 3.0, for: url)
        let fullExists = await store.exists(.fullQuality, timestamp: 3.0, for: url)
        #expect(thumbExists == true)
        #expect(fullExists == false)
    }

    // MARK: - delete

    @Test func deleteRemovesBothTiersAndAllTimestamps() async throws {
        deleteBinOnExit = true
        let store = try VideoFrameDataStore(inDirectory: bin)
        let url = fakeURL(index: 5)

        try await store.insert(.thumbnail, cgImage: syntheticImage(), timestamp: 1.0, for: url)
        try await store.insert(.thumbnail, cgImage: syntheticImage(), timestamp: 2.0, for: url)
        try await store.insert(.fullQuality, cgImage: syntheticImage(), timestamp: 1.0, for: url)

        await store.delete(url: url)

        let thumb1 = await store.fetch(.thumbnail, timestamp: 1.0, for: url)
        let thumb2 = await store.fetch(.thumbnail, timestamp: 2.0, for: url)
        let full1 = await store.fetch(.fullQuality, timestamp: 1.0, for: url)
        #expect(thumb1 == nil)
        #expect(thumb2 == nil)
        #expect(full1 == nil)
    }

    // MARK: - prune

    @Test func pruneRemovesWholeSubdirectoryForInactiveVideosOnly() async throws {
        deleteBinOnExit = true
        let store = try VideoFrameDataStore(inDirectory: bin)
        let activeURL = fakeURL(index: 6)
        let orphanedURL = fakeURL(index: 7)

        try await store.insert(.thumbnail, cgImage: syntheticImage(), timestamp: 1.0, for: activeURL)
        try await store.insert(.thumbnail, cgImage: syntheticImage(), timestamp: 2.0, for: activeURL)
        try await store.insert(.thumbnail, cgImage: syntheticImage(), timestamp: 1.0, for: orphanedURL)

        let removedCount = await store.prune(activeURLs: [activeURL])

        #expect(removedCount == 1)
        let activeStillThere = await store.fetch(.thumbnail, timestamp: 1.0, for: activeURL)
        let orphanedGone = await store.fetch(.thumbnail, timestamp: 1.0, for: orphanedURL)
        #expect(activeStillThere != nil)
        #expect(orphanedGone == nil)
    }

    // MARK: - count

    @Test func countReflectsTotalFramesAcrossVideosAndTiers() async throws {
        deleteBinOnExit = true
        let store = try VideoFrameDataStore(inDirectory: bin)
        let urlA = fakeURL(index: 8)
        let urlB = fakeURL(index: 9)

        try await store.insert(.thumbnail, cgImage: syntheticImage(), timestamp: 1.0, for: urlA)
        try await store.insert(.thumbnail, cgImage: syntheticImage(), timestamp: 2.0, for: urlA)
        try await store.insert(.fullQuality, cgImage: syntheticImage(), timestamp: 1.0, for: urlA)
        try await store.insert(.thumbnail, cgImage: syntheticImage(), timestamp: 1.0, for: urlB)

        let count = await store.count()
        #expect(count == 4)
    }
}
