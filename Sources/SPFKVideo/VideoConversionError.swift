// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import Foundation

/// Why ``VideoFormatConverter`` left no output.
public enum VideoConversionError: LocalizedError {
    /// The output is the input, or the file a render of it stands in for.
    case outputReplacesInput(URL)

    /// The output exists and the conflict scheme is `.error`.
    case outputExists(URL)

    /// AVFoundation cannot open the input: Matroska, WebM, Windows Media and MXF are the usual cases.
    case unreadable(URL, underlying: any Error)

    /// The input is copy-protected (FairPlay).
    case protectedContent(URL)

    /// The preset cannot be applied to this input.
    case presetUnavailable(VideoConversionPreset)

    /// The preset does not write this container for this input. `alternatives` are the extensions it does write.
    case unsupportedContainer(VideoConversionContainer, preset: VideoConversionPreset, alternatives: [String])

    case exportFailed(URL, underlying: any Error)

    /// The export completed without audio or video the input had.
    case tracksLost(URL, missing: [String])

    public var errorDescription: String? {
        switch self {
        case let .outputReplacesInput(url):
            "Converting \(url.lastPathComponent) would replace it. Choose a different folder or format."

        case let .outputExists(url):
            "\(url.lastPathComponent) already exists."

        case let .unreadable(url, _):
            "This Mac can't open .\(url.pathExtension) videos."

        case .protectedContent:
            "The video is copy-protected."

        case let .presetUnavailable(preset):
            "\(preset.title) can't be used for this video."

        case let .unsupportedContainer(container, preset, alternatives):
            alternatives.isEmpty
                ? "\(preset.title) can't be written to .\(container.pathExtension)."
                : "\(preset.title) can't be written to .\(container.pathExtension) - try "
                + alternatives.map { ".\($0)" }.joined(separator: ", ")

        case let .exportFailed(_, underlying):
            "The video could not be converted: \(underlying.localizedDescription)"

        case let .tracksLost(_, missing):
            "Converting would have dropped its \(missing.joined(separator: " and "))."
        }
    }
}
