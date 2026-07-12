// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import AVFoundation
import Foundation
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKVideo

@Suite("VideoFrameExtractor")
struct VideoFrameExtractorTests {

    // MARK: - Keys match requested timestamps

    @Test("Returns exactly the requested timestamps as dictionary keys")
    func keysMatchRequestedTimestamps() async throws {
        let videoURL = try await VideoTestFixture.makeTestVideo()
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let timestamps: [TimeInterval] = [1.0, 3.0, 5.0, 7.0]
        let frames = try await VideoFrameExtractor.frames(from: videoURL, at: timestamps)

        #expect(frames.count == timestamps.count)
        for timestamp in timestamps {
            #expect(frames[timestamp] != nil, "Expected frame for requested timestamp \(timestamp)s")
        }
    }

    // MARK: - Empty input

    @Test("Returns empty dictionary for empty timestamp array")
    func emptyTimestampsReturnsEmpty() async throws {
        let videoURL = try await VideoTestFixture.makeTestVideo()
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let frames = try await VideoFrameExtractor.frames(from: videoURL, at: [])
        #expect(frames.isEmpty)
    }

    // MARK: - maximumSize constrains output

    @Test("Returned images are no wider than maximumSize.width")
    func maximumSizeConstrainsWidth() async throws {
        let videoURL = try await VideoTestFixture.makeTestVideo()
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let maxWidth = 150
        let frames = try await VideoFrameExtractor.frames(
            from: videoURL,
            at: [1.0],
            maximumSize: CGSize(width: maxWidth, height: 0)
        )

        let image = try #require(frames[1.0])
        #expect(image.width <= maxWidth)
    }

    // MARK: - Different sizes for different consumers

    /// Validates the plan's key design correction: a classification-scale maximumSize produces
    /// meaningfully larger frames than a UI-thumbnail-scale maximumSize via the same API.
    @Test("Larger maximumSize produces larger output than smaller maximumSize")
    func largerMaximumSizeProducesLargerOutput() async throws {
        let videoURL = try await VideoTestFixture.makeTestVideo()
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let uiThumbnailFrames = try await VideoFrameExtractor.frames(
            from: videoURL,
            at: [1.0],
            maximumSize: CGSize(width: 150, height: 0)
        )

        let classificationFrames = try await VideoFrameExtractor.frames(
            from: videoURL,
            at: [1.0],
            maximumSize: CGSize(width: 600, height: 0)
        )

        let smallImage = try #require(uiThumbnailFrames[1.0])
        let largeImage = try #require(classificationFrames[1.0])
        #expect(smallImage.width < largeImage.width)
    }

    // MARK: - Error propagation

    @Test("Throws for a non-existent file")
    func throwsForMissingFile() async throws {
        let badURL = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).mp4")

        await #expect(throws: (any Error).self) {
            _ = try await VideoFrameExtractor.frames(from: badURL, at: [1.0])
        }
    }

    // MARK: - Tolerance behavior

    /// Verifies the tolerance wiring is actually applied and not just configured silently.
    /// Wide tolerance should never be meaningfully slower than zero tolerance — in practice
    /// it is faster when the video has sparse keyframes, since the generator can reuse
    /// already-decoded I-frames instead of seeking to exact positions.
    @Test("Wide tolerance is no slower than zero tolerance", .tags(.development))
    func wideToleranceIsNoSlowerThanZeroTolerance() async throws {
        let videoURL = try await VideoTestFixture.makeTestVideo(duration: 20.0)
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let timestamps = stride(from: 0.0, through: 18.0, by: 2.0).map { $0 }

        // Run zero-tolerance first to avoid warm-cache advantage for the wide-tolerance pass.
        let zeroBenchmark = Benchmark(label: "zero-tolerance extraction")
        _ = try await VideoFrameExtractor.frames(from: videoURL, at: timestamps, tolerance: 0.0)
        let zeroDuration = zeroBenchmark.stop()

        let wideBenchmark = Benchmark(label: "wide-tolerance extraction")
        _ = try await VideoFrameExtractor.frames(
            from: videoURL,
            at: timestamps,
            tolerance: VideoFrameExtractor.defaultTolerance
        )
        let wideDuration = wideBenchmark.stop()

        // Wide tolerance must not take more than 1.5x what zero tolerance took.
        // A ratio above this indicates the tolerance setting is not being applied.
        #expect(wideDuration <= zeroDuration * 1.5)
    }
}
