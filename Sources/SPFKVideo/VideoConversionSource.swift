// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import Foundation
import SPFKBase
import SPFKFileSystem

/// One file's conversion: where ``VideoFormatConverter`` reads, where it writes, and how.
public struct VideoConversionSource: Sendable {
    public var input: URL
    public var output: URL
    public var options: VideoConversionOptions

    /// The file ``input`` stands in for, when it is a render of that file with pending edits applied.
    /// The output may not replace this file any more than it may replace ``input``.
    public var originalInput: URL?

    public var conflictScheme: FileConflictScheme

    /// Rendered into the output. `nil` or empty converts the whole file.
    public var trim: TrimDescription?

    /// Whether the input's Finder tags are copied to the output.
    public var copiesFinderTags: Bool

    public init(
        input: URL,
        output: URL,
        options: VideoConversionOptions,
        originalInput: URL? = nil,
        conflictScheme: FileConflictScheme = .overwrite,
        trim: TrimDescription? = nil,
        copiesFinderTags: Bool = true
    ) {
        self.input = input
        self.output = output
        self.options = options
        self.originalInput = originalInput
        self.conflictScheme = conflictScheme
        self.trim = trim
        self.copiesFinderTags = copiesFinderTags
    }
}
