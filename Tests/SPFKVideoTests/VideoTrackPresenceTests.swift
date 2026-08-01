// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import Foundation
import SPFKTesting
import Testing

@testable import SPFKVideo

/// Covers `VideoTrackReader.hasVideoTrack(url:)`, whose whole reason to exist is that a
/// path-extension test can't answer this: callers guarding a destructive in-place operation
/// need the container's actual tracks, not its UTType.
@Suite
final class VideoTrackPresenceTests {
    @Test func reportsVideoTrackPresent() async throws {
        let url = try await VideoTestFixture.makeTestVideo(duration: 2)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(try await VideoTrackReader.hasVideoTrack(url: url))
    }

    /// An audio-only `.mp4` — the case that makes this distinct from an extension check, which
    /// resolves `mp4` to a movie UTType and would report it as video.
    @Test func reportsNoVideoTrackForAudioOnlyMP4() async throws {
        let url = TestBundleResources.shared.tabla_mp4

        #expect(try await VideoTrackReader.hasVideoTrack(url: url) == false)
    }

    /// Throws rather than reporting "no video", so a caller whose file safety depends on the
    /// answer can fail closed instead of reading an unreadable asset as audio.
    @Test func throwsRatherThanReportingNoVideoWhenUnreadable() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        await #expect(throws: (any Error).self) {
            try await VideoTrackReader.hasVideoTrack(url: url)
        }
    }
}
