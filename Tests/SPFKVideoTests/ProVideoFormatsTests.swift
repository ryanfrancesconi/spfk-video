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

    /// The half that can be tested on a machine that *has* the plug-ins, and the one that matters
    /// most: an inverted condition would show the install prompt to every user who already
    /// installed them.
    @Test("Never prompts a user who already has the plug-ins", .enabled(if: ProVideoFormats.isAvailable))
    func doesNotPromptWhenAvailable() {
        #expect(ProVideoFormats.needsInstall(for: URL(fileURLWithPath: "/tmp/a.mxf")) == false)
        #expect(ProVideoFormats.needsInstall(for: URL(fileURLWithPath: "/tmp/a.MXF")) == false)
    }

    /// Meaningful in both directions, so it runs unconditionally: a container the plug-ins do not
    /// serve must never produce the prompt, whether or not they are installed. Matroska is the
    /// trap — also unreadable by `AVAudioFile`, and nothing Apple ships would fix it.
    @Test("Never prompts for a container the plug-ins do not serve")
    func doesNotPromptForOtherContainers() {
        #expect(ProVideoFormats.needsInstall(for: URL(fileURLWithPath: "/tmp/a.mov")) == false)
        #expect(ProVideoFormats.needsInstall(for: URL(fileURLWithPath: "/tmp/a.mkv")) == false)
        #expect(ProVideoFormats.needsInstall(for: URL(fileURLWithPath: "/tmp/a.wav")) == false)
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
