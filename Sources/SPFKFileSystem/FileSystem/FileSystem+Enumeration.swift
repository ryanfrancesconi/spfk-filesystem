// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation
import SPFKBase
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
    public static func nextAvailableURL(
        _ url: URL,
        delimiter: String = "_",
        suffix: String = ""
    ) -> URL {
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
                    allFiles += enumerateDirectories(
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
    /// Similar to ``enumerateFiles(in:recursive:options:)``
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

    // MARK: - File enumeration

    /// Options for controlling file enumeration behavior in ``enumerateFiles(in:recursive:options:)``.
    ///
    /// All properties use sensible defaults — create with `.init()` for standard behavior
    /// (skip hidden files, skip package contents, no extension filter, unsorted).
    public struct FileDiscoveryEnumerationOptions: Sendable {
        /// Optional file extension filter (case-insensitive).
        public var fileExtension: String?

        /// Package types whose contents should be enumerated rather than treated as leaf files.
        public var allowedPackageTypes: [String] = []

        /// Whether to skip hidden files and directories. Default is `true`.
        public var skipsHiddenFiles: Bool = true

        /// Whether to skip descending into packages. Default is `true`.
        public var skipsPackageDescendants: Bool = true

        /// Whether to sort results by filename. Default is `false`.
        public var sorted: Bool = false

        public init(
            fileExtension: String? = nil,
            allowedPackageTypes: [String] = [],
            skipsHiddenFiles: Bool = true,
            skipsPackageDescendants: Bool = true,
            sorted: Bool = false
        ) {
            self.fileExtension = fileExtension
            self.allowedPackageTypes = allowedPackageTypes
            self.skipsHiddenFiles = skipsHiddenFiles
            self.skipsPackageDescendants = skipsPackageDescendants
            self.sorted = sorted
        }
    }

    /// Returns a deduplicated set of file URLs from the given inputs.
    ///
    /// Directories and packages in the input array are recursively scanned for their
    /// contained files. Plain file URLs are included directly. The returned set
    /// excludes directories and packages themselves.
    ///
    /// - Parameter urls: An array of file or directory URLs to scan.
    /// - Returns: A `Set` of unique file URLs discovered across all inputs.
    public static func enumerateFiles(in urls: [URL]) -> Set<URL> {
        var result = Set<URL>()

        for url in urls {
            if url.isDirectoryOrPackage {
                for file in enumerateFiles(in: url, recursive: true) where !file.isDirectoryOrPackage {
                    result.insert(file)
                }
            } else {
                result.insert(url)
            }
        }

        return result
    }

    /// Returns all file URLs within the given directory.
    ///
    /// Walks the directory tree using `FileManager.enumerator`, resolving Finder aliases
    /// and classifying each URL as a file, directory, or package. Alias targets that are
    /// directories are recursively enumerated (the system enumerator follows symlinks but
    /// not Finder aliases).
    ///
    /// - Parameters:
    ///   - directory: The root directory to enumerate.
    ///   - recursive: Whether to descend into subdirectories.
    ///   - options: Controls extension filtering, hidden-file skipping, package handling,
    ///     and result sorting. See ``FileDiscoveryEnumerationOptions``.
    /// - Returns: An array of file URLs found. May include packages treated as leaf files
    ///   when `skipsPackageDescendants` is `false` and the package type is not in
    ///   ``FileDiscoveryEnumerationOptions/allowedPackageTypes``.
    public static func enumerateFiles(
        in directory: URL,
        recursive: Bool,
        options: FileDiscoveryEnumerationOptions = .init()
    ) -> [URL] {
        guard directory.exists else {
            Log.error(directory, "doesn't exist")
            return []
        }

        var fmOptions: FileManager.DirectoryEnumerationOptions = []

        if !recursive {
            fmOptions.insert(.skipsSubdirectoryDescendants)
        }

        if options.skipsHiddenFiles {
            fmOptions.insert(.skipsHiddenFiles)
        }

        if options.skipsPackageDescendants {
            fmOptions.insert(.skipsPackageDescendants)
        }

        guard let enumerator = FileManager().enumerator(
            at: directory,
            includingPropertiesForKeys: enumerationResourceKeys,
            options: fmOptions
        ) else {
            return []
        }

        var allFiles = [URL]()

        while var url = enumerator.nextObject() as? URL {
            var isResolvedAlias = false

            if url.isAlias, let resolved = url.resolveAlias() {
                url = resolved
                isResolvedAlias = true
            }

            switch classify(url, options: options) {
            case .skipPackage:
                continue

            case .leafPackage:
                allFiles.append(url)
                // Only call skipDescendants for real enumerator children, not resolved aliases
                if !isResolvedAlias { enumerator.skipDescendants() }

            case .directory:
                // Finder aliases to directories aren't followed by the enumerator.
                // Recursively enumerate the resolved target.
                if isResolvedAlias, recursive {
                    allFiles += enumerateFiles(in: url, recursive: true, options: options)
                }

            case .file:
                if matchesExtension(url, options.fileExtension) {
                    allFiles.append(url)
                }
            }
        }

        if options.sorted {
            allFiles.sort {
                $0.lastPathComponent.standardCompare(
                    with: $1.lastPathComponent,
                    ascending: true
                )
            }
        }

        return allFiles
    }

    // MARK: - Private helpers

    /// Classification of a URL encountered during directory enumeration.
    private enum URLClassification {
        /// Regular file — append to results.
        case file
        /// Plain directory or allowed package type — enumerator descends automatically.
        case directory
        /// Package treated as a leaf file — append to results, skip descendants.
        case leafPackage
        /// Package that should be ignored entirely (when skipping package descendants).
        case skipPackage
    }

    /// Classifies a URL for enumeration handling.
    private static func classify(
        _ url: URL,
        options opts: FileDiscoveryEnumerationOptions
    ) -> URLClassification {
        if url.isPackage {
            if opts.skipsPackageDescendants {
                return .skipPackage
            } else if !opts.allowedPackageTypes.contains(url.pathExtension) {
                return .leafPackage
            }
        }

        if url.isDirectoryOrPackage {
            return .directory
        }

        return .file
    }

    /// Returns `true` if the URL matches the given extension filter, or if no filter is set.
    private static func matchesExtension(_ url: URL, _ ext: String?) -> Bool {
        guard let ext else { return true }
        return url.pathExtension.equalsIgnoringCase(ext)
    }

    // MARK: - Async streaming

    /// Yields file URLs as they are discovered, allowing callers to begin processing
    /// before the full enumeration completes.
    ///
    /// This is the streaming equivalent of ``enumerateFiles(in:)``.
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
                    for file in enumerateFiles(in: url, recursive: true) where !file.isDirectoryOrPackage {
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
