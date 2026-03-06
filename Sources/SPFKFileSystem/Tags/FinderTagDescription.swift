// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

#if os(macOS)
    import Foundation

    /// Describes the tags found and set by the finder such as colored labels or custom strings
    public struct FinderTagDescription: Hashable, Equatable, Sendable, Comparable {
        public static func < (lhs: FinderTagDescription, rhs: FinderTagDescription) -> Bool {
            lhs.label.standardCompare(with: rhs.label)
        }

        public var tagColor: TagColor
        public var label: String

        public init(tagColor: TagColor) {
            self.tagColor = tagColor
            label = tagColor.name
        }

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
