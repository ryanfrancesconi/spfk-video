// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import AVFoundation
import Foundation
import SPFKBase

/// MXF header metadata, read via AVFoundation's `org.smpte.mxf` keyspace. Read-only, and `nil` for
/// any file that declares no MXF metadata.
///
/// The counterpart to ``QuickTimeUserData`` for the other container AVFoundation reads but no tag
/// store can open, and modeled the same way: named fields for what a reader would want, rather than
/// every identifier the keyspace can carry. The ones left out are opaque — UMIDs, generation and
/// product UUIDs, partition counts, the `*ID` twin of each colorimetry field — and describe the
/// file's identity to another tool, not to a person.
///
/// **Nothing here can be written.** MXF is absent from TagLib and from the XMP toolkit's handlers,
/// which is why `TagBacking` answers `.none` for it.
///
/// **Requires ``ProVideoFormats/register()``.** Without Apple's Pro Video Formats plug-ins the
/// asset does not open at all and every field is `nil`.
public struct MXFMetadata: Hashable, Sendable, Codable {
    // MARK: Identification — what wrote the file

    /// e.g. `Adobe Media Encoder`.
    public var applicationName: String?

    /// e.g. `Adobe Inc.`.
    public var applicationSupplier: String?

    /// e.g. `15.4.0`.
    public var applicationVersion: String?

    // MARK: Structure

    /// e.g. `OP1a`. Worth surfacing rather than treating as trivia: Apple's reader opens OP1a and
    /// was measured declining an OP-Atom file, so this names why a given MXF may not play.
    public var operationalPattern: String?

    /// e.g. `1.2`.
    public var mxfVersion: String?

    // MARK: Material

    /// The material package's own name — the closest thing MXF has to a title.
    public var packageName: String?

    public var materialCreationDate: Date?

    // MARK: Essence

    public var spokenLanguage: String?
    public var signalStandard: String?
    public var colorPrimaries: String?
    public var transferCharacteristic: String?
    public var codingEquations: String?

    // MARK: Descriptive

    /// The Final Cut "Share" set, which Apple's reader surfaces under its own
    /// `com.apple.proapps.share.*` identifiers rather than SMPTE's.
    ///
    /// **These are tag vocabulary, not technical facts** — a file out of Final Cut or Compressor can
    /// carry a creator and a description where the SMPTE keyspace carries none. Reading them does
    /// not make MXF writable.
    public var creator: String?
    public var contentDescription: String?
    public var copyright: String?
    public var genre: String?
    public var show: String?
    public var episodeID: String?
    public var episodeNumber: String?
    public var tvNetwork: String?

    public init() {}
}

// MARK: - Display

public extension MXFMetadata {
    /// The fields in display order, grouped identification → structure → material → essence →
    /// descriptive.
    ///
    /// Labels live here rather than in the view package for the same reason
    /// ``VideoTechnicalProperties/Key/displayName`` does: `spfk-video-ui` has no localization
    /// bundle, and a user-facing label with no `localized()` to call cannot be translated.
    enum Field: String, CaseIterable, Sendable {
        case applicationSupplier
        case applicationName
        case applicationVersion
        case operationalPattern
        case mxfVersion
        case packageName
        case materialCreationDate
        case spokenLanguage
        case signalStandard
        case colorPrimaries
        case transferCharacteristic
        case codingEquations
        case creator
        case contentDescription
        case copyright
        case genre
        case show
        case episodeID
        case episodeNumber
        case tvNetwork

        /// - Note: a per-case `switch` with literal `localized(...)` calls rather than
        /// `localized(rawValue)` — extraction only picks up literal arguments at the call site.
        public var displayName: String {
            switch self {
            case .applicationSupplier: localized("Vendor")
            case .applicationName: localized("Application")
            case .applicationVersion: localized("Application Version")
            case .operationalPattern: localized("Operational Pattern")
            case .mxfVersion: localized("MXF Version")
            case .packageName: localized("Package Name")
            case .materialCreationDate: localized("Material Created")
            case .spokenLanguage: localized("Spoken Language")
            case .signalStandard: localized("Signal Standard")
            case .colorPrimaries: localized("Color Primaries")
            case .transferCharacteristic: localized("Transfer Characteristic")
            case .codingEquations: localized("Coding Equations")
            case .creator: localized("Creator")
            case .contentDescription: localized("Description")
            case .copyright: localized("Copyright")
            case .genre: localized("Genre")
            case .show: localized("Show")
            case .episodeID: localized("Episode ID")
            case .episodeNumber: localized("Episode Number")
            case .tvNetwork: localized("Network")
            }
        }
    }

    /// The field's display string, or `nil` when this file states nothing for it — which is most of
    /// them for most files, since which identifiers an MXF carries is the writing application's
    /// choice.
    func value(for field: Field) -> String? {
        switch field {
        case .applicationSupplier: applicationSupplier
        case .applicationName: applicationName
        case .applicationVersion: applicationVersion
        case .operationalPattern: operationalPattern
        case .mxfVersion: mxfVersion
        case .packageName: packageName
        case .materialCreationDate: materialCreationDate.map(Self.dateFormatter.string(from:))
        case .spokenLanguage: spokenLanguage
        case .signalStandard: signalStandard
        case .colorPrimaries: colorPrimaries
        case .transferCharacteristic: transferCharacteristic
        case .codingEquations: codingEquations
        case .creator: creator
        case .contentDescription: contentDescription
        case .copyright: copyright
        case .genre: genre
        case .show: show
        case .episodeID: episodeID
        case .episodeNumber: episodeNumber
        case .tvNetwork: tvNetwork
        }
    }

    /// Matches `VideoTechnicalProperties`' capture-date style, so two date rows in the same panel
    /// read the same way.
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = .current
        return formatter
    }()
}

// MARK: - Reading

public extension MXFMetadata {
    /// AVFoundation's format name for the keyspace. No SDK constant exists for it — `mxf` appears
    /// nowhere in the AVFoundation, CoreMedia or MediaToolbox headers.
    static let metadataFormat = AVMetadataFormat(rawValue: "org.smpte.mxf")

    /// Reads the asset's MXF metadata, or `nil` when it declares none.
    ///
    /// - Note: an asset that is not MXF declares no such keyspace, so this costs one
    ///   `availableMetadataFormats` load and stops.
    static func read(from asset: AVAsset, url: URL) async -> MXFMetadata? {
        let formats = (try? await asset.load(.availableMetadataFormats)) ?? []

        guard formats.contains(metadataFormat) else { return nil }

        var metadata = MXFMetadata()

        do {
            for item in try await asset.loadMetadata(for: metadataFormat) {
                guard let key = fieldKey(of: item) else { continue }

                switch key {
                case "org.smpte.mxf.identification.applicationname":
                    metadata.applicationName = try await item.load(.stringValue)
                case "org.smpte.mxf.identification.applicationsuppliername":
                    metadata.applicationSupplier = try await item.load(.stringValue)
                case "org.smpte.mxf.identification.applicationversionstring":
                    metadata.applicationVersion = try await item.load(.stringValue)
                case "org.smpte.mxf.preface.operationalPattern":
                    metadata.operationalPattern = try await item.load(.stringValue)
                case "org.smpte.mxf.file.mxfVersion":
                    metadata.mxfVersion = try await item.load(.stringValue)
                case "org.smpte.mxf.package.material.packagename":
                    metadata.packageName = try await item.load(.stringValue)
                case "org.smpte.mxf.package.material.creationtime":
                    metadata.materialCreationDate = try await timestamp(from: item.load(.stringValue))
                case "org.smpte.mxf.audio.spokenLanguage":
                    metadata.spokenLanguage = try await item.load(.stringValue)
                case "org.smpte.mxf.video.signalStandard":
                    metadata.signalStandard = try await item.load(.stringValue)
                case "org.smpte.mxf.video.colorPrimaries":
                    metadata.colorPrimaries = try await item.load(.stringValue)
                case "org.smpte.mxf.video.transferCharacteristic":
                    metadata.transferCharacteristic = try await item.load(.stringValue)
                case "org.smpte.mxf.video.codingEquations":
                    metadata.codingEquations = try await item.load(.stringValue)
                case "com.apple.proapps.share.creator":
                    metadata.creator = try await item.load(.stringValue)
                case "com.apple.proapps.share.description":
                    metadata.contentDescription = try await item.load(.stringValue)
                case "com.apple.proapps.share.copyright":
                    metadata.copyright = try await item.load(.stringValue)
                case "com.apple.proapps.share.genre":
                    metadata.genre = try await item.load(.stringValue)
                case "com.apple.proapps.share.show":
                    metadata.show = try await item.load(.stringValue)
                case "com.apple.proapps.share.episodeID":
                    metadata.episodeID = try await item.load(.stringValue)
                case "com.apple.proapps.share.episodeNumber":
                    metadata.episodeNumber = try await item.load(.stringValue)
                case "com.apple.proapps.share.tvNetwork":
                    metadata.tvNetwork = try await item.load(.stringValue)
                default:
                    continue
                }
            }
        } catch {
            Log.error("Failed to read MXF metadata for \(url.lastPathComponent)", error)
        }

        return metadata == MXFMetadata() ? nil : metadata
    }

    /// Shares an asset a caller already loaded.
    static func read(from url: URL) async -> MXFMetadata? {
        await read(from: AVURLAsset(url: url), url: url)
    }

    /// A cheap pre-check so a selection change does not open an asset for every file just to find
    /// no MXF keyspace. **Not the authority** — ``read(from:url:)`` answers from the keyspace the
    /// file declares, and returns `nil` for anything this would wave through.
    ///
    /// Here rather than in each product so the two cannot drift, which is how format tests usually
    /// diverge.
    static func isMXF(url: URL) -> Bool {
        url.pathExtension.caseInsensitiveCompare("mxf") == .orderedSame
    }

    /// Parses one of the keyspace's timestamps.
    ///
    /// **Never `item.load(.dateValue)` here.** These items arrive as
    /// `com.apple.metadata.datatype.UTF-8` holding `2021-07-30 04:06:08 +0000`, and `dateValue`
    /// does not decline a string it cannot read — it returns a *fabricated* date. Measured: that
    /// exact value came back as `12198-05-07`, which reached the panel as "May 7, 12198".
    ///
    /// Not ISO 8601 either, which rejects the space separator outright.
    static func timestamp(from string: String?) -> Date? {
        guard let string else { return nil }

        return timestampParser.date(from: string)
    }

    /// Fixed format and POSIX locale: this parses a machine-written value, so it must not follow
    /// the reader's locale.
    private static let timestampParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    /// The identifier with AVFoundation's keyspace prefix removed: items arrive as
    /// `MTmi/org.smpte.mxf.identification.applicationname`, where `MTmi` names the keyspace and not
    /// the field. Split rather than trimmed, so a change of prefix does not silently match nothing.
    internal static func fieldKey(of item: AVMetadataItem) -> String? {
        guard let raw = item.identifier?.rawValue else { return nil }
        guard let separator = raw.firstIndex(of: "/") else { return raw }

        return String(raw[raw.index(after: separator)...])
    }
}
