// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import AVFoundation
import Foundation
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKVideo

@Suite
final class VideoEditRendererTests {
    // MARK: - Track survival

    /// **A render that lost the audio must not be handed back.** A passthrough export writes what
    /// the destination container accepts and reports success either way, and the caller replaces
    /// the user's original with the result — so a dropped track is permanent, silent data loss.
    @Test func aDroppedAudioTrackIsDetected() {
        let missing = VideoEditRenderer.missingEssentialTracks(
            source: [.video, .audio, .timecode],
            output: [.video, .timecode]
        )

        #expect(missing == [.audio])
    }

    @Test func aDroppedVideoTrackIsDetected() {
        let missing = VideoEditRenderer.missingEssentialTracks(
            source: [.video, .audio],
            output: [.audio]
        )

        #expect(missing == [.video])
    }

    /// Losing one of several audio tracks counts. A file with commentary or a dub comes back
    /// looking playable, and only the extra track is gone.
    @Test func losingOneOfSeveralAudioTracksIsDetected() {
        let missing = VideoEditRenderer.missingEssentialTracks(
            source: [.video, .audio, .audio],
            output: [.video, .audio]
        )

        #expect(missing == [.audio])
    }

    /// Timecode, telemetry and text tracks are dropped by every passthrough export — a GoPro's
    /// `tmcd` and `gpmd` do not survive one. Refusing those renders would block ordinary edits to
    /// protect data the container was never going to keep.
    @Test func droppingNonEssentialTracksIsAllowed() {
        let missing = VideoEditRenderer.missingEssentialTracks(
            source: [.video, .audio, .timecode, .metadata, .text],
            output: [.video, .audio]
        )

        #expect(missing.isEmpty)
    }

    @Test func anUnchangedTrackSetPasses() {
        let missing = VideoEditRenderer.missingEssentialTracks(
            source: [.video, .audio],
            output: [.video, .audio]
        )

        #expect(missing.isEmpty)
    }

    /// The guard has to stay quiet on the ordinary path, or it trades silent loss for a render
    /// nobody can complete.
    @Test func arealRenderPassesTheGuard() async throws {
        let source = try await Self.videoWithAudio(duration: 8)
        defer { try? FileManager.default.removeItem(at: source) }

        let output = try await Self.render(source, TrimDescription(inPoint: 2, outPoint: 5))
        defer { try? FileManager.default.removeItem(at: output) }

        let tracks = try await AVURLAsset(url: output).load(.tracks).map(\.mediaType)
        #expect(tracks.contains(.audio))
        #expect(tracks.contains(.video))
    }

    /// End to end: an export that really does drop a track must throw rather than return a URL,
    /// and must not leave the partial render behind for a caller to swap in.
    @Test func aRenderThatDropsATrackThrows() async throws {
        let source = try await Self.videoWithAudio(duration: 8)
        defer { try? FileManager.default.removeItem(at: source) }

        // An audio-only container cannot carry the video track, so the export drops it and still
        // reports success — the same shape as a container that cannot carry the audio.
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        defer { try? FileManager.default.removeItem(at: output) }

        let renderer = VideoEditRenderer(
            sourceURL: source,
            trim: TrimDescription(inPoint: 0, outPoint: 5),
            outputURL: output
        )

        // Specifically `.tracksLost`: `.unsupportedOutputContainer` is also a `VideoEditError`, and
        // accepting it would let this pass with the guard deleted.
        do {
            _ = try await renderer.render()
            Issue.record("render returned instead of throwing")
        } catch let error as VideoEditError {
            guard case let .tracksLost(_, missing) = error else {
                Issue.record("expected .tracksLost, got \(error)")
                return
            }
            #expect(missing == ["video"])
        }

        #expect(!FileManager.default.fileExists(atPath: output.path), "partial render left behind")
    }

    // MARK: - Trimming

    @Test func producesTheRequestedDuration() async throws {
        let source = try await Self.videoWithAudio(duration: 8)
        defer { try? FileManager.default.removeItem(at: source) }

        let output = try await Self.render(source, TrimDescription(inPoint: 2, outPoint: 5))
        defer { try? FileManager.default.removeItem(at: output) }

        let duration = try await AVURLAsset(url: output).load(.duration).seconds
        #expect(abs(duration - 3.0) < 0.05, "expected ~3s, got \(duration)s")
    }

    /// An `outPoint` of 0 means "keep to the end", the same convention the audio path uses.
    @Test func keepsToTheEndWhenOutPointIsZero() async throws {
        let source = try await Self.videoWithAudio(duration: 8)
        defer { try? FileManager.default.removeItem(at: source) }

        let sourceDuration = try await AVURLAsset(url: source).load(.duration).seconds

        let output = try await Self.render(source, TrimDescription(inPoint: 3, outPoint: 0))
        defer { try? FileManager.default.removeItem(at: output) }

        let duration = try await AVURLAsset(url: output).load(.duration).seconds
        #expect(abs(duration - (sourceDuration - 3)) < 0.1)
    }

    /// The property the whole design rests on: passthrough is frame-accurate on the in-point, so
    /// the first frame of the output is the source's frame at that time and not the preceding
    /// keyframe. Zero tolerance on both extractions — the default wide tolerance would let a
    /// neighbouring frame satisfy this and hide exactly the drift being tested for.
    @Test func trimsToTheExactRequestedFrame() async throws {
        let source = try await Self.videoWithAudio(duration: 8)
        defer { try? FileManager.default.removeItem(at: source) }

        let inPoint: TimeInterval = 3.5
        let output = try await Self.render(source, TrimDescription(inPoint: inPoint, outPoint: 6))
        defer { try? FileManager.default.removeItem(at: output) }

        let sourceFrame = try await VideoFrameExtractor.frames(
            from: source, at: [inPoint], tolerance: 0
        )[inPoint]
        let outputFrame = try await VideoFrameExtractor.frames(
            from: output, at: [0], tolerance: 0
        )[0]

        let expected = try #require(sourceFrame.flatMap { $0.dataProvider?.data as Data? })
        let actual = try #require(outputFrame.flatMap { $0.dataProvider?.data as Data? })

        #expect(actual == expected, "first output frame is not the source frame at \(inPoint)s")
    }

    // MARK: - Tracks

    @Test func preservesBothTracks() async throws {
        let source = try await Self.videoWithAudio(duration: 6)
        defer { try? FileManager.default.removeItem(at: source) }

        let output = try await Self.render(source, TrimDescription(inPoint: 1, outPoint: 4))
        defer { try? FileManager.default.removeItem(at: output) }

        let asset = AVURLAsset(url: output)
        #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
    }

    /// Passthrough copies the encoded media rather than re-encoding, so the video track's
    /// dimensions and frame rate survive unchanged.
    @Test func preservesVideoTrackProperties() async throws {
        let source = try await Self.videoWithAudio(duration: 6)
        defer { try? FileManager.default.removeItem(at: source) }

        let before = try #require(await VideoTrackReader.read(from: source).videoTrack)

        let output = try await Self.render(source, TrimDescription(inPoint: 1, outPoint: 4))
        defer { try? FileManager.default.removeItem(at: output) }

        let after = try #require(await VideoTrackReader.read(from: output).videoTrack)

        #expect(after.width == before.width)
        #expect(after.height == before.height)
        #expect(after.codec == before.codec)

        let beforeRate = try #require(before.nominalFrameRate)
        let afterRate = try #require(after.nominalFrameRate)

        // Tolerate one frame. `nominalFrameRate` on a trimmed track is derived from the samples
        // actually present, so whether the frame sitting exactly on the out point lands inside the
        // range moves the result by 1/duration -- 89 frames over 3s reads as 29.67 rather than 30.
        // That is a boundary rounding artifact, not the frame rate failing to survive the trim, and
        // it surfaces only when something else on the machine perturbs the fixture's timing.
        let trimmedDuration: Float = 4 - 1
        #expect(abs(afterRate - beforeRate) < 1 / trimmedDuration + 0.01)
    }

    @Test func rendersASourceWithNoAudioTrack() async throws {
        let source = try await VideoTestFixture.makeTestVideo(duration: 6)
        defer { try? FileManager.default.removeItem(at: source) }

        let output = try await Self.render(source, TrimDescription(inPoint: 1, outPoint: 4))
        defer { try? FileManager.default.removeItem(at: output) }

        let asset = AVURLAsset(url: output)
        #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
        #expect(try await asset.loadTracks(withMediaType: .audio).isEmpty)

        let duration = try await asset.load(.duration).seconds
        #expect(abs(duration - 3.0) < 0.05)
    }

    // MARK: - Refusals

    /// A transport stream is readable but not writable by the export session. Asked of the
    /// session rather than matched against a hardcoded list, so this covers any container the
    /// running build can't write.
    @Test func refusesAContainerTheExportSessionCannotWrite() async throws {
        let source = try await VideoTestFixture.makeTestVideo(duration: 4)
        defer { try? FileManager.default.removeItem(at: source) }

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ts")

        await #expect(throws: VideoEditError.self) {
            try await VideoEditRenderer(
                sourceURL: source,
                trim: TrimDescription(inPoint: 1, outPoint: 2),
                outputURL: output
            ).render()
        }
        #expect(!output.exists)
    }

    @Test func refusesAnExistingOutput() async throws {
        let source = try await VideoTestFixture.makeTestVideo(duration: 4)
        defer { try? FileManager.default.removeItem(at: source) }

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        try Data("occupied".utf8).write(to: output)
        defer { try? FileManager.default.removeItem(at: output) }

        await #expect(throws: VideoEditError.self) {
            try await VideoEditRenderer(
                sourceURL: source,
                trim: TrimDescription(inPoint: 1, outPoint: 2),
                outputURL: output
            ).render()
        }

        // The pre-existing file must be left exactly as it was.
        #expect(try Data(contentsOf: output) == Data("occupied".utf8))
    }

    @Test func refusesATrimStartingPastTheEndOfTheSource() async throws {
        let source = try await VideoTestFixture.makeTestVideo(duration: 4)
        defer { try? FileManager.default.removeItem(at: source) }

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        await #expect(throws: VideoEditError.self) {
            try await VideoEditRenderer(
                sourceURL: source,
                trim: TrimDescription(inPoint: 30, outPoint: 40),
                outputURL: output
            ).render()
        }
        #expect(!output.exists)
    }

    /// An out-point past the end is clamped rather than refused — a trim stored against a
    /// slightly different duration is a rounding artifact, not a mistake.
    @Test func clampsAnOutPointPastTheEndOfTheSource() async throws {
        let source = try await VideoTestFixture.makeTestVideo(duration: 4)
        defer { try? FileManager.default.removeItem(at: source) }

        let output = try await Self.render(source, TrimDescription(inPoint: 1, outPoint: 30))
        defer { try? FileManager.default.removeItem(at: output) }

        let duration = try await AVURLAsset(url: output).load(.duration).seconds
        #expect(abs(duration - 3.0) < 0.1)
    }

    // MARK: - Export paths

    /// Both export paths must produce the same result. `#available(macOS 15, *)` is true on every
    /// current development and CI machine, so without forcing it the pre-15 branch — the one
    /// macOS 13/14 users actually run — would never execute anywhere before shipping.
    @Test(arguments: [false, true])
    func bothExportPathsProduceTheSameTrim(usesLegacyExportPath: Bool) async throws {
        let source = try await Self.videoWithAudio(duration: 8)
        defer { try? FileManager.default.removeItem(at: source) }

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        defer { try? FileManager.default.removeItem(at: output) }

        let renderer = VideoEditRenderer(
            sourceURL: source,
            trim: TrimDescription(inPoint: 2, outPoint: 5),
            outputURL: output
        )
        await renderer.setUsesLegacyExportPath(usesLegacyExportPath)
        try await renderer.render()

        let asset = AVURLAsset(url: output)
        let duration = try await asset.load(.duration).seconds
        #expect(abs(duration - 3.0) < 0.05, "expected ~3s, got \(duration)s")
        #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
    }

    /// The legacy path must report a refusal the same way the modern one does, rather than
    /// leaving a partial file behind.
    @Test func legacyExportPathStillRefusesAnUnwritableContainer() async throws {
        let source = try await VideoTestFixture.makeTestVideo(duration: 4)
        defer { try? FileManager.default.removeItem(at: source) }

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ts")

        let renderer = VideoEditRenderer(
            sourceURL: source,
            trim: TrimDescription(inPoint: 1, outPoint: 2),
            outputURL: output
        )
        await renderer.setUsesLegacyExportPath(true)

        await #expect(throws: VideoEditError.self) {
            try await renderer.render()
        }
        #expect(!output.exists)
    }

    // MARK: - Helpers

    private static func render(_ source: URL, _ trim: TrimDescription) async throws -> URL {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        return try await VideoEditRenderer(sourceURL: source, trim: trim, outputURL: output).render()
    }

    /// Builds a two-track `.mov` by composing the synthetic video fixture with the bundled
    /// tabla audio, so the both-tracks cases exercise a real muxed file.
    private static func videoWithAudio(duration: TimeInterval) async throws -> URL {
        let videoOnly = try await VideoTestFixture.makeTestVideo(duration: duration)
        defer { try? FileManager.default.removeItem(at: videoOnly) }

        let composition = AVMutableComposition()

        let videoAsset = AVURLAsset(url: videoOnly)
        let sourceVideo = try #require(try await videoAsset.loadTracks(withMediaType: .video).first)
        let videoTrack = try #require(
            composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        )
        let videoRange = try await sourceVideo.load(.timeRange)
        try videoTrack.insertTimeRange(videoRange, of: sourceVideo, at: .zero)

        let audioAsset = AVURLAsset(url: TestBundleResources.shared.tabla_mp4)
        if let sourceAudio = try await audioAsset.loadTracks(withMediaType: .audio).first {
            let audioTrack = try #require(
                composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            )
            let audioDuration = try await audioAsset.load(.duration)
            let range = CMTimeRange(start: .zero, duration: min(audioDuration, videoRange.duration))
            try audioTrack.insertTimeRange(range, of: sourceAudio, at: .zero)
        }

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        let session = try #require(
            AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough)
        )
        session.outputURL = output
        session.outputFileType = .mov

        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { c.resume() }
        }
        guard session.status == .completed else {
            throw VideoEditError.exportFailed(output, underlying: session.error)
        }
        return output
    }
}
