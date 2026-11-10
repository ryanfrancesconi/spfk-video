// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import AVFoundation
import Foundation
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKVideo

/// How ``VideoTrackReader`` describes a rotated or mirrored track. The files are rendered with
/// ``VideoEditRenderer``, which writes the matrix and decodes nothing.
@Suite
final class VideoTrackReaderOrientationTests {
    private let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(component: "VideoTrackReaderOrientationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    /// A left-right mirror reads as no turn and mirrored. `atan2` alone reads it as 180°.
    @Test func aMirroredFileReadsAsMirrored() async throws {
        let output = try await render(TestBundleResources.shared.orientation_pattern_mov, .upMirrored)
        let track = try #require(await VideoTrackReader.read(from: output).videoTrack)

        #expect(track.rotationDegrees == 0)
        #expect(track.isMirrored == true)
    }

    /// A mirrored quarter turn still swaps the displayed dimensions, which is what a quarter-turn
    /// check on ``VideoTrackProperties/rotationDegrees`` relies on.
    @Test(arguments: [OrientationEdit.rightMirrored, .leftMirrored])
    func aMirroredQuarterTurnReadsAsAQuarterTurn(edit: OrientationEdit) async throws {
        let output = try await render(TestBundleResources.shared.orientation_pattern_mov, edit)
        let track = try #require(await VideoTrackReader.read(from: output).videoTrack)

        #expect(track.rotationDegrees == 90 || track.rotationDegrees == 270)
        #expect(track.isMirrored == true)
        #expect(track.width == 160 && track.height == 120)
    }

    @Test func anUnmirroredFileReadsAsUnmirrored() async throws {
        let track = try #require(await VideoTrackReader.read(from: TestBundleResources.shared.orientation_pattern_mov).videoTrack)

        #expect(track.rotationDegrees == 0)
        #expect(track.isMirrored == false)
    }

    @Test func theMirroredRotationRowSaysMirrored() {
        let mirrored = VideoTechnicalProperties(videoTrack: VideoTrackProperties(rotationDegrees: 90, isMirrored: true), quickTimeUserData: nil)
        let plain = VideoTechnicalProperties(videoTrack: VideoTrackProperties(rotationDegrees: 90, isMirrored: false), quickTimeUserData: nil)

        #expect(mirrored.dictionary[.rotation] == "90° Mirrored")
        #expect(plain.dictionary[.rotation] == "90\u{00B0}")
    }

    @Test func aQuarterTurnOnARotatedSourceReadsAsAHalfTurn() async throws {
        let once = try await render(TestBundleResources.shared.orientation_pattern_mov, .right)
        let twice = try await render(once, .right)
        let track = try #require(await VideoTrackReader.read(from: twice).videoTrack)

        #expect(track.rotationDegrees == 180)
        #expect(track.isMirrored == false)
    }

    private func render(_ source: URL, _ edit: OrientationEdit) async throws -> URL {
        let output = folder.appending(component: "\(UUID().uuidString).\(source.pathExtension)", directoryHint: .notDirectory)

        return try await VideoEditRenderer(sourceURL: source, trim: TrimDescription(), orientation: edit, outputURL: output).render()
    }
}
