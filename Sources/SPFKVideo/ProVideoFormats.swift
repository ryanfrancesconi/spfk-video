// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import AVFoundation
import Foundation
import UniformTypeIdentifiers

#if os(macOS)
    import MediaToolbox
    import VideoToolbox
#endif

/// Opts the process into macOS's professional video workflow plug-ins: the MXF container reader and
/// the pro codec family (DNxHD, AVC-Intra, IMX, DVCPRO HD).
///
/// Those plug-ins ship in Apple's separate "Pro Video Formats" package, so this is a runtime
/// capability rather than a property of the OS version — where they are absent both registrations
/// are no-ops and ``isAvailable`` is `false`. Registration also opts into any third-party
/// MediaExtension format readers the user has installed, which then run in this process.
public enum ProVideoFormats {
    /// Registers the professional format readers and video decoders. Idempotent, and safe from any
    /// thread.
    ///
    /// Call before the first `AVURLAsset`.
    public static func register() {
        _ = addedContentTypes
    }

    /// Whether registration produced a professional format reader.
    ///
    /// `org.smpte.mxf` conforms to `public.movie` whether or not anything can read it, so no UTI or
    /// extension check can answer this — only the probe below can.
    public static var isAvailable: Bool { !addedContentTypes.isEmpty }

    /// The content types registration added, for open-panel filtering and messaging.
    public static var registeredContentTypes: [UTType] { addedContentTypes }

    /// `static let` initialization runs once and is thread-safe, which is what makes ``register()``
    /// idempotent without a lock.
    private static let addedContentTypes: [UTType] = {
        #if os(macOS)
            let before = Set(AVURLAsset.audiovisualTypes())

            // Both or neither: with only the format readers, an MXF parses with a correct duration
            // and track list and then renders nothing, which reads exactly like a container bug.
            MTRegisterProfessionalVideoWorkflowFormatReaders()
            VTRegisterProfessionalVideoWorkflowVideoDecoders()

            // A dynamic type carries no declaration to filter an open panel on, and registration
            // adds one alongside the real type.
            return AVURLAsset.audiovisualTypes()
                .filter { !before.contains($0) }
                .compactMap { UTType($0.rawValue) }
                .filter { !$0.isDynamic }
        #else
            return []
        #endif
    }()
}
