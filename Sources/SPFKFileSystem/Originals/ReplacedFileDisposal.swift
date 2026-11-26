// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation

/// What Revert to Original does with the file it replaced.
public enum ReplacedFileDisposal: Sendable {
    /// Moves it to the Trash under the file's own name.
    case trash

    /// Removes it. For tests, which would otherwise fill the user's Trash.
    case delete

    /// Disposes of `backup`, the replaced file under a hidden name, as `name`.
    ///
    /// - Returns: where it landed in the Trash, or nil when deleted.
    @discardableResult
    public func dispose(of backup: URL, named name: String) throws -> URL? {
        let fileManager = FileManager.default

        guard self == .trash else {
            try fileManager.removeItem(at: backup)
            return nil
        }

        // Renamed inside a hidden folder on the same volume, so the folder never shows the real name twice.
        // Named as a render sibling, so a crash's leftover is swept on the next launch.
        let folder = backup.deletingLastPathComponent().appendingPathComponent(name).renderSiblingURL()
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: folder) }

        let named = folder.appendingPathComponent(name)
        try fileManager.moveItem(at: backup, to: named)

        do {
            var result: NSURL?
            try fileManager.trashItem(at: named, resultingItemURL: &result)
            return result as URL?
        } catch {
            try? fileManager.moveItem(at: named, to: backup)
            throw error
        }
    }
}
