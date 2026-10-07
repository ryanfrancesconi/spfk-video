// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import AVFoundation
import CoreMedia
import Foundation
import SwiftTimecode

extension AVAsset {
    /// The first timecode track's first sample, at `frameRate`, or at the rate the asset states
    /// when nil. Nil when the asset has no timecode track.
    ///
    /// The sample read blocks, so it runs on a thread of its own: on the cooperative pool, as many
    /// concurrent reads as the pool has threads leave nothing to finish them, and the process stops.
    func startTimecodeReadingOffPool(at frameRate: TimecodeFrameRate?) async throws -> Timecode? {
        let rate: TimecodeFrameRate = if let frameRate { frameRate } else { try await timecodeFrameRate() }

        // Not Sendable, but immutable once loaded, and the other thread only reads them.
        nonisolated(unsafe) let asset = self

        for track in try await loadTracks(withMediaType: .timecode) {
            nonisolated(unsafe) let track = track

            if let sample = try await Self.onOwnThread({ try TimecodeSample.first(in: track, of: asset) }) {
                return try sample.timecode(at: rate)
            }
        }

        return nil
    }

    private static func onOwnThread<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            Thread.detachNewThread {
                continuation.resume(with: Result(catching: body))
            }
        }
    }
}

/// One `tmcd` media sample: a big-endian frame count (`tmcd`), or big-endian hours, minutes,
/// seconds and frames in 16 bits each (`tc64`).
private enum TimecodeSample: Sendable {
    case frames(UInt32)
    case components(h: UInt16, m: UInt16, s: UInt16, f: UInt16)

    enum ReadError: Error {
        case cannotRead(Error?)
        case unsupportedFormat(FourCharCode)
    }

    /// Blocks until the track's first non-empty sample is read.
    static func first(in track: AVAssetTrack, of asset: AVAsset) throws -> TimecodeSample? {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)

        guard reader.startReading() else { throw ReadError.cannotRead(reader.error) }
        defer { reader.cancelReading() }

        while let buffer = output.copyNextSampleBuffer() {
            if let sample = try TimecodeSample(buffer) {
                return sample
            }
        }

        return nil
    }

    /// Nil for a buffer holding no sample data.
    init?(_ buffer: CMSampleBuffer) throws {
        guard let block = CMSampleBufferGetDataBuffer(buffer),
              let format = CMSampleBufferGetFormatDescription(buffer),
              buffer.totalSampleSize > 0
        else { return nil }

        func bigEndian<T: FixedWidthInteger>(_: T.Type) -> T? {
            var value: T = 0
            let status = withUnsafeMutableBytes(of: &value) { bytes in
                bytes.baseAddress.map {
                    CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: MemoryLayout<T>.size, destination: $0)
                } ?? kCMBlockBufferBadPointerParameterErr
            }
            return status == kCMBlockBufferNoErr ? T(bigEndian: value) : nil
        }

        switch format.mediaSubType {
        case .timeCode32:
            guard let frames = bigEndian(UInt32.self) else { return nil }
            self = .frames(frames)

        case .timeCode64:
            guard let raw = bigEndian(UInt64.self) else { return nil }
            self = .components(
                h: UInt16(truncatingIfNeeded: raw >> 48), m: UInt16(truncatingIfNeeded: raw >> 32),
                s: UInt16(truncatingIfNeeded: raw >> 16), f: UInt16(truncatingIfNeeded: raw)
            )

        default:
            throw ReadError.unsupportedFormat(format.mediaSubType.rawValue)
        }
    }

    func timecode(at rate: TimecodeFrameRate) throws -> Timecode {
        switch self {
        case let .frames(count):
            try Timecode(.frames(Int(count)), at: rate)
        case let .components(h, m, s, f):
            try Timecode(.components(h: Int(h), m: Int(m), s: Int(s), f: Int(f)), at: rate)
        }
    }
}
