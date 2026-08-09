// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import AVFoundation
import CoreMedia
import Foundation
import SPFKBase

/// Lists a file's selectable audio tracks through AVFoundation.
///
/// The counterpart to the Matroska demuxer's own listing, producing the same neutral type so a
/// picker is written once. Returns an empty array rather than throwing for a container
/// AVFoundation cannot open — that file has a different backend, and a listing that failed and one
/// that found nothing lead to the same place: no choice to offer.
public enum AudioTrackReader {
    /// Every audio track of the asset at `url`, in stored order.
    ///
    /// A single track is the ordinary case and still returned, so a caller decides for itself
    /// whether one is worth offering a choice over.
    public static func read(from url: URL) async -> [AudioTrackDescription] {
        await read(asset: AVURLAsset(url: url), url: url)
    }

    /// Shares an asset a caller already loaded, so listing tracks costs no second `AVURLAsset`.
    public static func read(asset: AVAsset, url: URL) async -> [AudioTrackDescription] {
        do {
            let tracks = try await asset.loadTracks(withMediaType: .audio)

            var descriptions: [AudioTrackDescription] = []

            for track in tracks {
                descriptions.append(await description(of: track))
            }

            return descriptions

        } catch {
            Log.error("Failed to read audio tracks for \(url.lastPathComponent)", error)
            return []
        }
    }

    /// Reads one track, filling in whatever it can.
    ///
    /// Every field but the identifier is best-effort: a track whose format description will not
    /// load is still selectable and still needs a row in the picker.
    private static func description(of track: AVAssetTrack) async -> AudioTrackDescription {
        let language = try? await track.load(.languageCode)
        let formatDescriptions = (try? await track.load(.formatDescriptions)) ?? []

        var codec: String?
        var channelCount: Int?
        var sampleRate: Double?

        if let description = formatDescriptions.first {
            // A four-character code pads to four with spaces, so AAC arrives as `"aac "` — trailing
            // whitespace in a value that reaches a menu row. Video subtypes happen to fill all four
            // (`avc1`, `hvc1`), which is why `fourCCString` itself does not do this.
            codec = VideoTrackReader.fourCCString(CMFormatDescriptionGetMediaSubType(description))?
                .trimmingCharacters(in: .whitespaces)

            if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee {
                channelCount = Int(asbd.mChannelsPerFrame)
                sampleRate = asbd.mSampleRate
            }
        }

        return AudioTrackDescription(
            id: AudioTrackDescription.ID(persistentTrackID: track.trackID),
            name: await name(of: track),
            language: language ?? nil,
            codec: codec,
            channelCount: channelCount,
            sampleRate: sampleRate
        )
    }

    /// The track's own title, from its common metadata.
    ///
    /// Verified against a real file rather than assumed: a QuickTime track name written as
    /// `udta/name` reaches `commonMetadata` as `.commonKeyTitle`, which is why this reads the
    /// common keyspace rather than reaching for a QuickTime-specific identifier.
    private static func name(of track: AVAssetTrack) async -> String? {
        guard let metadata = try? await track.load(.commonMetadata) else { return nil }

        for item in metadata where item.commonKey == .commonKeyTitle {
            if let value = try? await item.load(.stringValue), value.isEmpty == false {
                return value
            }
        }

        return nil
    }
}
