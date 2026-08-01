// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import AVFoundation
import Foundation
import Testing

@testable import SPFKVideo

/// Locks down the finding Phase 2 of `shadowtag-video-edit-rendering.md` rests on: an
/// `AVAssetExportPresetPassthrough` trim preserves the QuickTime `mdta` fields
/// ``VideoTrackReader`` reads, so the video edit renderer needs no metadata-copy pass of its own
/// (unlike `AudioEditRenderer`, which must re-copy everything through `AudioFormatConverter`).
///
/// Worth a real asset round-trip rather than trusting the API: switching the preset away from
/// passthrough, or the export gaining a re-mux step, would silently strip a user's GPS and
/// capture date with nothing else to catch it.
@Suite
final class PassthroughMetadataProbeTests {
    @Test func passthroughTrimPreservesQuickTimeUserData() async throws {
        let source = try await Self.makeTaggedVideo()
        defer { try? FileManager.default.removeItem(at: source) }

        let before = try #require(await VideoTrackReader.read(from: source).quickTimeUserData)

        let trimmed = try await Self.passthroughTrim(source, from: 1, to: 3)
        defer { try? FileManager.default.removeItem(at: trimmed) }

        let after = try #require(await VideoTrackReader.read(from: trimmed).quickTimeUserData)

        #expect(after.deviceMake == before.deviceMake)
        #expect(after.deviceModel == before.deviceModel)
        #expect(after.deviceSoftware == before.deviceSoftware)
        #expect(after.creationDate == before.creationDate)
        #expect(after.latitude == before.latitude)
        #expect(after.longitude == before.longitude)
    }

    /// The trim itself is exact on both ends — the export writes an edit list rather than cutting
    /// the media at a keyframe, which is why no keyframe snapping is needed in the editor.
    @Test func passthroughTrimReportsTheRequestedDuration() async throws {
        let source = try await Self.makeTaggedVideo()
        defer { try? FileManager.default.removeItem(at: source) }

        let trimmed = try await Self.passthroughTrim(source, from: 1, to: 3)
        defer { try? FileManager.default.removeItem(at: trimmed) }

        let duration = try await AVURLAsset(url: trimmed).load(.duration).seconds
        #expect(abs(duration - 2.0) < 0.05, "expected ~2s, got \(duration)s")
    }

    // MARK: - Helpers

    private static func passthroughTrim(_ source: URL, from start: Double, to end: Double) async throws -> URL {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        let session = try #require(
            AVAssetExportSession(asset: AVURLAsset(url: source), presetName: AVAssetExportPresetPassthrough)
        )
        session.outputURL = output
        session.outputFileType = .mov
        session.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            end: CMTime(seconds: end, preferredTimescale: 600)
        )

        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { c.resume() }
        }

        guard session.status == .completed else {
            throw NSError(
                domain: "PassthroughMetadataProbeTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: session.error?.localizedDescription ?? "export failed"]
            )
        }
        return output
    }

    /// Writes a short H.264 `.mov` carrying the exact `mdta` identifiers `VideoTrackReader` queries.
    private static func makeTaggedVideo() async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        func item(_ identifier: AVMetadataIdentifier, _ value: any NSCopying & NSObjectProtocol) -> AVMetadataItem {
            let item = AVMutableMetadataItem()
            item.identifier = identifier
            item.value = value
            return item
        }

        let creationDate = try #require(ISO8601DateFormatter().date(from: "2019-06-01T12:34:56Z"))

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        writer.metadata = [
            item(.quickTimeMetadataMake, "SpikeCorp" as NSString),
            item(.quickTimeMetadataModel, "Model X" as NSString),
            item(.quickTimeMetadataSoftware, "SpikeOS 1.0" as NSString),
            item(.quickTimeMetadataCreationDate, creationDate as NSDate),
            item(.quickTimeMetadataLocationISO6709, "+45.5152-122.6784+015.000/" as NSString),
        ]

        let size = CGSize(width: 320, height: 240)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ])
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
            ]
        )

        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        for frame in 0 ..< 120 {
            while !input.isReadyForMoreMediaData { await Task.yield() }
            guard let pool = adaptor.pixelBufferPool else { break }
            var pixelBuffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer) == kCVReturnSuccess,
                  let pixelBuffer else { break }
            adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: CMTimeValue(frame * 20), timescale: 600))
        }

        input.markAsFinished()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            writer.finishWriting { c.resume() }
        }
        if let error = writer.error { throw error }
        return url
    }
}
