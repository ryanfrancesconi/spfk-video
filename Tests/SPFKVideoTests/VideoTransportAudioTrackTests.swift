// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import AVFoundation
import Foundation
import SPFKTesting
import Testing

@testable import SPFKVideo

@MainActor
struct VideoTransportAudioTrackTests {
    /// Ready *and* listed: the track read is a separate asynchronous hop that lands after
    /// `readyToPlay`, so waiting on readiness alone races it.
    private func loadedTransport(
        url: URL = TestBundleResources.shared.sample_dualaudio_mov
    ) async -> VideoTransport {
        let transport = VideoTransport()
        transport.player.isMuted = true
        transport.load(url: url)

        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, !transport.isReady || transport.availableAudioTracks.isEmpty {
            try? await Task.sleep(for: .milliseconds(25))
        }

        return transport
    }

    /// The enabled audio tracks of the live player item, which is what is actually heard.
    private func enabledAudioTrackIDs(_ transport: VideoTransport) -> Set<AudioTrackDescription.ID> {
        let tracks = transport.player.currentItem?.tracks ?? []

        return Set(
            tracks
                .filter { $0.assetTrack?.mediaType == .audio && $0.isEnabled }
                .compactMap { $0.assetTrack.map { AudioTrackDescription.ID(persistentTrackID: $0.trackID) } }
        )
    }

    @Test func listsTheFilesAudioTracksOnceLoaded() async {
        let transport = await loadedTransport()

        #expect(transport.availableAudioTracks.count == 2)
        #expect(transport.availableAudioTracks.map(\.displayName) == ["English", "Japanese"])
    }

    /// Selecting a track enables exactly it. Anything less is inaudible as a choice: leaving the
    /// others enabled mixes them, and disabling everything mutes the file.
    @Test func selectingATrackEnablesOnlyThatTrack() async {
        let transport = await loadedTransport()

        let japanese = transport.availableAudioTracks.first { $0.language == "jpn" }
        guard let japanese else { return }

        transport.selectedAudioTrack = japanese.id

        #expect(enabledAudioTrackIDs(transport) == [japanese.id])
    }

    /// Switching back is the same operation, not a special case — a second selection must not
    /// leave the first one enabled alongside it.
    @Test func switchingBackEnablesOnlyTheOtherTrack() async {
        let transport = await loadedTransport()

        guard transport.availableAudioTracks.count == 2 else {
            Issue.record("fixture did not list two tracks")
            return
        }

        let english = transport.availableAudioTracks[0]
        let japanese = transport.availableAudioTracks[1]

        transport.selectedAudioTrack = japanese.id
        transport.selectedAudioTrack = english.id

        #expect(enabledAudioTrackIDs(transport) == [english.id])
    }

    /// A selection persisted against a file that no longer carries the track leaves the item alone.
    /// Disabling every track instead would make the file silent, which is worse than the wrong
    /// track and reads as a broken player.
    @Test func anUnknownSelectionLeavesTheItemAudible() async {
        let transport = await loadedTransport()

        let before = enabledAudioTrackIDs(transport)

        transport.selectedAudioTrack = AudioTrackDescription.ID(rawValue: 999_999)

        #expect(enabledAudioTrackIDs(transport) == before)
        #expect(enabledAudioTrackIDs(transport).isEmpty == false)
    }

    /// The selection outlives the file, so opening another that carries the same track resumes the
    /// user's intent rather than resetting them.
    @Test func keepsTheSelectionAcrossAnUnload() async {
        let transport = await loadedTransport()

        let japanese = transport.availableAudioTracks.first { $0.language == "jpn" }
        guard let japanese else { return }

        transport.selectedAudioTrack = japanese.id
        transport.unload()

        #expect(transport.availableAudioTracks.isEmpty)
        #expect(transport.selectedAudioTrack == japanese.id)
    }

    /// A single-track file lists one and offers no meaningful choice, which is what makes the
    /// control hide itself rather than showing a menu of one.
    @Test func listsOneTrackForAnOrdinaryMovie() async {
        let transport = await loadedTransport(url: TestBundleResources.shared.sample_mov)

        #expect(transport.availableAudioTracks.count == 1)
    }
}
