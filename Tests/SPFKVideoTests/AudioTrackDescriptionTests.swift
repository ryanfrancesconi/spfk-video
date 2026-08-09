// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import Foundation
import Testing

@testable import SPFKVideo

struct AudioTrackDescriptionTests {
    private func description(
        name: String? = nil,
        language: String? = nil,
        codec: String? = nil
    ) -> AudioTrackDescription {
        AudioTrackDescription(
            id: AudioTrackDescription.ID(rawValue: 7),
            name: name,
            language: language,
            codec: codec
        )
    }

    /// A muxer that named a track said something a language code cannot, so the name wins even when
    /// both are present.
    @Test func prefersTheContainersOwnNameOverTheLanguage() {
        let track = description(name: "Director's Commentary", language: "eng")

        #expect(track.displayName == "Director's Commentary")
    }

    /// An empty `Name` is what a muxer writes for "no name", and it must not win the fallback chain
    /// as a blank label.
    @Test func treatsAnEmptyNameAsAbsent() {
        let track = description(name: "", language: "jpn")

        #expect(track.displayName == description(language: "jpn").displayName)
        #expect(track.displayName.isEmpty == false)
    }

    /// ISO-639-2 is what both containers write, and a bare `jpn` is not a label.
    @Test func spellsALanguageCodeOut() {
        #expect(description(language: "jpn").localizedLanguage == "Japanese")
        #expect(description(language: "eng").localizedLanguage == "English")
    }

    /// Matroska's default when a muxer states nothing. `Locale` resolves it to a real string, which
    /// would win the chain and label every unlabeled track identically — the codec is more use.
    @Test func refusesUndeterminedAsALanguage() {
        let track = description(language: "und", codec: "A_AAC")

        #expect(track.localizedLanguage == nil)
        #expect(track.displayName == "A_AAC")
    }

    /// The chain always terminates, so a picker never draws an empty row.
    @Test func fallsBackToTheIdentifierWhenNothingIsStated() {
        #expect(description().displayName == "7")
    }

    /// The signed-to-unsigned conversion is a bit pattern, so two AVFoundation tracks cannot
    /// collide on one identifier.
    @Test func roundTripsAPersistentTrackID() {
        let ids = [Int32(1), Int32(2), Int32(3), .max, .min, -1]

        #expect(Set(ids.map { AudioTrackDescription.ID(persistentTrackID: $0) }).count == ids.count)
    }
}
