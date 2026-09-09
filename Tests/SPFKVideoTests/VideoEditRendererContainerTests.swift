// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import AVFoundation
import Foundation
import SPFKTesting
import Testing

@testable import SPFKVideo

/// Readable and writable are different capabilities, and MXF is the file that separates them.
@Suite("VideoEditRenderer container writability")
struct VideoEditRendererContainerTests {
    @Test("MXF is not writable, so a trim of it cannot be offered")
    func mxfIsNotWritable() {
        #expect(VideoEditRenderer.canWriteContainer(of: URL(fileURLWithPath: "/tmp/a.mxf")) == false)
        #expect(VideoEditRenderer.canWriteContainer(of: URL(fileURLWithPath: "/tmp/a.MXF")) == false)
    }

    @Test("The containers a trim does write stay writable")
    func othersRemainWritable() {
        #expect(VideoEditRenderer.canWriteContainer(of: URL(fileURLWithPath: "/tmp/a.mov")))
        #expect(VideoEditRenderer.canWriteContainer(of: URL(fileURLWithPath: "/tmp/a.mp4")))
        #expect(VideoEditRenderer.canWriteContainer(of: URL(fileURLWithPath: "/tmp/a.m4v")))
    }

    /// The claim the gate rests on, checked against AVFoundation rather than assumed: the export
    /// session offers no MXF output even for an MXF source it opened happily.
    @Test("AVFoundation offers no MXF output", .enabled(if: ProVideoFormats.isAvailable))
    func exportSessionOffersNoMXF() async throws {
        let asset = AVURLAsset(url: TestBundleResources.shared.sample_mxf)
        let session = try #require(
            AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough)
        )

        let types = session.supportedFileTypes
        #expect(types.contains(AVFileType(rawValue: "org.smpte.mxf")) == false)

        // Not an empty list — the session works, it simply cannot write this container.
        #expect(types.contains(.mov))
    }
}
