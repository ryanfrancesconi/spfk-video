// Copyright Ryan Francesconi. All Rights Reserved.

import Foundation
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKVideo

/// A file where a store's directory goes would leave the store writing nowhere, so building it
/// has to fail.
@Suite(.tags(.file))
final class VideoFrameDataStoreDirectoryTests: BinTestCase {
    private func plantFile(named name: String) throws {
        let data = bin.appendingPathComponent("Data", isDirectory: true)
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        try Data("not a directory".utf8).write(to: data.appendingPathComponent(name))
    }

    @Test func aFileWhereTheStoreGoesFailsTheStore() throws {
        try plantFile(named: "Video")

        #expect(throws: (any Error).self) {
            _ = try VideoFrameDataStore(inDirectory: self.bin)
        }
    }
}
