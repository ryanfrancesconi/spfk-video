// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import AVFoundation
import CoreMedia
import Foundation
import SPFKBase

/// AVFoundation-based reader for video-technical and QuickTime user-data properties.
///
/// Best-effort: a failure on either read leaves that half of the result `nil` rather than
/// failing the whole call, so a corrupt video track doesn't also suppress an otherwise
/// readable QuickTime user-data block (and vice versa).
public enum VideoTrackReader {
    /// Reads both the video track's technical properties and its QuickTime user-data,
    /// sharing a single `AVURLAsset` between the two reads.
    public static func read(
        from url: URL
    ) async -> (videoTrack: VideoTrackProperties?, quickTimeUserData: QuickTimeUserData?) {
        let asset = AVURLAsset(url: url)
        let videoTrack = await readVideoTrack(asset: asset, url: url)
        let quickTimeUserData = await readQuickTimeUserData(asset: asset, url: url)
        return (videoTrack, quickTimeUserData)
    }

    private static func readVideoTrack(asset: AVURLAsset, url: URL) async -> VideoTrackProperties? {
        do {
            guard let track = try await asset.loadTracks(withMediaType: .video).first else { return nil }

            let naturalSize = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let nominalFrameRate = try await track.load(.nominalFrameRate)
            let formatDescriptions = try await track.load(.formatDescriptions)

            var codec: String?
            var pixelAspectRatio: Double?

            if let description = formatDescriptions.first {
                codec = fourCCString(CMFormatDescriptionGetMediaSubType(description))
                pixelAspectRatio = Self.pixelAspectRatio(from: description)
            }

            // Best-effort, separate from the rest of this read: resolved against
            // swift-timecode's standard-rate table from the exact rational frame duration
            // (minFrameDuration/format description/timecode track), not the lossy nominal
            // Float above. nil when the real rate doesn't match a known standard rate.
            let preciseFrameRate = try? await asset.timecodeFrameRate()

            return VideoTrackProperties(
                width: Int(naturalSize.width),
                height: Int(naturalSize.height),
                nominalFrameRate: nominalFrameRate,
                preciseFrameRate: preciseFrameRate,
                codec: codec,
                pixelAspectRatio: pixelAspectRatio,
                rotationDegrees: rotationDegrees(from: transform)
            )
        } catch {
            Log.error("Failed to read video track properties for \(url.lastPathComponent)", error)
            return nil
        }
    }

    /// Reads device/GPS/creation-date metadata, trying both QuickTime metadata keyspaces.
    ///
    /// Verified against real files, not assumed: a recent iPhone recording (iOS 26.5) stores
    /// this data under the modern `mdta` keyspace (`.quickTimeMetadata`) — `.quickTimeUserData`
    /// (the legacy `udta` keyspace this originally queried exclusively) returned zero items
    /// for it, confirmed via `asset.load(.availableMetadataFormats)` listing only
    /// `com.apple.quicktime.mdta`. Older devices/software may still only populate the legacy
    /// keyspace, so both are queried and merged; `.quickTimeMetadata` takes priority as the
    /// modern/common case, with `.quickTimeUserData` filling in only fields still `nil`.
    private static func readQuickTimeUserData(asset: AVAsset, url: URL) async -> QuickTimeUserData? {
        var userData = QuickTimeUserData()

        do {
            for item in try await asset.loadMetadata(for: .quickTimeMetadata) {
                switch item.identifier {
                case .quickTimeMetadataMake:
                    userData.deviceMake = try await item.load(.stringValue)
                case .quickTimeMetadataModel:
                    userData.deviceModel = try await item.load(.stringValue)
                case .quickTimeMetadataSoftware:
                    userData.deviceSoftware = try await item.load(.stringValue)
                case .quickTimeMetadataCreationDate:
                    userData.creationDate = try await item.load(.dateValue)
                case .quickTimeMetadataLocationISO6709:
                    if let iso6709 = try await item.load(.stringValue) {
                        (userData.latitude, userData.longitude) = parseISO6709(iso6709)
                    }
                default:
                    continue
                }
            }
        } catch {
            Log.error("Failed to read QuickTime mdta metadata for \(url.lastPathComponent)", error)
        }

        do {
            for item in try await asset.loadMetadata(for: .quickTimeUserData) {
                switch item.identifier {
                case .quickTimeUserDataMake:
                    if userData.deviceMake == nil { userData.deviceMake = try await item.load(.stringValue) }
                case .quickTimeUserDataModel:
                    if userData.deviceModel == nil { userData.deviceModel = try await item.load(.stringValue) }
                case .quickTimeUserDataSoftware:
                    if userData.deviceSoftware == nil { userData.deviceSoftware = try await item.load(.stringValue) }
                case .quickTimeUserDataCreationDate:
                    if userData.creationDate == nil { userData.creationDate = try await item.load(.dateValue) }
                case .quickTimeUserDataLocationISO6709:
                    if userData.latitude == nil, let iso6709 = try await item.load(.stringValue) {
                        (userData.latitude, userData.longitude) = parseISO6709(iso6709)
                    }
                default:
                    continue
                }
            }
        } catch {
            Log.error("Failed to read QuickTime udta user data for \(url.lastPathComponent)", error)
        }

        return userData == QuickTimeUserData() ? nil : userData
    }

    /// Converts a `CMFormatDescription`'s four-character-code media subtype into its
    /// standard ASCII string form (e.g. "avc1", "hvc1").
    ///
    /// Internal, not private: exposed to `@testable import` so `parseISO6709`/
    /// `rotationDegrees(from:)`/this can be unit tested directly as pure functions,
    /// without needing a real video file (unlike `read(from:)` itself).
    static func fourCCString(_ fourCC: FourCharCode) -> String? {
        let value = fourCC
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ]

        guard bytes.allSatisfy({ (0x20...0x7E).contains($0) }) else { return nil }

        return String(bytes: bytes, encoding: .ascii)
    }

    /// Reads pixel aspect ratio from a format description's `PixelAspectRatio` extension
    /// dictionary (horizontal/vertical spacing). `nil` (implying 1:1 square pixels) when
    /// the extension is absent, which is the common case for standard video.
    static func pixelAspectRatio(from description: CMFormatDescription) -> Double? {
        guard
            let extensions = CMFormatDescriptionGetExtension(
                description,
                extensionKey: kCMFormatDescriptionExtension_PixelAspectRatio
            ) as? [CFString: Any],
            let horizontal = extensions[kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing] as? NSNumber,
            let vertical = extensions[kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing] as? NSNumber,
            vertical.doubleValue > 0
        else {
            return nil
        }

        return horizontal.doubleValue / vertical.doubleValue
    }

    /// Normalizes an `AVAssetTrack.preferredTransform` rotation to the nearest multiple of
    /// 90 degrees (0, 90, 180, or 270) — what a portrait phone-shot video needs applied to
    /// preview right-side-up.
    static func rotationDegrees(from transform: CGAffineTransform) -> Int {
        let radians = atan2(Double(transform.b), Double(transform.a))
        var degrees = Int((radians * 180 / .pi).rounded())
        degrees = ((degrees % 360) + 360) % 360
        return (Int((Double(degrees) / 90).rounded()) * 90) % 360
    }

    /// Parses an ISO 6709 location string (e.g. "+37.3349-122.0090+000.000/") into
    /// decimal-degree latitude/longitude. Format: signed latitude immediately followed by
    /// signed longitude, no separator between them, optional altitude, terminated by "/".
    static func parseISO6709(_ string: String) -> (latitude: Double?, longitude: Double?) {
        // Match the leading two signed decimal numbers (latitude, then longitude).
        let pattern = #"^([+-]\d+(?:\.\d+)?)([+-]\d+(?:\.\d+)?)"#

        guard let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)),
            match.numberOfRanges == 3,
            let latRange = Range(match.range(at: 1), in: string),
            let lonRange = Range(match.range(at: 2), in: string),
            let latitude = Double(string[latRange]),
            let longitude = Double(string[lonRange])
        else {
            return (nil, nil)
        }

        return (latitude, longitude)
    }
}
