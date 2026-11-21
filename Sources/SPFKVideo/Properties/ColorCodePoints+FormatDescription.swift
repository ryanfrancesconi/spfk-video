// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import SPFKBase

extension ColorCodePoints {
    /// The color `description` is tagged with. Nil when it carries none of the three tags.
    public init?(formatDescription description: CMFormatDescription) {
        func tag(_ key: CFString) -> CFString? {
            (CMFormatDescriptionGetExtension(description, extensionKey: key) as? String) as CFString?
        }

        let primaries = tag(kCMFormatDescriptionExtension_ColorPrimaries)
        let transfer = tag(kCMFormatDescriptionExtension_TransferFunction)
        let matrix = tag(kCMFormatDescriptionExtension_YCbCrMatrix)

        guard primaries != nil || transfer != nil || matrix != nil else { return nil }

        self.init(
            primaries: Int(CVColorPrimariesGetIntegerCodePointForString(primaries)),
            transfer: Int(CVTransferFunctionGetIntegerCodePointForString(transfer)),
            matrix: Int(CVYCbCrMatrixGetIntegerCodePointForString(matrix))
        )
    }

    /// The color of the first video track of the movie at `url`. Nil for an untagged track, or a
    /// file with no video track.
    public static func read(fromMovieAt url: URL) async throws -> ColorCodePoints? {
        guard let track = try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first,
              let description = try await track.load(.formatDescriptions).first
        else { return nil }

        return ColorCodePoints(formatDescription: description)
    }
}
