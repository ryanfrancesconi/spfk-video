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
}

/// Stops the process when not cancelled in time. A plain `Thread`, because a deadlocked
/// cooperative pool cannot run the task a Swift Testing time limit would need.
private final class DeadlockWatchdog: Sendable {
    private let isCancelled = OSAllocatedUnfairLock(initialState: false)

    init(seconds: TimeInterval, message: String) {
        let isCancelled = isCancelled

        Thread.detachNewThread {
            Thread.sleep(forTimeInterval: seconds)
            if !isCancelled.withLock({ $0 }) {
                fatalError("Deadlock: \(message)")
            }
        }
    }

    func cancel() {
        isCancelled.withLock { $0 = true }
    }
}
