// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
    import AppKit
    import Foundation

    /// Describes the tags found and set by the finder such as colored labels
    public struct FinderTagGroup: Hashable, Sendable {
        public static let defaultTags: FinderTagGroup = .init(
            tags: TagColor.allCases.map {
                FinderTagDescription(tagColor: $0)
            }
        )

        // codable value
        public var tags: [FinderTagDescription] = .init()

        public var stringValue: String {
            tags.map(\.label)
                .joined(separator: ", ")
        }

        public var defaultColor: NSColor? {
            guard let color = tags.first(where: { $0.tagColor != .none })?.tagColor else { return nil }

            guard let nsColor = color.nsColor else {
                return nil
            }

            return nsColor
        }

        public var tagColors: [TagColor] {
            tags.filter {
                $0.tagColor != .none
            }
            .map(\.tagColor)
        }

        public func labels() -> [String] {
            tags.filter {
                $0.tagColor != .none
            }
            .map(\.label)
        }

        public init() {}

        public init(url: URL) {
            self = FinderTagGroup(tags: url.finderTags)
        }

        public init(tags: [FinderTagDescription]) {
            self.tags = tags
        }

        public mutating func insert(colors: [FinderTagDescription]) {
            tags = tags.filter { $0.tagColor == .none }
            let colors = colors.filter { $0.tagColor != .none }

            tags = tags.union(colors)
        }

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
