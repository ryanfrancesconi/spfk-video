// Copyright Ryan Francesconi. All Rights Reserved.

import Foundation
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKVideo

/// A store whose directory is a file, or cannot be written, would fail every write silently, so
/// building it has to fail.
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

    @Test func aReadOnlyStoreDirectoryFailsTheStore() throws {
        let directory = bin.appendingPathComponent("Data/Video", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }

        #expect(throws: (any Error).self) {
            _ = try VideoFrameDataStore(inDirectory: self.bin)
        }
    }
}
