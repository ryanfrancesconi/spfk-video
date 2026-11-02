// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import AVFoundation
import Foundation

/// What a file holds that a metadata write must not lose: its track types as `AVURLAsset` lists
/// them, and its audio length as `AVAudioFile` decodes it.
///
/// Read both before and after a write. The two readings come from different parsers, and a
/// malformed container can hide a track from one while the other still sees it.
public struct MediaTrackInventory: Sendable, Equatable {
    public let trackTypes: [AVMediaType]
    public let audioFrames: Int64

    public init(trackTypes: [AVMediaType], audioFrames: Int64) {
        self.trackTypes = trackTypes
        self.audioFrames = audioFrames
    }

    /// Unreadable reads as empty: a container AVFoundation cannot open (Matroska) has no opinion.
    public static func read(at url: URL) async -> MediaTrackInventory {
        let trackTypes = (try? await AVURLAsset(url: url).load(.tracks))?.map(\.mediaType) ?? []
        let audioFrames = (try? AVAudioFile(forReading: url))?.length ?? 0

        return MediaTrackInventory(trackTypes: trackTypes, audioFrames: audioFrames)
    }

    /// The loss between `self`, read before a write, and `after`; `nil` when nothing was lost.
    public func lostTracks(after: MediaTrackInventory, url: URL) -> VideoEditError? {
        var missing = VideoEditRenderer.missingEssentialTracks(source: trackTypes, output: after.trackTypes)

        if missing.isEmpty, audioFrames > 0, after.audioFrames <= 0 {
            missing = [.audio]
        }

        guard !missing.isEmpty else { return nil }

        return .tracksLostBySave(url, missing: missing.map { $0 == .audio ? "audio" : "video" })
    }
}
