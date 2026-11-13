// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import Foundation
import os
import SPFKTesting
import Testing

@testable import SPFKVideo

/// As many timecode reads at once as the cooperative pool has threads must all finish. A read that
/// blocks the thread it runs on leaves nothing to run the rest, and the whole process stops.
@Suite(.serialized)
final class VideoTrackReaderConcurrencyTests {
    @Test func timecodeReadsFillingThePoolAllFinish() async throws {
        let url = TestBundleResources.shared.sample_timecode_offset_mov
        let width = ProcessInfo.processInfo.activeProcessorCount
        let watchdog = DeadlockWatchdog(seconds: 30, message: "\(width) concurrent timecode reads never finished")

        let starts = await withTaskGroup(of: String?.self) { group in
            for _ in 0 ..< width {
                group.addTask { await VideoTrackReader.read(from: url).videoTrack?.startTimecodeString }
            }
            return await group.reduce(into: [String?]()) { $0.append($1) }
        }

        watchdog.cancel()

        #expect(starts == Array(repeating: "01:00:00;01", count: width))
    }

    @Test func theWatchdogsSampleHoldsEveryThreadsStack() throws {
        let url = try #require(DeadlockWatchdog.sampleProcess())
        defer { try? FileManager.default.removeItem(at: url) }

        let sample = try String(contentsOf: url, encoding: .utf8)
        #expect(sample.contains("Call graph:"))
        #expect(sample.contains("theWatchdogsSampleHoldsEveryThreadsStack"))
    }
}

/// Stops the process when not cancelled in time, after sampling every thread's stack to a file it
/// names. A plain `Thread`, because a deadlocked cooperative pool cannot run the task a Swift Testing
/// time limit would need.
final class DeadlockWatchdog: Sendable {
    private let isCancelled = OSAllocatedUnfairLock(initialState: false)

    init(seconds: TimeInterval, message: String) {
        let isCancelled = isCancelled

        Thread.detachNewThread {
            Thread.sleep(forTimeInterval: seconds)
            guard !isCancelled.withLock({ $0 }) else { return }

            let sample = Self.sampleProcess().map(\.path) ?? "none, sample failed"
            fatalError("Deadlock: \(message). Stacks: \(sample)")
        }
    }

    /// `/usr/bin/sample` of this process for a second, as `xcb.sh` takes of a stalled run, into a file
    /// under the temporary directory; nil when it wrote none.
    static func sampleProcess() -> URL? {
        let directory = FileManager.default.temporaryDirectory.appending(component: "stalls", directoryHint: .isDirectory)
        let url = directory.appending(component: "xctest-watchdog-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString).txt")

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
            process.arguments = [String(ProcessInfo.processInfo.processIdentifier), "1", "-file", url.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
        } catch {
            print("DeadlockWatchdog: sample failed: \(error)")
            return nil
        }

        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func cancel() {
        isCancelled.withLock { $0 = true }
    }
}
