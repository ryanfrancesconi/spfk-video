// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import AVFoundation
import CoreImage
import Foundation
import ImageIO
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKVideo

/// A rendered orientation checked against how AVFoundation displays the output, with CoreImage's
/// EXIF orientation of the source frame as the reference. Decodes frames, so it needs VideoToolbox:
/// run unsandboxed.
@Suite(.tags(.conversion))
final class VideoOrientationTests {
    private let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(component: "VideoOrientationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    static let patterns: [URL] = [TestBundleResources.shared.orientation_pattern_mov, TestBundleResources.shared.orientation_pattern_mp4]

    // MARK: - Display

    @Test(arguments: OrientationEdit.allCases, patterns)
    func theOutputDisplaysTheSourceOriented(edit: OrientationEdit, source: URL) async throws {
        let output = try await render(source, edit)

        let expected = try Self.oriented(try await Self.frame(of: source), edit)
        let actual = try await Self.frame(of: output)

        #expect(try Self.maxChannelDifference(actual, expected) == 0)
    }

    /// The source's own matrix is composed with, not replaced.
    @Test func aQuarterTurnOnARotatedSourceLandsAtAHalfTurn() async throws {
        let source = TestBundleResources.shared.orientation_pattern_mov
        let once = try await render(source, .right)
        let twice = try await render(once, .right)

        #expect(OrientationEdit(trackTransform: try await Self.videoTransform(of: twice)) == .down)

        let expected = try Self.oriented(try await Self.frame(of: source), .down)
        #expect(try Self.maxChannelDifference(try await Self.frame(of: twice), expected) == 0)
    }

    @Test func anM4VReadsAndWritesLikeAnMP4() async throws {
        let once = try await render(TestBundleResources.shared.orientation_pattern_mp4, .right, pathExtension: "m4v")
        let twice = try await render(once, .upMirrored, pathExtension: "m4v")

        let transform = try await Self.videoTransform(of: twice)
        #expect(OrientationEdit(trackTransform: transform) == OrientationEdit.right.flippedHorizontally)
    }

    // MARK: - Matrix

    @Test(arguments: OrientationEdit.allCases)
    func aTrackMatrixReadsBackAsItsOrientation(edit: OrientationEdit) {
        let transform = edit.transform(displaying: CGSize(width: 160, height: 120))
        #expect(OrientationEdit(trackTransform: transform) == edit)
    }

    @Test(arguments: OrientationEdit.allCases)
    func theTransformMapsThePictureOntoTheOrigin(edit: OrientationEdit) {
        let size = CGSize(width: 160, height: 120)
        let displayed = CGRect(origin: .zero, size: size).applying(edit.transform(displaying: size))
        let expectedSize = edit.swapsDimensions ? CGSize(width: 120, height: 160) : size

        #expect(displayed == CGRect(origin: .zero, size: expectedSize))
    }

    @Test func aMatrixThatScalesOrSkewsHasNoOrientation() {
        #expect(OrientationEdit(trackTransform: CGAffineTransform(scaleX: 2, y: 2)) == nil)
        #expect(OrientationEdit(trackTransform: CGAffineTransform(a: 1, b: 0, c: 0.5, d: 1, tx: 0, ty: 0)) == nil)
    }

    @Test func translationIsIgnored() {
        let transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0)
        #expect(OrientationEdit(trackTransform: transform) == .right)
    }

    // MARK: - Render

    @Test(arguments: [false, true])
    func aTrimAndAnOrientationRenderTogether(usesLegacyExportPath: Bool) async throws {
        let source = TestBundleResources.shared.orientation_pattern_mov
        let output = folder.appending(component: "\(UUID().uuidString).mov", directoryHint: .notDirectory)

        let renderer = VideoEditRenderer(sourceURL: source, trim: TrimDescription(inPoint: 0.5, outPoint: 1.5), orientation: .left, outputURL: output)
        await renderer.setUsesLegacyExportPath(usesLegacyExportPath)
        try await renderer.render()

        let duration = try await AVURLAsset(url: output).load(.duration).seconds
        #expect(abs(duration - 1.0) < 0.05, "expected ~1s, got \(duration)s")
        #expect(OrientationEdit(trackTransform: try await Self.videoTransform(of: output)) == .left)
        #expect(try await AVURLAsset(url: output).loadTracks(withMediaType: .audio).count == 1)
    }

    @Test func theWrittenMatrixIsCheckedAgainstTheOneAskedFor() async throws {
        let output = try await render(TestBundleResources.shared.orientation_pattern_mov, .right)
        let written = try await Self.videoTransform(of: output)

        #expect(try await VideoExport.videoTransforms(at: output, match: [written]))
        #expect(try await VideoExport.videoTransforms(at: output, match: [.identity]) == false)
        #expect(try await VideoExport.videoTransforms(at: output, match: [written, written]) == false)
    }

    @Test func noOrientationReadsTheSourceAsAURLAsset() async throws {
        #expect(try await VideoExport.orientedMovie(of: TestBundleResources.shared.orientation_pattern_mov, orientation: .up) == nil)
    }

    @Test func orientationIsOfferedForMOVMP4AndM4VOnly() {
        for name in ["a.mov", "a.MP4", "a.m4v"] {
            #expect(VideoEditRenderer.canWriteOrientation(of: URL(fileURLWithPath: "/tmp/\(name)")), "\(name)")
        }
        for name in ["a.mkv", "a.webm", "a.mxf", "a.ts", "a.avi"] {
            #expect(VideoEditRenderer.canWriteOrientation(of: URL(fileURLWithPath: "/tmp/\(name)")) == false, "\(name)")
        }
    }

    // MARK: - Export

    @Test func aPassthroughConversionWritesTheMatrix() async throws {
        let converted = try await convert(.passthrough, .right)

        #expect(OrientationEdit(trackTransform: try await Self.videoTransform(of: converted)) == .right)

        let expected = try Self.oriented(try await Self.frame(of: TestBundleResources.shared.orientation_pattern_mov), .right)
        #expect(try Self.maxChannelDifference(try await Self.frame(of: converted), expected) == 0)
    }

    /// A re-encoding preset renders the pixels through the matrix and writes an identity one. The
    /// output is color-managed differently from the untagged source, so the check is which of the 8
    /// orientations of the source it is closest to rather than an exact match.
    @Test func aReencodingConversionTurnsThePixels() async throws {
        let converted = try await convert(.hevcHighestQuality, .right)

        let track = try #require(try await AVURLAsset(url: converted).loadTracks(withMediaType: .video).first)
        #expect(try await track.load(.naturalSize) == CGSize(width: 120, height: 160))
        #expect(OrientationEdit(trackTransform: try await track.load(.preferredTransform)) == .up)

        let source = try await Self.frame(of: TestBundleResources.shared.orientation_pattern_mov)
        let actual = try await Self.frame(of: converted)
        var distances: [OrientationEdit: Double] = [:]

        for candidate in OrientationEdit.allCases where candidate.swapsDimensions {
            distances[candidate] = try Self.meanChannelDifference(actual, try Self.oriented(source, candidate))
        }

        #expect(distances.min { $0.value < $1.value }?.key == .right, "\(distances)")
    }

    // MARK: - Helpers

    private func render(_ source: URL, _ edit: OrientationEdit, pathExtension: String? = nil) async throws -> URL {
        let output = folder.appending(component: "\(UUID().uuidString).\(pathExtension ?? source.pathExtension)", directoryHint: .notDirectory)

        return try await VideoEditRenderer(sourceURL: source, trim: TrimDescription(), orientation: edit, outputURL: output).render()
    }

    private func convert(_ preset: VideoConversionPreset, _ edit: OrientationEdit) async throws -> URL {
        let source = VideoConversionSource(
            input: TestBundleResources.shared.orientation_pattern_mov,
            output: folder.appending(component: "\(UUID().uuidString).mov", directoryHint: .notDirectory),
            options: VideoConversionOptions(preset: preset, container: .mov),
            orientation: edit
        )

        return try await VideoFormatConverter(source: source).convert().output
    }

    private static func videoTransform(of url: URL) async throws -> CGAffineTransform {
        let track = try #require(try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first)
        return try await track.load(.preferredTransform)
    }

    /// The frame at 1 s as AVFoundation displays it.
    private static func frame(of url: URL) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        return try await generator.image(at: CMTime(value: 1, timescale: 1)).image
    }

    /// `image` with the EXIF orientation of the same raw value performed on it.
    private static func oriented(_ image: CGImage, _ edit: OrientationEdit) throws -> CGImage {
        let orientation = try #require(CGImagePropertyOrientation(rawValue: UInt32(edit.rawValue)))
        let oriented = CIImage(cgImage: image).oriented(orientation)
        let atOrigin = oriented.transformed(by: CGAffineTransform(translationX: -oriented.extent.minX, y: -oriented.extent.minY))
        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])

        return try #require(context.createCGImage(atOrigin, from: atOrigin.extent, format: .RGBA8, colorSpace: image.colorSpace))
    }

    private static func pixels(_ image: CGImage) throws -> [UInt8] {
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

    private static func differences(_ lhs: CGImage, _ rhs: CGImage) throws -> [Int] {
        try #require(lhs.width == rhs.width && lhs.height == rhs.height, "\(lhs.width)×\(lhs.height) against \(rhs.width)×\(rhs.height)")

        return zip(try pixels(lhs), try pixels(rhs)).enumerated()
            .filter { $0.offset % 4 != 3 }
            .map { abs(Int($0.element.0) - Int($0.element.1)) }
    }

    private static func maxChannelDifference(_ lhs: CGImage, _ rhs: CGImage) throws -> Int {
        try differences(lhs, rhs).max() ?? 0
    }

    private static func meanChannelDifference(_ lhs: CGImage, _ rhs: CGImage) throws -> Double {
        let differences = try differences(lhs, rhs)
        return Double(differences.reduce(0, +)) / Double(max(1, differences.count))
    }
}
