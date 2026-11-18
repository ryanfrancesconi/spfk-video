// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import CoreGraphics
import Foundation
import SPFKTesting
import Testing

@testable import SPFKVideo

/// What a batch of re-encodes keeps per file, at the width Convert Files runs them.
@Suite(.tags(.slow, .conversion))
struct VideoFormatConverterMemoryTests {
    @Test func reEncodingHoldsNoMemoryPerFile() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(component: "VideoFormatConverterMemoryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let input = try await VideoTestFixture.makeTestVideo(duration: 5, size: CGSize(width: 1920, height: 1080))
        defer { try? FileManager.default.removeItem(at: input) }

        let grown = try await retainedMemoryMB(warmUp: 4, measured: 16, width: VideoFormatConverter.preferredBatchSize) { index in
            let output = folder.appending(component: "out-\(index).mov", directoryHint: .notDirectory)

            _ = try await VideoFormatConverter(source: VideoConversionSource(
                input: input,
                output: output,
                options: VideoConversionOptions(preset: .hevc1080p, container: .mov)
            )).convert()

            try FileManager.default.removeItem(at: output)
        }

        #expect(grown < 100, "grew \(Int(grown)) MB over 16 files")
    }
}
