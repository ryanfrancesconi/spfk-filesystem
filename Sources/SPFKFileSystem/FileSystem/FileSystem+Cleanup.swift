// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation
import SPFKBase

extension FileSystem {
    // MARK: - Empty directory cleanup

    /// Remove directories if there is nothing in them
    /// - Parameter url: URL to perform a deep scan of
    public static func deleteEmptyDirectories(in url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let resourceKeys: [URLResourceKey] = [.creationDateKey, .isDirectoryKey, .isPackageKey]

        if let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: resourceKeys,
            options: []
        ) {
            var directories = [URL]()

            for case let localURL as URL in enumerator {
                if localURL.isPackage || localURL.isDirectory {
                    directories.append(localURL)
                }
            }

            directories = directories.sorted(
                by: { lhs, rhs -> Bool in
                    lhs.pathComponents.count > rhs.pathComponents.count
                }
            )

            Log.debug(directories)

            for localURL in directories {
                let dsstore = localURL.appendingPathComponent(".DS_Store")

                if FileManager.default.fileExists(atPath: dsstore.path) {
                    try? FileManager.default.removeItem(at: dsstore)
                }

                if let directoryContents = try? FileManager.default.contentsOfDirectory(atPath: localURL.path),
                   directoryContents.isEmpty
                {
                    do {
                        try FileManager.default.trashItem(at: localURL, resultingItemURL: nil)
                        Log.debug("🗑 Deleted Empty Directory:", localURL)

                    } catch {
                        Log.error(error)
                    }
                }
            }
        }
    }
}
