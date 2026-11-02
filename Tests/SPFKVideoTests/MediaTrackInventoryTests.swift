// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import AVFoundation
import Foundation
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKVideo

@Suite
struct MediaTrackInventoryTests {
    @Test func anUnchangedFileLosesNothing() async {
        let url = TestBundleResources.shared.sample_mov
        let before = await MediaTrackInventory.read(at: url)
        let after = await MediaTrackInventory.read(at: url)

        #expect(before.trackTypes.contains(.audio))
        #expect(before.trackTypes.contains(.video))
        #expect(before.lostTracks(after: after, url: url) == nil)
    }

    @Test(arguments: [(AVMediaType.audio, "audio"), (AVMediaType.video, "video")])
    func aDroppedTrackIsReportedAsLostBySave(dropped: AVMediaType, name: String) async throws {
        let source = TestBundleResources.shared.sample_mov
        let damaged = try await MediaTrackCopy.copyDroppingTracks(of: source, mediaType: dropped)
        defer { try? FileManager.default.removeItem(at: damaged) }

        let before = await MediaTrackInventory.read(at: source)
        let after = await MediaTrackInventory.read(at: damaged)

        let error = try #require(before.lostTracks(after: after, url: source))
        guard case let .tracksLostBySave(url, missing) = error else {
            Issue.record("expected .tracksLostBySave, got \(error)")
            return
        }

        #expect(url == source)
        #expect(missing == [name])
    }

    /// The track list alone can be blind to audio that `AVAudioFile` still decodes.
    @Test func audioThatStopsDecodingIsLostEvenWhenTheTrackListAgrees() {
        let before = MediaTrackInventory(trackTypes: [.video], audioFrames: 48000)
        let after = MediaTrackInventory(trackTypes: [.video], audioFrames: 0)
        let url = URL(fileURLWithPath: "/tmp/x.mov")

        guard case let .tracksLostBySave(_, missing) = before.lostTracks(after: after, url: url) else {
            Issue.record("expected .tracksLostBySave")
            return
        }

        #expect(missing == ["audio"])
    }

    @Test func aContainerAVFoundationCannotOpenHasNoOpinion() async {
        let url = TestBundleResources.shared.sample_mkv
        let inventory = await MediaTrackInventory.read(at: url)

        #expect(inventory == MediaTrackInventory(trackTypes: [], audioFrames: 0))
        #expect(inventory.lostTracks(after: inventory, url: url) == nil)
    }

    @Test func theMessageSaysTheFileWasChanged() throws {
        let error = VideoEditError.tracksLostBySave(URL(fileURLWithPath: "/tmp/clip.mov"), missing: ["audio"])
        let message = try #require(error.errorDescription)

        #expect(message.contains("clip.mov"))
        #expect(message.contains("audio"))
        #expect(!message.contains("unchanged"))
    }
}
