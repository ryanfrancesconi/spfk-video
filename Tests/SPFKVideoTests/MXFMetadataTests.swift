// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import AVFoundation
import Foundation
import SPFKTesting
import Testing

@testable import SPFKVideo

/// Only the fields the fixture actually carries are asserted. The rest of the mapping is pinned by
/// the identifier list in `MXFMetadata.read`, which comes from `AppleMXFImport.bundle`'s own symbols
/// -- there is no file here that produces them.
@Suite("MXFMetadata")
struct MXFMetadataTests {
    @Test("Reads identification and structure from an MXF", .enabled(if: ProVideoFormats.isAvailable))
    func readsFromMXF() async throws {
        let metadata = try #require(await MXFMetadata.read(from: TestBundleResources.shared.sample_mxf))

        // The fixture is muxed by ffmpeg, so these name ffmpeg rather than an NLE.
        #expect(metadata.applicationSupplier?.isEmpty == false)
        #expect(metadata.applicationName?.isEmpty == false)
        #expect(metadata.applicationVersion?.isEmpty == false)

        // OP1a is what Apple's reader opens; an OP-Atom file does not load at all.
        #expect(metadata.operationalPattern == "OP1a")
        #expect(metadata.mxfVersion?.isEmpty == false)

        // ffmpeg writes `-0001-11-30 07:52:58 +0000` here, which the parser refuses rather than
        // rendering as "Nov 30, -1". `MXF_Test.mxf` carries a real one; no fixture here does.
        #expect(metadata.materialCreationDate == nil)
    }

    /// **`AVMetadataItem.dateValue` fabricates a date for these items rather than declining them.**
    /// They arrive as `com.apple.metadata.datatype.UTF-8`, and the real value below came back from
    /// `dateValue` as `12198-05-07` — which reached the panel as "May 7, 12198". Parsing the string
    /// is what makes it right, so this pins the parse.
    @Test("Parses a keyspace timestamp without inventing one")
    func parsesTimestamp() throws {
        let date = try #require(MXFMetadata.timestamp(from: "2021-07-30 04:06:08 +0000"))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))

        let parts = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        #expect(parts.year == 2021)
        #expect(parts.month == 7)
        #expect(parts.day == 30)
        #expect(parts.hour == 4)
    }

    /// ISO 8601 rejects the space separator these use, so a caller reaching for the obvious
    /// formatter gets nothing. Anything unparseable is `nil` rather than a guess.
    @Test("Refuses a timestamp it cannot read")
    func refusesUnparseableTimestamp() {
        #expect(MXFMetadata.timestamp(from: nil) == nil)
        #expect(MXFMetadata.timestamp(from: "") == nil)
        #expect(MXFMetadata.timestamp(from: "2021-07-30T04:06:08Z") == nil)
        #expect(MXFMetadata.timestamp(from: "-0001-11-30 07:52:58 +0000") == nil)
    }

    /// The type describes MXF and says so by being absent, rather than by returning an empty struct
    /// a caller has to test field by field.
    @Test("Is nil for a container that declares no MXF keyspace")
    func isNilForNonMXF() async {
        #expect(await MXFMetadata.read(from: TestBundleResources.shared.sample_mov) == nil)
        #expect(await MXFMetadata.read(from: TestBundleResources.shared.sample_mkv) == nil)
    }

    /// The keyspace prefix names the keyspace, not the field, and dropping it is what makes every
    /// case in the switch match. A regression here reads as "MXF carries no metadata".
    @Test("Strips the keyspace prefix from an identifier")
    func stripsKeyspacePrefix() {
        let item = AVMutableMetadataItem()
        item.identifier = AVMetadataIdentifier(rawValue: "MTmi/org.smpte.mxf.identification.applicationname")

        #expect(MXFMetadata.fieldKey(of: item) == "org.smpte.mxf.identification.applicationname")
    }
}
