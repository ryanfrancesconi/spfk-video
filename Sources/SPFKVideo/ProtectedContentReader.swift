// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import AVFoundation
import Foundation

/// Whether a container's content is DRM-protected (FairPlay), asked of the asset alone.
///
/// The question a protected purchase makes necessary: it opens, reports playable, decodes its
/// metadata, and fails only once a player or a file reader holds it — so nothing short of asking
/// keeps it out of one. ``VideoTrackReader/read(from:)`` folds the same answer into its result for
/// the files it reads; this is for the audio containers of the same family it does not.
public enum ProtectedContentReader {
    /// `false` for a file AVFoundation cannot open at all, which is a different question with its
    /// own flag.
    public static func hasProtectedContent(url: URL) async -> Bool {
        (try? await AVURLAsset(url: url).load(.hasProtectedContent)) ?? false
    }
}
