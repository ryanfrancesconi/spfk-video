// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import AVFoundation
import CoreMedia
import Foundation

/// One audio track's stream format and length, for a caller that needs the numbers rather than a
/// picker row.
///
/// The counterpart to ``AudioTrackDescription``, which names a track for a menu and carries no
/// length. Separate because the two are read for unrelated reasons and a picker should not pay for
/// a duration load per track.
public struct AudioTrackFormat: Hashable, Sendable {
    public let channelCount: AVAudioChannelCount
    public let sampleRate: Double

    /// `nil` for a lossy codec, which declares none.
    public let bitsPerChannel: Int?

    public let frameCount: AVAudioFramePosition
    public let duration: TimeInterval

    public init(
        channelCount: AVAudioChannelCount,
        sampleRate: Double,
        bitsPerChannel: Int?,
        frameCount: AVAudioFramePosition,
        duration: TimeInterval
    ) {
        self.channelCount = channelCount
        self.sampleRate = sampleRate
        self.bitsPerChannel = bitsPerChannel
        self.frameCount = frameCount
        self.duration = duration
    }
}

extension AudioTrackReader {
    /// The first audio track's format and length, through `AVAsset`.
    ///
    /// For the containers `AVAudioFile` refuses: it is ExtAudioFile underneath, a stack that
    /// MediaToolbox format readers do not serve, so a file that plays perfectly through `AVAsset`
    /// can still fail to open there — MXF does, before and after ``ProVideoFormats/register()``.
    ///
    /// - Returns: `nil` when the file has no audio track, or none whose format description loads.
    public static func format(of url: URL) async -> AudioTrackFormat? {
        let tracks = (try? await AVURLAsset(url: url).loadTracks(withMediaType: .audio)) ?? []

        guard let track = tracks.first else { return nil }

        return await format(of: track)
    }

    /// Shares a track a caller already holds.
    public static func format(of track: AVAssetTrack) async -> AudioTrackFormat? {
        let descriptions = (try? await track.load(.formatDescriptions)) ?? []

        guard
            let description = descriptions.first,
            let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
            asbd.mSampleRate > 0
        else {
            return nil
        }

        let seconds = CMTimeGetSeconds((try? await track.load(.timeRange).duration) ?? .zero)
        let duration = seconds.isFinite && seconds > 0 ? seconds : 0

        return AudioTrackFormat(
            channelCount: AVAudioChannelCount(asbd.mChannelsPerFrame),
            sampleRate: asbd.mSampleRate,
            bitsPerChannel: asbd.mBitsPerChannel > 0 ? Int(asbd.mBitsPerChannel) : nil,
            frameCount: AVAudioFramePosition(duration * asbd.mSampleRate),
            duration: duration
        )
    }
}
