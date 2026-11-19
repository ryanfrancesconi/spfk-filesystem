// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation
import SPFKBase

/// A folder of files as they were before their first rendered save, each linked to its file by an
/// extended attribute on that file holding the original's id.
///
/// No state of its own: every answer comes from the file system, so it can be used from any task.
/// The attribute rides `replaceItemAt`, renames and copies, so a copy of a file shares its original.
public struct OriginalsStore: Sendable, Equatable {
    /// Holds `<id>.<ext>` originals and `<id>.json` records, flat.
    public let root: URL

    /// `com.spongefork.original.<product>`, so two products keep separate originals of one file.
    public let attributeName: String

    /// Written into each record.
    public let productIdentifier: String

    public init(root: URL, product: String, productIdentifier: String = Bundle.main.bundleIdentifier ?? "") {
        self.root = root.standardizedFileURL
        attributeName = Self.attributePrefix + product
        self.productIdentifier = productIdentifier
    }

    /// The original kept for `url`, or nil: no attribute, or its original is not in ``root``.
    public func original(for url: URL) -> KeptOriginal? {
        guard let id = keptID(of: url) else { return nil }
        return kept(id: id, pathExtension: url.pathExtension)
    }

    /// The original with `id` in ``root``, or nil. The extension is tried first, then the folder is searched.
    func kept(id: UUID, pathExtension: String) -> KeptOriginal? {
        let recordURL = root.appendingPathComponent("\(id.uuidString).json")
        let fileManager = FileManager.default

        let direct = root.appendingPathComponent(id.uuidString).appendingPathExtension(pathExtension)
        if fileManager.fileExists(atPath: direct.path) {
            return KeptOriginal(id: id, url: direct, recordURL: recordURL)
        }

        // A Rename that changed the extension leaves the original under the old one.
        guard let names = try? fileManager.contentsOfDirectory(atPath: root.path),
              let name = names.first(where: { $0.hasPrefix(id.uuidString + ".") && !$0.hasSuffix(".json") })
        else { return nil }

        return KeptOriginal(id: id, url: root.appendingPathComponent(name), recordURL: recordURL)
    }

    /// Copies `url` into the store and marks `url`, unless it already has an original.
    ///
    /// Leaves the modification date of `url` alone. A failure at any step removes what the earlier
    /// steps made, then throws.
    ///
    /// - Returns: the new original, or nil when one was already kept.
    public func keep(_ url: URL) throws -> KeptOriginal? {
        guard original(for: url) == nil else { return nil }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let id = UUID()
        let partial = root.appendingPathComponent(".\(id.uuidString).partial")
        let kept = KeptOriginal(
            id: id,
            url: root.appendingPathComponent(id.uuidString).appendingPathExtension(url.pathExtension),
            recordURL: root.appendingPathComponent("\(id.uuidString).json")
        )

        do {
            try fileManager.copyItem(at: url, to: partial)

            // A stale mark, whose original is gone, travels with the copy. An original carrying it
            // would put that mark back on the file when reverted.
            try removeAttribute(from: partial)

            try fileManager.moveItem(at: partial, to: kept.url)

            let size = try kept.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            let record = OriginalRecord(
                id: id,
                filename: url.lastPathComponent,
                path: url.path,
                size: Int64(size),
                keptDate: Date(),
                product: productIdentifier
            )
            try record.write(to: kept.recordURL)

            try setAttribute(id, on: url)
        } catch {
            for leftover in [partial, kept.url, kept.recordURL] where fileManager.fileExists(atPath: leftover.path) {
                try? fileManager.removeItem(at: leftover)
            }
            throw error
        }

        return kept
    }

    /// Removes an original this save created, when the swap after it failed.
    public func discard(_ kept: KeptOriginal, unmarking url: URL) {
        if keptID(of: url) == kept.id {
            do {
                try removeAttribute(from: url)
            } catch {
                Log.error("The original's mark could not be removed from \(url.lastPathComponent)", error)
            }
        }

        for item in [kept.url, kept.recordURL] where FileManager.default.fileExists(atPath: item.path) {
            do {
                try FileManager.default.removeItem(at: item)
            } catch {
                Log.error("A discarded original could not be removed: \(item.lastPathComponent)", error)
            }
        }
    }

    public func record(of kept: KeptOriginal) throws -> OriginalRecord {
        try OriginalRecord.read(from: kept.recordURL)
    }

    /// Appends the kinds one rendered save wrote into `url` to its record. No-op without an original.
    public func noteRender(of url: URL, kinds: [String]) throws {
        guard let kept = original(for: url) else { return }

        var record = try record(of: kept)
        record.renders.append(.init(date: Date(), kinds: kinds))
        try record.write(to: kept.recordURL)
    }

    /// Empties the record's renders: the file holds its original's content again.
    public func clearRenders(of kept: KeptOriginal) throws {
        var record = try record(of: kept)
        record.renders = []
        try record.write(to: kept.recordURL)
    }
}
