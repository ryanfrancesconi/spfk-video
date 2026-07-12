// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import AVFoundation
import CoreGraphics
import Foundation

// MARK: - Synthetic video fixture for tests

enum VideoTestFixture {
    /// Generates a synthetic H.264 MP4 video at a temporary path.
    ///
    /// Each frame is a solid color that shifts across the duration, providing distinct
    /// per-second content without requiring a bundled binary asset. Call sites are
    /// responsible for cleaning up the returned URL with `FileManager.removeItem`.
    ///
    /// - Parameters:
    ///   - duration: Video duration in seconds.
    ///   - size: Output frame dimensions. Must be even values for H.264 encoding.
    static func makeTestVideo(
        duration: TimeInterval = 10.0,
        size: CGSize = CGSize(width: 640, height: 360)
    ) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mp4")

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        let pixelBufferAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: pixelBufferAttrs
        )

        writer.add(writerInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let frameRate = 30
        let timescale: CMTimeScale = 600
        let totalFrames = Int(duration) * frameRate

        for i in 0..<totalFrames {
            while !writerInput.isReadyForMoreMediaData {
                await Task.yield()
            }

            let presentationTime = CMTime(
                value: CMTimeValue(i * Int(timescale) / frameRate),
                timescale: timescale
            )

            guard let pool = adaptor.pixelBufferPool else { break }
            var pixelBuffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer) == kCVReturnSuccess,
                  let pixelBuffer
            else { break }

            fillPixelBuffer(pixelBuffer, frameIndex: i, totalFrames: totalFrames)
            adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
        }

        writerInput.markAsFinished()

        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }

        if let error = writer.error {
            throw error
        }

        return url
    }

    private static func fillPixelBuffer(
        _ buffer: CVPixelBuffer,
        frameIndex: Int,
        totalFrames: Int
    ) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return }

        let progress = CGFloat(frameIndex) / CGFloat(max(totalFrames - 1, 1))

        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return }

        context.setFillColor(red: progress, green: 0.3, blue: 1.0 - progress, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
    }
}
