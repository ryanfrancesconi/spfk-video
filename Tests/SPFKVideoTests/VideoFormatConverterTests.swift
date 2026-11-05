// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import AVFoundation
import Foundation
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKVideo

@Suite(.tags(.conversion))
struct VideoFormatConverterTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(component: "VideoFormatConverterTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func source(
        _ input: URL,
        _ preset: VideoConversionPreset,
        _ container: VideoConversionContainer,
        trim: TrimDescription? = nil
    ) -> VideoConversionSource {
        VideoConversionSource(
            input: input,
            output: folder.appending(component: "out.\(container.pathExtension)", directoryHint: .notDirectory),
            options: VideoConversionOptions(preset: preset, container: container),
            trim: trim
        )
    }

    private static func videoTrack(of url: URL) async throws -> AVAssetTrack {
        let tracks = try await AVURLAsset(url: url).loadTracks(withMediaType: .video)
        return try #require(tracks.first)
    }

    @Test(arguments: [false, true])
    func h264At720pScalesDownToFitAndNeverUp(usesLegacyExportPath: Bool) async throws {
        defer { try? FileManager.default.removeItem(at: folder) }

        let input = TestBundleResources.shared.sample_mov
        var converter = VideoFormatConverter(source: source(input, .h264_720p, .mp4))
        converter.usesLegacyExportPath = usesLegacyExportPath

        let result = try await converter.convert()

        let sourceSize = try await Self.videoTrack(of: input).load(.naturalSize)
        let outputSize = try await Self.videoTrack(of: result.output).load(.naturalSize)

        #expect(outputSize.width == min(1280, sourceSize.width))
        #expect(try await AVURLAsset(url: result.output).load(.isPlayable))
    }

    @Test func passthroughIntoMP4KeepsTheCodec() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }

        let input = TestBundleResources.shared.sample_mov
        let result = try await VideoFormatConverter(source: source(input, .passthrough, .mp4)).convert()

        func codec(_ url: URL) async throws -> FourCharCode? {
            try await Self.videoTrack(of: url).load(.formatDescriptions).first.map(CMFormatDescriptionGetMediaSubType)
        }

        #expect(result.output.pathExtension == "mp4")
        #expect(try await codec(result.output) == codec(input))
    }

    @Test func proResIntoMP4FailsNamingTheContainersItWrites() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }

        let item = source(TestBundleResources.shared.sample_mov, .proRes422, .mp4)

        do {
            _ = try await VideoFormatConverter(source: item).convert()
            Issue.record("ProRes was written to MP4")
        } catch let VideoConversionError.unsupportedContainer(container, preset, alternatives) {
            #expect(container == .mp4)
            #expect(preset == .proRes422)
            #expect(alternatives.contains("mov"))
        }

        #expect(!item.output.exists)
    }

    @Test func aTrimSetsTheOutputsLengthToWithinAFrame() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }

        let input = TestBundleResources.shared.sample_mov
        let duration = try await AVURLAsset(url: input).load(.duration).seconds
        let trim = TrimDescription(inPoint: duration * 0.25, outPoint: duration * 0.75)

        let result = try await VideoFormatConverter(source: source(input, .hevc1080p, .mov, trim: trim)).convert()

        let frameRate = try await Self.videoTrack(of: input).load(.nominalFrameRate)
        let outputDuration = try await AVURLAsset(url: result.output).load(.duration).seconds

        #expect(abs(outputDuration - (trim.outPoint - trim.inPoint)) <= 1 / Double(frameRate))
    }

    @Test func aReEncodeMixingAudioTracksIntoOneIsNotALoss() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }

        let input = TestBundleResources.shared.sample_dualaudio_mov
        let sourceAudio = try await AVURLAsset(url: input).loadTracks(withMediaType: .audio)
        try #require(sourceAudio.count > 1)

        let result = try await VideoFormatConverter(source: source(input, .h264_720p, .mov)).convert()

        #expect(try await AVURLAsset(url: result.output).loadTracks(withMediaType: .audio).isNotEmpty)
    }

    @Test func passthroughKeepsEveryAudioTrack() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }

        let input = TestBundleResources.shared.sample_dualaudio_mov
        let result = try await VideoFormatConverter(source: source(input, .passthrough, .mov)).convert()

        let sourceCount = try await AVURLAsset(url: input).loadTracks(withMediaType: .audio).count
        #expect(try await AVURLAsset(url: result.output).loadTracks(withMediaType: .audio).count == sourceCount)
    }

    @Test func matroskaFailsAsUnreadable() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }

        let item = source(TestBundleResources.shared.sample_mkv, .hevc1080p, .mov)

        do {
            _ = try await VideoFormatConverter(source: item).convert()
            Issue.record("Matroska converted")
        } catch let VideoConversionError.unreadable(url, _) {
            #expect(url == item.input)
        }

        #expect(!item.output.exists)
    }

    @Test func anOutputReplacingTheInputIsRefused() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }

        let input = folder.appending(component: "in.mov", directoryHint: .notDirectory)
        try FileManager.default.copyItem(at: TestBundleResources.shared.sample_mov, to: input)
        let before = try Data(contentsOf: input)

        var item = source(input, .passthrough, .mov)
        item.output = input

        await #expect(throws: VideoConversionError.self) {
            _ = try await VideoFormatConverter(source: item).convert()
        }

        #expect(try Data(contentsOf: input) == before)
    }

    @Test func cancellingMidExportLeavesNoOutput() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }

        let input = try await VideoTestFixture.makeTestVideo(duration: 10, size: CGSize(width: 1920, height: 1080))
        defer { try? FileManager.default.removeItem(at: input) }

        let item = source(input, .hevcHighestQuality, .mov)

        let task = Task {
            try await VideoFormatConverter(source: item).convert()
        }

        try await Task.sleep(for: .milliseconds(100))
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }

        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }
}
