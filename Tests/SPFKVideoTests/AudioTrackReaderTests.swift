// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import AVFoundation
import Foundation
import SPFKTesting
import Testing

@testable import SPFKVideo

struct AudioTrackReaderTests {
    /// The fixture's two tone tracks, named and languaged — everything a picker draws a row from.
    @Test func readsBothTracksOfADualAudioMovie() async {
        let tracks = await AudioTrackReader.read(from: TestBundleResources.shared.sample_dualaudio_mov)

        #expect(tracks.count == 2)
        #expect(tracks.map(\.language) == ["eng", "jpn"])
        #expect(tracks.map(\.displayName) == ["English", "Japanese"])
        // `"aac"`, not `"aac "` — a four-character code pads with spaces and this one reaches a
        // menu row.
        #expect(tracks.allSatisfy { $0.codec == "aac" })
        #expect(tracks.allSatisfy { $0.channelCount == 1 })
        #expect(tracks.allSatisfy { $0.sampleRate == 44100 })
    }

    /// **An audio container, not a movie.** An `.m4a` carries alternate tracks exactly as its `.mp4`
    /// sibling does, so anything that lists tracks only for video files leaves this one with no
    /// picker at all.
    ///
    /// The fixture states no track names, so the rows come from the language codes alone.
    @Test func readsBothTracksOfADualAudioMPEG4AudioFile() async {
        let tracks = await AudioTrackReader.read(from: TestBundleResources.shared.dualaudio_m4a)

        #expect(tracks.count == 2)
        #expect(tracks.map(\.language) == ["eng", "jpn"])
        #expect(tracks.map(\.name) == [nil, nil])
        #expect(tracks.map(\.displayName) == ["English", "Japanese"])
        #expect(tracks.allSatisfy { $0.codec == "aac" })
    }

    /// Distinct identifiers are what makes a selection addressable at all; equal ones would silently
    /// select the first match every time.
    @Test func givesEachTrackItsOwnIdentifier() async {
        let tracks = await AudioTrackReader.read(from: TestBundleResources.shared.sample_dualaudio_mov)

        #expect(Set(tracks.map(\.id)).count == tracks.count)
    }

    /// A single-track file still lists, so the caller decides whether one is worth a choice.
    @Test func listsASingleTrackFileToo() async {
        let tracks = await AudioTrackReader.read(from: TestBundleResources.shared.sample_mov)

        #expect(tracks.count == 1)
    }

    /// Matroska is absent from `AVURLAsset.audiovisualTypes()`, so this is the path where the
    /// AVFoundation backend has nothing to say and the Matroska one answers instead. Empty rather
    /// than a throw: both mean "no choice to offer here".
    @Test func returnsNothingForAContainerAVFoundationCannotOpen() async {
        let tracks = await AudioTrackReader.read(from: TestBundleResources.shared.sample_dualaudio_mkv)

        #expect(tracks.isEmpty)
    }
}
