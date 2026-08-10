// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import Foundation

/// Drops a seek that cannot change the picture.
///
/// A drag emits several seeks per frame period, and an exact duplicate whenever the pointer pauses
/// without the drag ending; each one still costs a decode. A target is identified by the frame
/// containing it — `floor(time * fps)` — and an allowed target is passed back to the caller
/// unquantized, so a seek that survives lands exactly where it was asked to.
///
/// Only tracks what it was asked to seek to. Anything else that moves the picture — playback, a
/// reload — leaves it somewhere the filter cannot know about, and calls for ``reset()``.
@MainActor
public final class FrameSeekFilter {
    private var lastFrame: Int?

    public init() {}

    /// - Parameter fps: a nil or non-positive rate allows every target through.
    /// - Returns: whether `time` lands on a frame other than the one last allowed.
    public func allows(_ time: TimeInterval, fps: Double?) -> Bool {
        guard let fps, fps > 0 else { return true }

        let frame = Int((time * fps).rounded(.down))

        guard frame != lastFrame else { return false }

        lastFrame = frame
        return true
    }

    public func reset() {
        lastFrame = nil
    }
}
