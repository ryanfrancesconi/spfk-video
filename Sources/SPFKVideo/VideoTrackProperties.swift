// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import Foundation
import SwiftTimecode

/// Video stream technical properties (resolution, frame rate, codec, pixel aspect ratio,
/// rotation), read via AVFoundation (`AVAssetTrack`) rather than TagLib — these are
/// stream-technical facts, not tags. `nil` for pure-audio files.
public struct VideoTrackProperties: Hashable, Sendable, Codable {
    /// Current schema version `VideoTrackReader` populates. Bump this whenever a video-track read
    /// starts populating something it didn't before — a field on this type, or one of the sibling
    /// flags the same `loadVideoTrack()` call writes. `parserVersion < currentParserVersion` (see
    /// `isOutdated`) then reliably flags a value that was cached under an older reader and needs
    /// re-deriving from the source file -- unlike checking individual fields' nil-ness, which can't
    /// distinguish "this field didn't exist yet" from "this field is legitimately absent for this
    /// file" (e.g. `preciseFrameRate` is `nil` for plenty of freshly, fully parsed files whose
    /// exact rate doesn't match a standard-rate table entry).
    ///
    /// **This is the only thing that repairs already-imported elements**, so a fix to what a read
    /// records is not finished until this is bumped: the parser change alone reaches new files
    /// only, and every existing library keeps the stale value forever.
    ///
    /// 2: `duration` added, which anything cached under version 1 is missing.
    /// 3: nothing new on this type. `isDecodable` — whether the Matroska demuxer can decode a
    ///    container AVFoundation will not open — was never set on the import path, so every
    ///    Matroska element cached before this reads as unplayable however well it plays.
    /// 4: `startTimecodeString` added — the `tmcd` track's start value, which the reader
    ///    previously discarded while keeping only the frame rate it resolved alongside.
    public static let currentParserVersion = 4

    /// The schema version this value was populated at -- see `currentParserVersion`. Defaults
    /// to `nil` only when decoded from data that predates this field's existence; any value
    /// built through the memberwise `init` (including by `VideoTrackReader`) is stamped current
    /// unless told otherwise. `nil` is treated as older than every real version -- see `isOutdated`.
    public var parserVersion: Int?

    /// `true` when this value may be missing fields the current `VideoTrackReader` would
    /// populate, and should be re-derived from the source file rather than trusted as complete.
    public var isOutdated: Bool {
        (parserVersion ?? 0) < Self.currentParserVersion
    }

    /// Pixel width of the video track's natural (untransformed) size.
    public var width: Int?

    /// Pixel height of the video track's natural (untransformed) size.
    public var height: Int?

    /// Nominal frame rate in frames per second, as reported by `AVAssetTrack.nominalFrameRate`
    /// -- a single lossy `Float`, not a precisely measured rate. Prefer `preciseFrameRate`
    /// when it's available; this stays around as a fallback and for display of the raw
    /// as-reported value.
    public var nominalFrameRate: Float?

    /// The frame rate resolved against `swift-timecode`'s standard-rate table (23.976/24/25/
    /// 29.97(d)/30(d)/etc., including drop-frame detection), derived from the asset's exact
    /// rational frame duration rather than the lossy nominal `Float` -- see
    /// `AVAsset.timecodeFrameRate(drop:)`. `nil` when the real rate doesn't match a known
    /// standard rate, or detection fails.
    public var preciseFrameRate: TimecodeFrameRate?

    /// Duration of the video track in seconds.
    ///
    /// The *track's* duration, not the container's — they differ when a sibling audio track runs
    /// longer, which is common in phone video.
    public var duration: TimeInterval?

    /// The `tmcd` track's start timecode, verbatim (e.g. `01:00:00;01`). `nil` for a container
    /// with no timecode track.
    ///
    /// Stored as its string form because `Timecode` is not `Codable` and this value is cached
    /// alongside the rest of this type. The frame separator carries the drop flag, so the string
    /// is lossless where a bare frame count would not be — see ``startTimecode``.
    public var startTimecodeString: String?

    /// ``startTimecodeString`` parsed at ``timecodeFrameRate``.
    ///
    /// `nil` when either is absent, or when the stored string does not express a valid position at
    /// that rate — a mismatch that means the two were read from files with different rates, not
    /// something to render approximately.
    public var startTimecode: Timecode? {
        guard let startTimecodeString, let timecodeFrameRate else { return nil }

        guard let timecode = try? Timecode(.string(startTimecodeString), at: timecodeFrameRate),
              timecode.invalidComponents.isEmpty
        else {
            return nil
        }

        return timecode
    }

    /// Video codec identifier (e.g. a four-character-code string like "avc1", "hvc1"),
    /// derived from `AVAssetTrack.formatDescriptions`.
    public var codec: String?

    /// Pixel aspect ratio (width/height of a single pixel — 1.0 for square pixels).
    public var pixelAspectRatio: Double?

    /// Rotation baked into `AVAssetTrack.preferredTransform`, normalized to the nearest
    /// multiple of 90 degrees (0, 90, 180, or 270). This is what a portrait phone-shot
    /// video needs applied to preview right-side-up.
    public var rotationDegrees: Int?

    /// The rate to render this track's timecode at.
    ///
    /// ``preciseFrameRate`` when the exact rational rate matched a standard one, otherwise the
    /// standard rate nearest ``nominalFrameRate``. The fallback exists because a container can
    /// state a real frame rate that no rational match will find: Matroska gives a frame duration in
    /// whole nanoseconds, and 33333333ns is not exactly 1/30, so the exact matcher rejects a file
    /// whose rate is plainly 30. Such a file still has a rate, and rendering its duration as raw
    /// seconds is a display failure rather than an honest absence.
    ///
    /// **Drop-frame is excluded from the fallback only.** `asset.timecodeFrameRate()` detects it, so
    /// ``preciseFrameRate`` can be a drop rate and is returned as-is — which is what a *position*
    /// readout wants, since drop-frame is how positions are numbered. The fallback cannot know:
    /// `nominalFrameRate` is a bare fps and a container stating one carries no timecode track to
    /// read drop from, so guessing would mislabel every 29.97 file one way or the other.
    public var timecodeFrameRate: TimecodeFrameRate? {
        if let preciseFrameRate {
            return preciseFrameRate
        }

        guard let nominalFrameRate, nominalFrameRate > 0 else { return nil }

        let target = Double(nominalFrameRate)

        let nearest = TimecodeFrameRate.allCases
            .filter { !$0.isDrop }
            .min { abs($0.rate.doubleValue - target) < abs($1.rate.doubleValue - target) }

        // Tolerance rather than nearest-wins outright, so a genuinely non-standard rate reports
        // nothing instead of being rounded into a neighbor it does not belong to.
        guard let nearest, abs(nearest.rate.doubleValue - target) < 0.1 else { return nil }

        return nearest
    }

    public init(
        width: Int? = nil,
        height: Int? = nil,
        nominalFrameRate: Float? = nil,
        preciseFrameRate: TimecodeFrameRate? = nil,
        codec: String? = nil,
        duration: TimeInterval? = nil,
        startTimecodeString: String? = nil,
        pixelAspectRatio: Double? = nil,
        rotationDegrees: Int? = nil,
        parserVersion: Int? = Self.currentParserVersion
    ) {
        self.width = width
        self.height = height
        self.nominalFrameRate = nominalFrameRate
        self.preciseFrameRate = preciseFrameRate
        self.codec = codec
        self.duration = duration
        self.startTimecodeString = startTimecodeString
        self.pixelAspectRatio = pixelAspectRatio
        self.rotationDegrees = rotationDegrees
        self.parserVersion = parserVersion
    }
}
