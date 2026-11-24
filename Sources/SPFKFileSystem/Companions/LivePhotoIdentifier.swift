// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import AVFoundation
import Foundation
import ImageIO
import SPFKBase
import UniformTypeIdentifiers

/// The content identifier a Live Photo's still and movie share: Apple's maker-note tag 17 in the
/// still, `com.apple.quicktime.content.identifier` in the movie.
public enum LivePhotoIdentifier {
    /// The identifier in an image's properties at index 0, when present and non-empty.
    public static func value(inImageProperties properties: [CFString: Any]) -> String? {
        let makerApple = properties[kCGImagePropertyMakerAppleDictionary] as? [String: Any]

        guard let identifier = makerApple?["17"] as? String, identifier.isNotEmpty else { return nil }

        return identifier
    }

    /// The still's identifier, from its properties alone. Nil for a RAW, which is never a Live Photo
    /// and whose ImageIO read can block on a decode.
    public static func still(at url: URL) -> String? {
        guard let type = UTType(filenameExtension: url.pathExtension),
              type.conforms(to: .image), !type.conforms(to: .rawImage),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }

        return value(inImageProperties: properties)
    }

    /// The movie's identifier, from its QuickTime metadata.
    public static func movie(at url: URL) async -> String? {
        let asset = AVURLAsset(url: url)

        do {
            let metadata = try await asset.loadMetadata(for: .quickTimeMetadata)
            let items = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .quickTimeMetadataContentIdentifier)

            for item in items {
                if let identifier = try await item.load(.stringValue), identifier.isNotEmpty {
                    return identifier
                }
            }
        } catch {
            Log.error("Couldn't read the metadata of \(url.lastPathComponent)", error)
        }

        return nil
    }
}

/// How ``FileCompanions`` reads Live Photo identifiers: from the files, or from a test's table.
public struct LivePhotoIdentifierReading: Sendable {
    public var still: @Sendable (URL) async -> String?
    public var movie: @Sendable (URL) async -> String?

    public init(still: @escaping @Sendable (URL) async -> String?, movie: @escaping @Sendable (URL) async -> String?) {
        self.still = still
        self.movie = movie
    }

    public static let system = LivePhotoIdentifierReading(
        still: { LivePhotoIdentifier.still(at: $0) },
        movie: { await LivePhotoIdentifier.movie(at: $0) }
    )
}
