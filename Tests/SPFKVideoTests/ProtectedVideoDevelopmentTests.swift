// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import AVFoundation
import Foundation
import SPFKTesting
import Testing

@testable import SPFKVideo

enum ProtectedMediaFixture {
    static var url: URL? {
        guard let path = ProcessInfo.processInfo.environment["SPFK_PROTECTED_MEDIA"], path.isEmpty == false else {
            return nil
        }

        let url = URL(fileURLWithPath: path)

        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

/// Walks a FairPlay-protected file (iTunes purchase, `drms`/`drmi` sample entries) through each
/// AVFoundation read ShadowTag makes when the file is selected, in that order, printing before and
/// after each. A process that is killed leaves no crash report, so the last "begin" line without
/// its "done" is the only record of which read did it.
///
/// One test per stage rather than one test walking every stage: a kill ends the process, so a
/// stage past the fatal one can only be reached by running it on its own with `-only-testing`.
///
/// Skipped unless `SPFK_PROTECTED_MEDIA` names a file; `xcodebuild` needs it as
/// `TEST_RUNNER_SPFK_PROTECTED_MEDIA`, since it does not forward the parent environment.
@Suite(.tags(.development), .serialized, .enabled(if: ProtectedMediaFixture.url != nil))
final class ProtectedVideoDevelopmentTests {
    private let url: URL

    init() throws {
        url = try #require(ProtectedMediaFixture.url)
    }

    private func stage<T>(
        _ name: String,
        isolation: isolated (any Actor)? = #isolation,
        _ body: () async throws -> T
    ) async rethrows -> T {
        print("PROTECTED: begin \(name)")
        let result = try await body()
        print("PROTECTED: done  \(name)")
        return result
    }

    private func fourCC(_ code: FourCharCode) -> String {
        let bytes = [UInt8((code >> 24) & 0xFF), UInt8((code >> 16) & 0xFF), UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF)]
        return String(bytes: bytes, encoding: .ascii) ?? "?"
    }

    // MARK: - Stages, in the order `TagViewCoordinator.load(element:)` reaches them

    /// The asset-level questions AVFoundation answers before any decode.
    @Test func a_assetProperties() async throws {
        let asset = AVURLAsset(url: url)

        let isPlayable = try await stage("asset.isPlayable") { try await asset.load(.isPlayable) }
        print("PROTECTED: isPlayable \(isPlayable)")

        let isProtected = try await stage("asset.hasProtectedContent") { try await asset.load(.hasProtectedContent) }
        print("PROTECTED: hasProtectedContent \(isProtected)")

        let isReadable = try await stage("asset.isReadable") { try await asset.load(.isReadable) }
        print("PROTECTED: isReadable \(isReadable)")

        let isExportable = try await stage("asset.isExportable") { try await asset.load(.isExportable) }
        print("PROTECTED: isExportable \(isExportable)")

        let duration = try await stage("asset.duration") { try await asset.load(.duration) }
        print("PROTECTED: duration \(duration.seconds)")

        let tracks = try await stage("asset.tracks") { try await asset.load(.tracks) }
        for track in tracks {
            let formats = try await track.load(.formatDescriptions)
            let subtypes = formats.map { fourCC(CMFormatDescriptionGetMediaSubType($0)) }
            let isEnabled = try await track.load(.isEnabled)
            let isPlayableTrack = try await track.load(.isPlayable)
            let isDecodable = try await track.load(.isDecodable)
            print(
                "PROTECTED: track \(track.trackID) \(track.mediaType.rawValue) \(subtypes) enabled=\(isEnabled) playable=\(isPlayableTrack) decodable=\(isDecodable)"
            )
        }
    }

    /// What the import stores: the video track properties, user data and the playable flag.
    @Test func b_videoTrackReader() async throws {
        let result = await stage("VideoTrackReader.read") { await VideoTrackReader.read(from: url) }
        print("PROTECTED: isPlayable \(result.isPlayable) hasProtectedContent \(result.hasProtectedContent)")
        print("PROTECTED: videoTrack \(String(describing: result.videoTrack))")
        print("PROTECTED: quickTimeUserData \(String(describing: result.quickTimeUserData))")

        let hasVideo = try await stage("VideoTrackReader.hasVideoTrack") { try await VideoTrackReader.hasVideoTrack(url: url) }
        print("PROTECTED: hasVideoTrack \(hasVideo)")
    }

    /// The audio track listing behind the track menu.
    @Test func c_audioTrackReader() async {
        let tracks = await stage("AudioTrackReader.read") { await AudioTrackReader.read(from: url) }
        for track in tracks {
            print("PROTECTED: audio track \(track)")
        }
    }

    /// The waveform scan's open and first read.
    @Test func d_audioFileRead() async throws {
        let file = try await stage("AVAudioFile(forReading:)") { try AVAudioFile(forReading: url) }
        print("PROTECTED: length \(file.length) format \(file.processingFormat)")

        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096))
        await stage("AVAudioFile.read") {
            do {
                try file.read(into: buffer)
                print("PROTECTED: read \(buffer.frameLength) frames")
            } catch {
                print("PROTECTED: read threw \(error)")
            }
        }
    }

    /// The filmstrip's duration probe.
    @Test func e_frameExtractorDuration() async throws {
        let duration = try await stage("VideoFrameExtractor.duration") { try await VideoFrameExtractor.duration(of: url) }
        print("PROTECTED: video track duration \(duration)")
    }

    /// The filmstrip's frame decode.
    @Test func f_frameExtractorFrames() async throws {
        let frames = try await stage("VideoFrameExtractor.frames") {
            try await VideoFrameExtractor.frames(from: url, at: [1, 60], maximumSize: CGSize(width: 0, height: 64))
        }
        print("PROTECTED: extracted \(frames.count) frames")
    }

    /// The video preview's player. Loads, waits for the item to settle, then plays for a second.
    @Test @MainActor func g_transport() async throws {
        let transport = VideoTransport()

        await stage("VideoTransport.load") {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                var resumed = false
                transport.eventHandler = { event in
                    guard event == .readyChanged, !resumed else { return }
                    resumed = true
                    continuation.resume()
                }
                transport.load(url: url)
            }
        }

        let item = try #require(transport.player.currentItem)
        print("PROTECTED: item status \(item.status.rawValue) error \(String(describing: item.error))")
        print("PROTECTED: isReady \(transport.isReady) duration \(transport.duration)")

        await stage("VideoTransport.play") {
            transport.play()
            try? await Task.sleep(for: .seconds(1))
            transport.pause()
        }
        print("PROTECTED: player error \(String(describing: transport.player.error)) time \(transport.currentTime)")

        transport.unload()
    }

    /// The same load with an `AVPlayerLayer` attached, which is what the preview does and what
    /// starts the out-of-process video decoder.
    @Test @MainActor func h_transportWithLayer() async throws {
        let transport = VideoTransport()
        let layer = AVPlayerLayer(player: transport.player)
        layer.frame = CGRect(x: 0, y: 0, width: 640, height: 272)

        await stage("VideoTransport.load with AVPlayerLayer") {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                var resumed = false
                transport.eventHandler = { event in
                    guard event == .readyChanged, !resumed else { return }
                    resumed = true
                    continuation.resume()
                }
                transport.load(url: url)
            }
        }

        let item = try #require(transport.player.currentItem)
        print("PROTECTED: item status \(item.status.rawValue) error \(String(describing: item.error))")

        await stage("VideoTransport.play with AVPlayerLayer") {
            transport.play()
            try? await Task.sleep(for: .seconds(2))
            transport.pause()
        }
        print("PROTECTED: layer isReadyForDisplay \(layer.isReadyForDisplay) time \(transport.currentTime)")

        transport.unload()
    }
}
