// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

#if os(macOS)
    import AppKit
    import Foundation

    /// A collection of Finder tags (color labels and/or custom text tags) attached to a file.
    ///
    /// **macOS only** (`#if os(macOS)`).
    ///
    /// Use ``init(url:)`` to read a file's current tags, or construct a group manually
    /// and write it with ``URL/set(finderTags:)``. The ``defaultTags`` static provides
    /// all 8 built-in macOS label colors as a convenience.
    public struct FinderTagGroup: Hashable, Sendable {
        /// All 8 built-in macOS label colors (none through orange).
        public static let defaultTags: FinderTagGroup = .init(
            tags: TagColor.allCases.map {
                FinderTagDescription(tagColor: $0)
            }
        )

        /// The individual tag descriptions in this group.
        public var tags: [FinderTagDescription] = .init()

        /// Comma-separated string of all tag labels.
        public var stringValue: String {
            tags.map(\.label)
                .joined(separator: ", ")
        }

        /// The `NSColor` of the first color tag in the group, or `nil` if no color tags are present.
        public var defaultColor: NSColor? {
            guard let color = tags.first(where: { $0.tagColor != .none })?.tagColor else { return nil }

            guard let nsColor = color.nsColor else {
                return nil
            }

            return nsColor
        }

        /// The color labels in this group, excluding `.none` (text-only tags).
        public var tagColors: [TagColor] {
            tags.filter {
                $0.tagColor != .none
            }
            .map(\.tagColor)
        }

        /// The display names of all color tags (excluding text-only tags).
        public func labels() -> [String] {
            tags.filter {
                $0.tagColor != .none
            }
            .map(\.label)
        }

        public init() {}

        /// Creates a tag group from the Finder tags currently attached to a file URL.
        public init(url: URL) {
            self = FinderTagGroup(tags: url.finderTags)
        }

        public init(tags: [FinderTagDescription]) {
            self.tags = tags
        }

        /// Replaces all color tags with the given descriptions, preserving text-only tags.
        public mutating func insert(colors: [FinderTagDescription]) {
            tags = tags.filter { $0.tagColor == .none }
            let colors = colors.filter { $0.tagColor != .none }

            tags = tags.union(colors)
        }

        /// Replaces all color tags, keeping text-only tags and appending the new colors.
        public mutating func update(colors: [FinderTagDescription]) {
            tags = tags.filter { $0.tagColor == .none }
            tags += colors
        }
    }

    extension FinderTagGroup: Codable {
        enum CodingKeys: String, CodingKey {
            case tags
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            tags = try container.decode([FinderTagDescription].self, forKey: .tags)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(tags, forKey: .tags)
        }
    }

#endif
