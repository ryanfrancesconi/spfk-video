// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import AVFoundation
import Foundation
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKVideo

@Suite
struct VideoExportProgressTests {
    private actor Fractions {
        var values: [Double] = []
        var lateReports = 0
        private var isClosed = false

        func append(_ value: Double) {
            if isClosed { lateReports += 1 }
            values.append(value)
        }

        func close() {
            isClosed = true
        }
    }

    private static func temporaryURL(_ pathExtension: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(pathExtension)
    }

    @Test func renderReportsFractionsAndStopsWhenItReturns() async throws {
        let output = Self.temporaryURL("mov")
        defer { try? FileManager.default.removeItem(at: output) }

        let fractions = Fractions()

        let renderer = VideoEditRenderer(
            sourceURL: TestBundleResources.shared.orientation_pattern_mov,
            trim: TrimDescription(),
            orientation: .right,
            outputURL: output
        )

        try await renderer.render { await fractions.append($0) }
        await fractions.close()

        // Long enough for a report that outlived the render to land.
        try await Task.sleep(for: .milliseconds(400))

        let values = await fractions.values
        #expect(values.isNotEmpty)
        #expect(values.allSatisfy { (0 ... 1).contains($0) })
        #expect(await fractions.lateReports == 0)
    }

    @Test func cancellingARenderMidExportLeavesNoOutput() async throws {
        let source = try await VideoTestFixture.makeTestVideo(duration: 10, size: CGSize(width: 1920, height: 1080))
        defer { try? FileManager.default.removeItem(at: source) }

        let output = Self.temporaryURL("mov")
        defer { try? FileManager.default.removeItem(at: output) }

        let renderer = VideoEditRenderer(
            sourceURL: source,
            trim: TrimDescription(inPoint: 1, outPoint: 9),
            orientation: .right,
            outputURL: output
        )

        let started = AsyncStream<Void>.makeStream()

        let task = Task {
            try await renderer.render { _ in started.continuation.yield() }
        }

        // The first report arrives as the export starts.
        for await _ in started.stream { break }
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("render returned instead of throwing")
        } catch let error as VideoEditError {
            guard case .cancelled = error else {
                Issue.record("expected .cancelled, got \(error)")
                return
            }
        }

        #expect(!FileManager.default.fileExists(atPath: output.path))
    }

    @Test(.tags(.conversion))
    func convertReportsFractions() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(component: "VideoExportProgressTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let source = VideoConversionSource(
            input: TestBundleResources.shared.orientation_pattern_mov,
            output: folder.appending(component: "out.mov", directoryHint: .notDirectory),
            options: VideoConversionOptions(preset: .passthrough, container: .mov)
        )

        let fractions = Fractions()

        _ = try await VideoFormatConverter(source: source).convert { await fractions.append($0) }

        let values = await fractions.values
        #expect(values.isNotEmpty)
        #expect(values.allSatisfy { (0 ... 1).contains($0) })
    }
}
