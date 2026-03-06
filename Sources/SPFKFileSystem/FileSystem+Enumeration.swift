// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation
import SwiftExtensions

extension FileSystem {
    /// Resource keys prefetched by directory enumerators to avoid per-URL disk calls.
    private static let enumerationResourceKeys: [URLResourceKey] = [
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
    /// - Returns: The original URL if available, or the first non-conflicting numbered variant.
    public static func nextAvailableURL(_ url: URL,
                                        delimiter: String = "_",
                                        suffix: String = "") -> URL
    {
        guard url.exists else { return url } // no need to do anything

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
            if !test.exists { return test }
        }
        return url
    }

    // MARK: - Directory enumeration

    /// Returns all subdirectories within the given directory, optionally recursive.
    ///
    /// Resolves aliases and skips packages (bundles). Hidden files are skipped by default.
    /// - Parameters:
    ///   - directory: The root directory to enumerate.
    ///   - recursive: Whether to descend into subdirectories.
    ///   - skipHidden: Whether to skip hidden files and directories.
    /// - Returns: An array of directory URLs found.
    public static func getDirectories(in directory: URL,
                                      recursive: Bool,
                                      skipHidden: Bool = true) -> [URL]
    {
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

                // Finder aliases to directories aren't followed by the enumerator
                // (unlike symlinks). Recursively enumerate the resolved target.
                if recursive, localURL.isDirectory, !localURL.isPackage {
                    allFiles.append(localURL)
                    allFiles += getDirectories(
                        in: localURL,
                        recursive: true,
                        skipHidden: skipHidden
                    )
                    continue
                }
            }

            if localURL.isDirectory, !localURL.isPackage {
                allFiles.append(localURL)
            }
        }

        return allFiles
    }

    /// Searches recursively for a folder with the given name.
    /// - Parameters:
    ///   - folderName: The `lastPathComponent` to match.
    ///   - directory: The root directory to search.
    /// - Returns: The URL of the first matching folder, or `nil` if not found.
    public static func searchRecursivelyForFolder(named folderName: String, in directory: URL) -> URL? {
        FileSystem.getDirectories(in: directory, recursive: true).first(
            where: { subfolder in
                subfolder.lastPathComponent == folderName
            }
        )
    }

    // MARK: - Package enumeration

    /// Returns all package (bundle) URLs within the given directory.
    ///
    /// Similar to ``getFileURLs(in:withExtension:recursive:allowedPackageTypes:skipsHiddenFiles:skipsPackageDescendants:sorted:)``
    /// but specifically targets macOS packages (e.g., `.app`, `.framework`, custom types).
    /// - Parameters:
    ///   - directory: The root directory to enumerate.
    ///   - withExtension: Optional file extension filter (case-insensitive).
    ///   - recursive: Whether to descend into subdirectories.
    ///   - skipHidden: Whether to skip hidden files. Default is `true`.
    /// - Returns: An array of package URLs.
    public static func getPackages(in directory: URL,
                                   withExtension: String? = nil,
                                   recursive: Bool,
                                   skipHidden: Bool = true) -> [URL]
    {
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

    // MARK: - File enumeration

    /// Create a flat set of urls containing only file urls.
    /// Recursively scans directories.
    public static func getFileURLs(in urls: [URL]) -> Set<URL> {
        var result = Set<URL>()

        for url in urls {
            if url.isDirectoryOrPackage {
                for file in getFileURLs(in: url, recursive: true) where !file.isDirectoryOrPackage {
                    result.insert(file)
                }
            } else {
                result.insert(url)
            }
        }

        return result
    }

    /// Returns all files at the given URL.
    public static func getFileURLs(
        in directory: URL,
        withExtension: String? = nil,
        recursive: Bool,
        allowedPackageTypes: [String] = [],
        skipsHiddenFiles: Bool = true,
        skipsPackageDescendants: Bool = true,
        sorted: Bool = false
    ) -> [URL] {
        guard directory.exists else {
            Log.error(directory, "doesn't exist")
            return []
        }

        var options: FileManager.DirectoryEnumerationOptions = []

        if !recursive {
            options.insert(.skipsSubdirectoryDescendants)
        }

        if skipsHiddenFiles {
            options.insert(.skipsHiddenFiles)
        }

        if skipsPackageDescendants {
            options.insert(.skipsPackageDescendants)
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

                // Finder aliases to directories aren't followed by the enumerator.
                // Recursively enumerate the resolved target.
                if recursive, localURL.isDirectoryOrPackage {
                    if localURL.isPackage, skipsPackageDescendants {
                        continue
                    } else if localURL.isPackage, !allowedPackageTypes.contains(localURL.pathExtension) {
                        allFiles.append(localURL)
                    } else {
                        allFiles += getFileURLs(
                            in: localURL,
                            withExtension: withExtension,
                            recursive: true,
                            allowedPackageTypes: allowedPackageTypes,
                            skipsHiddenFiles: skipsHiddenFiles,
                            skipsPackageDescendants: skipsPackageDescendants
                        )
                    }
                    continue
                }
            }

            if localURL.isPackage, skipsPackageDescendants {
                continue

            } else if localURL.isPackage, !allowedPackageTypes.contains(localURL.pathExtension) {
                // Treat package as leaf file, don't descend into it
                allFiles.append(localURL)
                enumerator.skipDescendants()

            } else if localURL.isDirectoryOrPackage {
                // Plain directory or allowed-type package: enumerator descends automatically
                continue

            } else if let withExtension {
                if localURL.pathExtension.equalsIgnoringCase(withExtension) {
                    allFiles.append(localURL)
                }
            } else {
                allFiles.append(localURL)
            }
        }

        if sorted {
            allFiles.sort {
                $0.lastPathComponent.standardCompare(
                    with: $1.lastPathComponent,
                    ascending: true
                )
            }
        }

        return allFiles
    }

    // MARK: - Async streaming

    /// Yields file URLs as they are discovered, allowing callers to begin processing
    /// before the full enumeration completes.
    ///
    /// This is the streaming equivalent of ``getFileURLs(in:)-6p0n5``.
    /// Deduplication is performed inline.
    ///
    /// - Parameter urls: An array of file or directory URLs to scan.
    /// - Returns: An `AsyncStream` of unique file URLs.
    public static func fileURLStream(in urls: [URL]) -> AsyncStream<URL> {
        AsyncStream { continuation in
            var seen = Set<URL>()

            for url in urls {
                if Task.isCancelled {
                    continuation.finish()
                    return
                }

                if url.isDirectoryOrPackage {
                    for file in getFileURLs(in: url, recursive: true) where !file.isDirectoryOrPackage {
                        if seen.insert(file).inserted {
                            continuation.yield(file)
                        }
                    }
                } else {
                    if seen.insert(url).inserted {
                        continuation.yield(url)
                    }
                }
            }

            continuation.finish()
        }
    }
}
