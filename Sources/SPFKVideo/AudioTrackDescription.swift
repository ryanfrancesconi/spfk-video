// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import Foundation

/// One selectable audio track of a video file, in terms neither playback backend owns.
///
/// A dual-audio film states two, and which one plays is the user's choice rather than the muxer's
/// ordering. The two backends answer that question by unrelated mechanisms — Matroska reopens its
/// demuxer on a different `TrackNumber`, AVFoundation enables a track on a live player item — so
/// nothing here mentions reopening, seeking, or a track number. A backend answers "which tracks"
/// and "use this one", and maps ``id`` back to its own object.
///
/// Lives in `spfk-video` because both backends and both products must reach it. It cannot live in
/// `spfk-matroska`: that package already depends on this one, so the edge back would be a cycle.
public struct AudioTrackDescription: Hashable, Sendable, Identifiable {
    /// A track's identity, stable across reopens of the same file.
    ///
    /// Matroska fills it from `TrackUID` and AVFoundation from `CMPersistentTrackID`, both of which
    /// survive in the file. **Not a track number or an index** — those are positional, and a remux
    /// renumbers them, which is exactly what a persisted selection must not depend on. The wrapper
    /// exists to make that confusion a compile error rather than a wrong track.
    public struct ID: Hashable, Sendable, Codable, RawRepresentable {
        public let rawValue: UInt64

        public init(rawValue: UInt64) {
            self.rawValue = rawValue
        }

        /// AVFoundation's `CMPersistentTrackID` is signed; the bit pattern round-trips.
        public init(persistentTrackID: Int32) {
            rawValue = UInt64(UInt32(bitPattern: persistentTrackID))
        }
    }

    public let id: ID

    /// The container's own name for the track, when it states one — Matroska's `Name`, QuickTime's
    /// `udta/name`.
    public let name: String?

    /// As the container spells it, un-normalized: Matroska writes ISO-639-2 (`jpn`) or BCP-47,
    /// QuickTime ISO-639-2. Resolving it to a display language is ``displayName``'s job.
    public let language: String?

    /// A codec name for the picker's benefit, not for dispatch — `A_AAC`, `aac`, whatever the
    /// backend calls it.
    public let codec: String?

    public let channelCount: Int?
    public let sampleRate: Double?

    /// **No default-track flag, deliberately.** Matroska's `FlagDefault` is one libwebm's parser
    /// discards — `kMkvFlagDefault` is in its ID table and nothing reads it, so there is no
    /// accessor to bridge — and QuickTime's per-track enabled bit answers a different question.
    /// A field one backend can only ever answer `false` to is worse than an absent one, and
    /// nothing needs it: initial selection is the first track either way.
    public init(
        id: ID,
        name: String? = nil,
        language: String? = nil,
        codec: String? = nil,
        channelCount: Int? = nil,
        sampleRate: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.language = language
        self.codec = codec
        self.channelCount = channelCount
        self.sampleRate = sampleRate
    }
}

// MARK: - Display

extension AudioTrackDescription {
    /// A label for a picker, which always has one: the container's name, else the language spelled
    /// out, else the codec, else the identifier.
    ///
    /// The container's name wins even when a language is also present, because a muxer that
    /// bothered to name a track said something a language code cannot — "Director's Commentary" is
    /// `eng` too.
    public var displayName: String {
        if let name, name.isEmpty == false {
            return name
        }

        if let localizedLanguage {
            return localizedLanguage
        }

        if let codec, codec.isEmpty == false {
            return codec
        }

        return "\(id.rawValue)"
    }

    /// ``language`` as a reader's own language names it, or `nil` when it is absent or is a code
    /// `Locale` cannot resolve.
    ///
    /// `und` — Matroska's default when a muxer states nothing — resolves to a real string
    /// ("Unknown language"), which is worse than falling through to the codec, so it is refused
    /// here.
    public var localizedLanguage: String? {
        guard let language, language.isEmpty == false, language != "und" else { return nil }

        return Locale.current.localizedString(forIdentifier: language)
            ?? Locale.current.localizedString(forLanguageCode: language)
    }
}
