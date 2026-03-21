// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

#if os(macOS)
    import Foundation

    /// Describes a single Finder tag — either a standard color label or a custom text tag.
    ///
    /// **macOS only** (`#if os(macOS)`).
    ///
    /// Each tag has a ``tagColor`` (one of the 7 built-in macOS label colors, or `.none` for
    /// custom text-only tags) and a ``label`` string. Standard color tags use the color's
    /// ``TagColor/name`` as the label.
    ///
    /// Read tags from a file URL via ``URL/finderTags``, or write them with
    /// ``URL/set(finderTags:)``.
    public struct FinderTagDescription: Hashable, Equatable, Sendable, Comparable {
        public static func < (lhs: FinderTagDescription, rhs: FinderTagDescription) -> Bool {
            lhs.label.standardCompare(with: rhs.label)
        }

        /// The color label for this tag, or `.none` for custom text-only tags.
        public var tagColor: TagColor

        /// The display name of this tag.
        public var label: String

        /// Creates a tag from a standard color label.
        /// - Parameter tagColor: The macOS label color.
        public init(tagColor: TagColor) {
            self.tagColor = tagColor
            label = tagColor.name
        }

        /// Creates a custom text-only tag with no associated color.
        /// - Parameter label: The tag text.
        public init(label: String) {
            tagColor = TagColor.none
            self.label = label
        }
    }

    extension FinderTagDescription: Codable {
        enum CodingKeys: String, CodingKey {
            case tagColor
            case label
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            tagColor = try container.decode(TagColor.self, forKey: .tagColor)
            label = try container.decode(String.self, forKey: .label)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(tagColor, forKey: .tagColor)
            try container.encode(label, forKey: .label)
        }
    }

#endif
