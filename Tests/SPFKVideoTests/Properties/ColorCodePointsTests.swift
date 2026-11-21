// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import CoreMedia
import CoreVideo
import Foundation
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKVideo

@Suite
struct ColorCodePointsTests {
    @Test func anHLGMovieReadsAsRec2020HLG() async throws {
        #expect(try await ColorCodePoints.read(fromMovieAt: TestBundleResources.shared.hlg_pattern_mov) == .rec2020HLG)
    }

    @Test func anUntaggedMovieReadsAsNone() async throws {
        #expect(try await ColorCodePoints.read(fromMovieAt: TestBundleResources.shared.sample_mov) == nil)
    }

    /// A missing tag among present ones reads as unspecified, 2, rather than dropping the others.
    @Test func aMissingTagIsUnspecified() throws {
        var description: CMVideoFormatDescription?
        let extensions = [kCMFormatDescriptionExtension_ColorPrimaries: kCVImageBufferColorPrimaries_ITU_R_709_2] as CFDictionary
        CMVideoFormatDescriptionCreate(
            allocator: nil, codecType: kCMVideoCodecType_H264, width: 16, height: 16, extensions: extensions, formatDescriptionOut: &description
        )

        let format = try #require(description)
        let points = try #require(ColorCodePoints(formatDescription: format))
        #expect(points == ColorCodePoints(primaries: 1, transfer: 2, matrix: 2))
    }
}
