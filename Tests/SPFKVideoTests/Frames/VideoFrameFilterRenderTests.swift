// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import AVFoundation
import CoreImage
import CoreMedia
import Foundation
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKVideo

@Suite(.tags(.file))
final class VideoFrameFilterRenderTests {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(component: "VideoFrameFilterRenderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    static let invert = VideoFrameFilter { image, _, _ in image.applyingFilter("CIColorInvert") }

    private func output(_ name: String = "out.mov") -> URL {
        directory.appending(component: name)
    }

    /// The displayed frame at `seconds`, drawn into a 64 × 64 RGBA bitmap.
    static func frame(of url: URL, at seconds: Double) async throws -> [UInt8] {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let image = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
        var pixels = [UInt8](repeating: 0, count: 64 * 64 * 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))

        try pixels.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(
                data: buffer.baseAddress, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 64 * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 64))
        }

        return pixels
    }

    static func meanDifference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        Double(zip(a, b).map { abs(Int($0) - Int($1)) }.reduce(0, +)) / Double(a.count)
    }

    static func displayedSize(of url: URL) async throws -> (size: CGSize, transform: CGAffineTransform) {
        let track = try #require(try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first)
        return try await (track.load(.naturalSize), track.load(.preferredTransform))
    }

    // MARK: - Rendering

    @Test func aFilterChangesThePixels() async throws {
        let source = TestBundleResources.shared.orientation_pattern_mov
        let renderer = VideoEditRenderer(sourceURL: source, trim: TrimDescription(), filter: Self.invert, outputURL: output())
        let rendered = try await renderer.render()

        let difference = try await Self.meanDifference(Self.frame(of: source, at: 0.5), Self.frame(of: rendered, at: 0.5))
        #expect(difference > 50)
    }

    @Test func trimOrientationAndFilterAreOneRender() async throws {
        let source = TestBundleResources.shared.orientation_pattern_mov
        let sourceSize = try await Self.displayedSize(of: source).size

        let renderer = VideoEditRenderer(
            sourceURL: source,
            trim: TrimDescription(inPoint: 0.5, outPoint: 1.5),
            orientation: .right,
            filter: Self.invert,
            outputURL: output()
        )
        let rendered = try await renderer.render()

        let duration = try await AVURLAsset(url: rendered).load(.duration).seconds
        #expect(abs(duration - 1) < 0.1)

        let (size, transform) = try await Self.displayedSize(of: rendered)
        #expect(transform.isIdentity)
        #expect(size.width == sourceSize.height)
        #expect(size.height == sourceSize.width)

        let unfiltered = try await VideoEditRenderer(
            sourceURL: source, trim: TrimDescription(inPoint: 0.5, outPoint: 1.5), orientation: .right, outputURL: output("plain.mov")
        ).render()
        let difference = try await Self.meanDifference(Self.frame(of: unfiltered, at: 0.5), Self.frame(of: rendered, at: 0.5))
        #expect(difference > 50)
    }

    @Test func aFileWithTwoAudioTracksIsRefused() async throws {
        let renderer = VideoEditRenderer(
            sourceURL: TestBundleResources.shared.sample_dualaudio_mov, trim: TrimDescription(), filter: Self.invert, outputURL: output()
        )

        await #expect(throws: VideoEditError.self) { try await renderer.render() }
        #expect(!output().exists)
    }

    /// The cancel comes from outside the frame handler: cancelling the export waits for the handler.
    @Test func cancellingMidRenderLeavesNoOutput() async throws {
        let (frames, continuation) = AsyncStream<Int64>.makeStream()
        let slow = VideoFrameFilter { image, frameIndex, _ in
            continuation.yield(frameIndex)
            Thread.sleep(forTimeInterval: 0.02)
            return image
        }

        let renderer = VideoEditRenderer(
            sourceURL: TestBundleResources.shared.orientation_pattern_mov, trim: TrimDescription(), filter: slow, outputURL: output()
        )
        let render = Task { try await renderer.render() }

        for await _ in frames.prefix(4) {}
        render.cancel()

        await #expect(throws: (any Error).self) { try await render.value }
        #expect(!output().exists)
    }

    // MARK: - Preset

    @Test func theReencodePresetFollowsTheSourceCodec() async throws {
        let resources = TestBundleResources.shared
        #expect(try await VideoEditRenderer.reencodePreset(for: resources.hlg_pattern_mov) == .hevcHighestQuality)
        #expect(try await VideoEditRenderer.reencodePreset(for: resources.orientation_pattern_mov) == .hevcHighestQuality)
        #expect(try await VideoEditRenderer.reencodePreset(for: resources.prores_pattern_mov) == .proRes422)
    }

    @Test func proResOutsideAMovieBecomesHEVC() throws {
        let url = URL(fileURLWithPath: "/clip.mp4")
        #expect(try VideoEditRenderer.reencodePreset(codec: kCMVideoCodecType_AppleProRes4444, pathExtension: "mov", url: url) == .proRes4444)
        #expect(try VideoEditRenderer.reencodePreset(codec: kCMVideoCodecType_AppleProRes422HQ, pathExtension: "mp4", url: url) == .hevcHighestQuality)
        #expect(throws: VideoEditError.self) {
            try VideoEditRenderer.reencodePreset(codec: kCMVideoCodecType_AppleProResRAW, pathExtension: "mov", url: url)
        }
    }

    // MARK: - Conversion

    @Test func passthroughWithAFilterIsRefused() async throws {
        let source = VideoConversionSource(
            input: TestBundleResources.shared.orientation_pattern_mov,
            output: output(),
            options: VideoConversionOptions(preset: .passthrough, container: .mov),
            filter: Self.invert
        )

        await #expect(throws: VideoConversionError.self) { try await VideoFormatConverter(source: source).convert() }
        #expect(!output().exists)
    }

    @Test func aConversionCarriesTheFilter() async throws {
        let input = TestBundleResources.shared.orientation_pattern_mov
        let source = VideoConversionSource(
            input: input, output: output(), options: VideoConversionOptions(preset: .hevcHighestQuality, container: .mov), filter: Self.invert
        )

        let converted = try await VideoFormatConverter(source: source).convert()
        let difference = try await Self.meanDifference(Self.frame(of: input, at: 0.5), Self.frame(of: converted.output, at: 0.5))
        #expect(difference > 50)
    }
}
