// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation
import SPFKBase

/// The kept originals moved by a cache Change Location, for moving back when a later step fails.
public struct OriginalsMove: Sendable {
    public private(set) var moved: [(from: URL, to: URL)] = []

    public init() {}

    public func undo() async {
        let moved = moved
        await Task.detached { Self.moveBack(moved) }.value
    }

    /// Each original, then its record, so a stopped move leaves every original findable in exactly
    /// one place. A failure moves back what moved, then throws.
    public static func move(_ items: [URL], to newRoot: URL) throws -> OriginalsMove {
        let fileManager = FileManager.default
        let records = items.filter { $0.pathExtension == "json" }
        let recordsByID = Dictionary(records.map { ($0.deletingPathExtension().lastPathComponent, $0) }, uniquingKeysWith: { first, _ in first })

        var ordered: [URL] = []
        var placed: Set<URL> = []

        for original in items where original.pathExtension != "json" {
            ordered.append(original)
            if let record = recordsByID[original.deletingPathExtension().lastPathComponent] {
                ordered.append(record)
                placed.insert(record)
            }
        }

        ordered += records.filter { !placed.contains($0) }

        var result = OriginalsMove()

        do {
            for item in ordered {
                let destination = newRoot.appendingPathComponent(item.lastPathComponent)
                try fileManager.moveItem(at: item, to: destination)
                result.moved.append((item, destination))
            }
        } catch {
            moveBack(result.moved)
            throw error
        }

        return result
    }

    private static func moveBack(_ moved: [(from: URL, to: URL)]) {
        for item in moved.reversed() {
            do {
                try FileManager.default.moveItem(at: item.to, to: item.from)
            } catch {
                Log.error("An original could not be moved back: \(item.to.lastPathComponent)", error)
            }
        }
    }
}
