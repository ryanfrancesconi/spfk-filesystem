// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation
import SPFKBase

extension FileSystem {
    /// Removes each folder that held one of `sources` and is now empty, then each parent left
    /// empty by that, never reaching `root` or anything outside it. Returns the removed folders,
    /// children first.
    ///
    /// A folder holding nothing but `.DS_Store` counts as empty. Removal is outright rather than
    /// to the Trash: an undo of the move recreates the folder.
    @discardableResult
    public static func removeFoldersEmptied(byMoving sources: [URL], within root: URL) -> [URL] {
        let rootComponents = root.standardizedFileURL.pathComponents
        let parents = Set(sources.map { $0.deletingLastPathComponent().standardizedFileURL })
            .sorted { $0.pathComponents.count > $1.pathComponents.count }

        var removed: [URL] = []

        for parent in parents {
            var folder = parent

            while folder.pathComponents.count > rootComponents.count,
                  Array(folder.pathComponents.prefix(rootComponents.count)) == rootComponents,
                  removeIfEmpty(folder) {
                removed.append(folder)
                folder = folder.deletingLastPathComponent()
            }
        }

        return removed
    }

    /// Removes each of `folders` that is empty, deepest first, without ascending past them.
    /// Returns the removed folders, children first.
    @discardableResult
    public static func removeEmptyFolders(_ folders: [URL]) -> [URL] {
        folders
            .map(\.standardizedFileURL)
            .sorted { $0.pathComponents.count > $1.pathComponents.count }
            .filter { removeIfEmpty($0) }
    }

    /// Removes `folder` when it holds nothing but `.DS_Store`.
    private static func removeIfEmpty(_ folder: URL) -> Bool {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path),
              names.allSatisfy({ $0 == ".DS_Store" })
        else { return false }

        do {
            try FileManager.default.removeItem(at: folder)
            return true
        } catch {
            Log.error("Couldn't remove the empty folder \(folder.path)", error)
            return false
        }
    }
}
