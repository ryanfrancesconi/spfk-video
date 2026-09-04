// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import Foundation

/// Errors thrown by ``VideoEditRenderer``.
public enum VideoEditError: Error {
    /// A file already exists at the requested output URL.
    case outputExists(URL)

    /// The output URL's path extension names a container the export session cannot write.
    /// MPEG-2 transport streams (`.ts`) are the common case — readable, but not writable.
    ///
    /// - Parameter alternatives: extensions this export *can* write, so the message can offer one
    ///   rather than only refusing. Read from the session itself, which is the only thing that
    ///   knows what this build and this source support; empty when no session exists yet.
    case unsupportedOutputContainer(String, alternatives: [String])

    /// The trim window does not describe a usable range of the source, either because the
    /// in-point falls at or past the end of the asset or because the asset has no duration.
    case trimOutOfRange(inPoint: TimeInterval, outPoint: TimeInterval, duration: TimeInterval)

    /// The export session could not be created for the source asset.
    case exportUnavailable(URL)

    /// The export ran but did not complete. Carries the session's own error when it had one.
    case exportFailed(URL, underlying: (any Error)?)

    /// The export was cancelled via ``VideoEditRenderer/cancel()`` or task cancellation.
    case cancelled

    /// The export completed but the result is missing audio or video the source had.
    ///
    /// A passthrough export drops a track the destination container cannot hold and still reports
    /// success, so this is the only signal that the render is not a faithful copy. Callers replace
    /// the user's original with the render, which makes the loss permanent and silent.
    case tracksLost(URL, missing: [String])
}

// MARK: - LocalizedError

extension VideoEditError: LocalizedError {
    /// Deliberately plain English rather than a localized string: this matches the messages
    /// `AudioEditRenderer` produces for the same class of failure, and keeps the user-facing
    /// wording with the UI layer, which is where the catalogs live.
    public var errorDescription: String? {
        switch self {
        case let .outputExists(url):
            "A file already exists at \(url.lastPathComponent)"

        case let .unsupportedOutputContainer(pathExtension, alternatives):
            alternatives.isEmpty
                ? "Video edits can't be written to .\(pathExtension) files"
                : "Video edits can't be written to .\(pathExtension) files — try "
                + alternatives.map { ".\($0)" }.joined(separator: ", ")

        case let .trimOutOfRange(inPoint, outPoint, duration):
            "Trim range \(inPoint)–\(outPoint)s is outside the file's \(duration)s duration"

        case let .exportUnavailable(url):
            "Unable to prepare an export for \(url.lastPathComponent)"

        case let .exportFailed(url, underlying):
            "Failed to render \(url.lastPathComponent)" + (underlying.map { ": \($0.localizedDescription)" } ?? "")

        case .cancelled:
            "The render was cancelled"

        case let .tracksLost(url, missing):
            "Rendering \(url.lastPathComponent) would have dropped its \(missing.joined(separator: " and ")) — the file was left unchanged"
        }
    }
}
