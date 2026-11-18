// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation

/// What an ``OriginalsStore`` knows about one kept original, stored beside it as JSON.
///
/// Decoding ignores unknown keys and treats a missing `renders` as none, so a record written by a
/// later version still reads.
public struct OriginalRecord: Codable, Sendable, Equatable {
    /// One rendered save into the file, after the original was kept.
    public struct Render: Codable, Sendable, Equatable {
        public let date: Date

        /// The product's own edit-kind names.
        public let kinds: [String]

        public init(date: Date, kinds: [String]) {
            self.date = date
            self.kinds = kinds
        }
    }

    public static let currentVersion = 1

    public var version: Int
    public let id: UUID

    /// The file's name and path when it was kept.
    public let filename: String
    public let path: String

    /// Bytes.
    public let size: Int64
    public let keptDate: Date

    /// The bundle identifier of the app that kept it.
    public let product: String

    public var renders: [Render]

    public init(id: UUID, filename: String, path: String, size: Int64, keptDate: Date, product: String, renders: [Render] = []) {
        version = Self.currentVersion
        self.id = id
        self.filename = filename
        self.path = path
        self.size = size
        self.keptDate = keptDate
        self.product = product
        self.renders = renders
    }

    private enum CodingKeys: String, CodingKey {
        case version, id, filename, path, size, keptDate, product, renders
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        id = try container.decode(UUID.self, forKey: .id)
        filename = try container.decode(String.self, forKey: .filename)
        path = try container.decode(String.self, forKey: .path)
        size = try container.decode(Int64.self, forKey: .size)
        keptDate = try container.decode(Date.self, forKey: .keptDate)
        product = try container.decode(String.self, forKey: .product)
        renders = try container.decodeIfPresent([Render].self, forKey: .renders) ?? []
    }

    /// Every kind any render wrote, in first-seen order.
    public var renderedKinds: [String] {
        var seen: Set<String> = []
        return renders.flatMap(\.kinds).filter { seen.insert($0).inserted }
    }
}

extension OriginalRecord {
    static func read(from url: URL) throws -> OriginalRecord {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(OriginalRecord.self, from: Data(contentsOf: url))
    }

    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
