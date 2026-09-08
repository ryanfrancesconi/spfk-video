// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import AVFoundation
import Foundation
import SPFKTesting
import Testing
import UniformTypeIdentifiers

@testable import SPFKVideo

@Suite("ProVideoFormats")
struct ProVideoFormatsTests {
    private static let mxfIdentifier = "org.smpte.mxf"

    /// Meaningful in both directions: without Apple's Pro Video Formats package installed, both
    /// sides are false.
    @Test("isAvailable matches what AVFoundation will actually open")
    func availabilityMatchesAudiovisualTypes() {
        ProVideoFormats.register()

        let readsMXF = AVURLAsset.audiovisualTypes().contains { $0.rawValue == Self.mxfIdentifier }
        #expect(ProVideoFormats.isAvailable == readsMXF)
    }

    @Test("register() is idempotent")
    func registerIsIdempotent() {
        ProVideoFormats.register()
        let first = ProVideoFormats.registeredContentTypes
        let typeCount = AVURLAsset.audiovisualTypes().count

        ProVideoFormats.register()

        #expect(ProVideoFormats.registeredContentTypes == first)
        #expect(AVURLAsset.audiovisualTypes().count == typeCount)
    }

    /// Registration adds a dynamic type alongside the declared one, and a dynamic type is useless
    /// for open-panel filtering.
    @Test("registeredContentTypes are declared types only")
    func registeredTypesAreDeclared() {
        ProVideoFormats.register()

        for type in ProVideoFormats.registeredContentTypes {
            #expect(!type.isDynamic, "\(type.identifier) is dynamic")
        }
    }

    @Test("Extracts a frame from an MXF", .enabled(if: ProVideoFormats.isAvailable))
    func extractsFrameFromMXF() async throws {
        let url = TestBundleResources.shared.sample_mxf
        let frames = try await VideoFrameExtractor.frames(from: url, at: [1.0])

        let frame = try #require(frames[1.0])
        #expect(frame.width == 160)
        #expect(frame.height == 120)
    }
}
