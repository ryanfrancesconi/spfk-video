// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import AVFoundation
import Foundation
import Testing

@testable import SPFKVideo

/// The refusal a user actually reads when a container cannot be written.
@Suite
struct VideoEditErrorTests {
    /// Naming what would work is the whole point of carrying the list: the alternatives come from
    /// the export session, so the message tracks what this build and this source can write rather
    /// than a list somebody has to maintain.
    @Test func theRefusalOffersWhatTheSessionWouldAccept() throws {
        let error = VideoEditError.unsupportedOutputContainer("ts", alternatives: ["mov", "mp4"])
        let message = try #require(error.errorDescription)

        #expect(message.contains(".ts"))
        #expect(message.contains(".mov"))
        #expect(message.contains(".mp4"))
    }

    /// The extension check runs before the session exists, so there is nothing to offer there. The
    /// message has to stay a plain refusal rather than an empty "try ".
    @Test func theRefusalStaysPlainWhenNothingIsKnown() throws {
        let error = VideoEditError.unsupportedOutputContainer("xyz", alternatives: [])
        let message = try #require(error.errorDescription)

        #expect(message.contains(".xyz"))
        #expect(!message.contains("try"))
    }

    /// The mapping the message is built from -- an `AVFileType` is a UTI, and printing one at the
    /// user would be unreadable.
    @Test func fileTypesAreNamedByTheirExtension() {
        let extensions = VideoEditRenderer.pathExtensions(for: [.mov, .mp4, .m4a])

        #expect(extensions == ["m4a", "mov", "mp4"])
    }
}
