// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation
import SPFKBase
import SwiftExtensions

extension FileSystem {
    /// Resource keys prefetched by directory enumerators to avoid per-URL disk calls.
    static let enumerationResourceKeys: [URLResourceKey] = [
        .isDirectoryKey,
        .isPackageKey,
        .isAliasFileKey,
        .isSymbolicLinkKey,
    ]

    // MARK: - File naming

    /// Returns the next available URL that doesn't conflict with existing files.
    ///
    /// Appends incrementing numbers (`_1`, `_2`, ...) to the filename until a non-existing
    /// path is found.
    /// - Parameters:
    ///   - url: The desired URL.
    ///   - delimiter: Separator before the number. Default is `"_"`.
    ///   - suffix: Optional suffix appended to the base name before numbering.
    ///   - excluding: Names treated as taken even though nothing is on disk at them yet. A caller
    ///     handing out several URLs before any is written passes what it has already given out.
    /// - Returns: The original URL if available, or the first non-conflicting numbered variant.
    public static func nextAvailableURL(
        _ url: URL,
        delimiter: String = "_",
        suffix: String = "",
        excluding: Set<URL> = []
    ) -> URL {
        nextAvailableURL(url, delimiter: delimiter, suffix: suffix, isTaken: { excluding.contains($0) })
    }

    /// Returns the next available URL, treating a name as taken when it exists on disk or
    /// `isTaken` says so — for a caller whose claimed names compare other than by `URL` equality.
    public static func nextAvailableURL(
        _ url: URL,
        delimiter: String = "_",
        suffix: String = "",
        isTaken: (URL) -> Bool
    ) -> URL {
        guard url.exists || isTaken(url) else { return url } // no need to do anything

        let isDirectory = url.isDirectory
        let parentDirectory = url.deletingLastPathComponent()

        let pathExtension = isDirectory ? "" : url.pathExtension
        let baseFilename = isDirectory ?
            url.lastPathComponent + suffix :
            url.deletingPathExtension().lastPathComponent + suffix

        for i in 1 ... 100_000 {
            let filename = "\(baseFilename)\(delimiter)\(i)"

            let test = parentDirectory
                .appendingPathComponent(filename)
                .appendingPathExtension(pathExtension)

            // found an available numbered file
            if !test.exists, !isTaken(test) { return test }
        }
        return url
    }

    // MARK: - Directory enumeration

    /// Returns all subdirectories within the given directory, optionally recursive.
    ///
    /// Resolves aliases and skips packages (bundles). Hidden files are skipped by default. A folder
    /// behind an alias or symlink is walked at most once, and never when it holds `directory`.
    /// - Parameters:
    ///   - directory: The root directory to enumerate.
    ///   - recursive: Whether to descend into subdirectories.
    ///   - skipHidden: Whether to skip hidden files and directories.
    /// - Returns: An array of directory URLs found.
    public static func enumerateDirectories(
        in directory: URL,
        recursive: Bool,
        skipHidden: Bool = true
    ) -> [URL] {
        guard directory.exists else {
            Log.error(directory, "doesn't exist")
            return []
        }

        var options: FileManager.DirectoryEnumerationOptions = []

        if !recursive {
            options.insert(.skipsSubdirectoryDescendants)
        } else {
            options.insert(.skipsPackageDescendants)
        }

        if skipHidden {
            options.insert(.skipsHiddenFiles)
        }

        var targetGuard = AliasTargetGuard(roots: [directory])
        var pending = [directory]
        var allFiles = [URL]()

        while let next = pending.popLast() {
            guard let enumerator = FileManager().enumerator(
                at: next,
                includingPropertiesForKeys: enumerationResourceKeys,
                options: options
            ) else { continue }

            while var localURL = enumerator.nextObject() as? URL {
                if localURL.isAlias, let resolved = localURL.resolveAlias() {
                    localURL = resolved

                    // The enumerator does not descend through an alias or symlink.
                    if recursive, localURL.isDirectory, !localURL.isPackage {
                        if targetGuard.admit(localURL) {
                            allFiles.append(localURL)
                            pending.append(localURL)
                        }
                        continue
                    }
                }

                if localURL.isDirectory, !localURL.isPackage {
                    allFiles.append(localURL)
                }
            }
        }

        return allFiles
    }

    /// Finds the first subdirectory matching the given name by recursively
    /// enumerating from the root directory.
    ///
    /// Uses ``enumerateDirectories(in:recursive:skipHidden:)`` internally and
    /// returns the first match by `lastPathComponent`.
    /// - Parameters:
    ///   - folderName: The `lastPathComponent` to match.
    ///   - directory: The root directory to search.
    /// - Returns: The URL of the first matching folder, or `nil` if not found.
    public static func findDirectory(named folderName: String, in directory: URL) -> URL? {
        FileSystem.enumerateDirectories(in: directory, recursive: true).first(
            where: { subfolder in
                subfolder.lastPathComponent == folderName
            }
        )
    }

    // MARK: - Package enumeration

    /// Returns all package (bundle) URLs within the given directory.
    ///
    /// Similar to ``scanFiles(in:recursive:width:includes:shouldStop:onFound:)``
    /// but specifically targets macOS packages (e.g., `.app`, `.framework`, custom types).
    /// - Parameters:
    ///   - directory: The root directory to enumerate.
    ///   - withExtension: Optional file extension filter (case-insensitive).
    ///   - recursive: Whether to descend into subdirectories.
    ///   - skipHidden: Whether to skip hidden files. Default is `true`.
    /// - Returns: An array of package URLs.
    public static func enumeratePackages(
        in directory: URL,
        withExtension: String? = nil,
        recursive: Bool,
        skipHidden: Bool = true
    ) -> [URL] {
        guard directory.exists else {
            Log.error(directory, "doesn't exist")
            return []
        }

        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]

        if !recursive {
            options.insert(.skipsSubdirectoryDescendants)
        }

        if skipHidden {
            options.insert(.skipsHiddenFiles)
        }

        guard let enumerator = FileManager().enumerator(
            at: directory,
            includingPropertiesForKeys: enumerationResourceKeys,
            options: options
        ) else {
            return []
        }

        var allFiles = [URL]()

        while var localURL = enumerator.nextObject() as? URL {
            if localURL.isAlias, let resolved = localURL.resolveAlias() {
                localURL = resolved
            }

            if localURL.isPackage {
                if let withExtension {
                    if localURL.pathExtension.equalsIgnoringCase(withExtension) {
                        allFiles.append(localURL)
                    }
                } else {
                    allFiles.append(localURL)
                }
            }
        }

        return allFiles
    }
}
