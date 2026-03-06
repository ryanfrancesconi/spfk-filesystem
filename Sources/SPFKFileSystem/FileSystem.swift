// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation
import SwiftExtensions

public enum FileSystem {
    // MARK: - File size calculations

    /// Convert bytes to readable string
    /// - Parameter byteCount: the bytes to convert
    /// - Returns: A readable string such as 1 MB
    public static func byteCountToString(_ byteCount: Int64) -> String? {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    /// Attempt to resolve a byte count string to a number
    /// - Parameter string: String such as 1 MB
    /// - Returns: byte count or nil if parsing failed
    public static func stringToByteCount(_ string: String) -> UInt64? {
        let parts = string.components(separatedBy: " ")

        guard let number = parts.first?.double,
              let text = parts.last?.uppercased() else { return nil }

        switch text {
        case "KB":
            return (number * ByteCount.kilobyte.rawValue.double).uInt64
        case "MB":
            return (number * ByteCount.megabyte.rawValue.double).uInt64
        case "GB":
            return (number * ByteCount.gigabyte.rawValue.double).uInt64
        case "TB":
            return (number * ByteCount.terabyte.rawValue.double).uInt64
        default:
            return nil
        }
    }

    /// How much free space is at this location
    /// - Parameter path: The path to the location to check
    /// - Returns: free space in bytes
    public static func getSystemFreeSizeInBytes(forPath path: String = "/") -> UInt64? {
        guard let attributes = try? FileManager.default
            .attributesOfFileSystem(forPath: path) else { return nil }

        let byteCount = attributes[FileAttributeKey.systemFreeSize] as? UInt64
        return byteCount
    }

    public static func getSystemSizeInBytes(forPath path: String = "/") -> UInt64? {
        guard let attributes = try? FileManager.default
            .attributesOfFileSystem(forPath: path) else { return nil }

        let byteCount = attributes[FileAttributeKey.systemSize] as? UInt64
        return byteCount
    }

    /// - Parameter path: The path to read from
    /// - Returns: A readable string such as 1 MB
    public static func getSystemFreeSizeDescription(forPath path: String = "/") -> String? {
        guard let byteCount = getSystemFreeSizeInBytes(forPath: path)?.int64 else { return nil }
        return byteCountToString(byteCount)
    }

    /// - Parameter path: The path to read from
    /// - Returns: A readable string such as 1 MB
    public static func getSystemSizeDescription(forPath path: String = "/") -> String? {
        guard let byteCount = getSystemSizeInBytes(forPath: path)?.int64 else { return nil }
        return byteCountToString(byteCount)
    }

    public static func getMountedVolumes() -> [URL] {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeIsBrowsableKey,
            .volumeIsLocalKey,
        ]

        return FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys) ?? []
    }

    public static func volumeURL(forFileURL url: URL) -> URL? {
        let isExternal = url.pathComponents.contains("Volumes")

        var volumes = getMountedVolumes()

        if isExternal {
            volumes = volumes.filter {
                $0.pathComponents.contains("Volumes")
            }
        }

        return volumes.first {
            url.path.hasPrefix($0.path)
        }
    }

    // MARK: - Empty directory cleanup

    /// Remove directories if there is nothing in them
    /// - Parameter url: URL to perform a deep scan of
    public static func deleteEmptyDirectories(in url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let resourceKeys: [URLResourceKey] = [.creationDateKey, .isDirectoryKey]

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

    // MARK: - File System

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

    public static func getQueryStringParameter(url: String,
                                               param: String) -> String?
    {
        guard let url = URLComponents(string: url) else { return nil }
        return url.queryItems?.first(where: { $0.name == param })?.value
    }

    // MARK: - getFileURLs / getFilePaths

    // has overlap with getFileURLs
    public static func getDirectories(in directory: URL,
                                      recursive: Bool,
                                      skipHidden: Bool = true) -> [URL]
    {
        var allFiles = [URL]()

        guard directory.exists else {
            Log.error(directory, "doesn't exist")
            return []
        }

        let options: FileManager.DirectoryEnumerationOptions = skipHidden ?
            [.skipsHiddenFiles, .skipsSubdirectoryDescendants] :
            [.skipsSubdirectoryDescendants]

        if let enumerator = FileManager().enumerator(
            at: directory,
            includingPropertiesForKeys: [],
            options: options
        ) {
            while var localURL = enumerator.nextObject() as? URL {
                // resolve target if it's an alias.
                // an alias/symlink can be a file or folder.
                if localURL.isAlias, let resolved = localURL.resolveAlias() {
                    localURL = resolved
                }

                let isPackage = localURL.isPackage

                if localURL.isDirectory, !isPackage {
                    allFiles += localURL

                    if recursive {
                        allFiles += getDirectories(
                            in: localURL,
                            recursive: recursive,
                            skipHidden: skipHidden
                        )
                    }
                }
            }
        }
        return allFiles
    }

    public static func searchRecursivelyForFolder(named folderName: String, in directory: URL) -> URL? {
        FileSystem.getDirectories(in: directory, recursive: true).first(
            where: { subfolder in
                subfolder.lastPathComponent == folderName
            }
        )
    }

    // DRY with getFileURLs but specific to packages such as .addLibrary
    public static func getPackages(in directory: URL,
                                   withExtension: String? = nil,
                                   recursive: Bool,
                                   skipHidden: Bool = true) -> [URL]
    {
        var allFiles = [URL]()

        guard directory.exists else {
            Log.error(directory, "doesn't exist")
            return []
        }

        var options: FileManager.DirectoryEnumerationOptions = [.skipsSubdirectoryDescendants]

        if skipHidden { options.insert(.skipsHiddenFiles) }

        if let enumerator = FileManager().enumerator(
            at: directory,
            includingPropertiesForKeys: [],
            options: options
        ) {
            while var localURL = enumerator.nextObject() as? URL {
                // resolve target if it's an alias.
                // an alias/symlink can be a file or folder.
                if localURL.isAlias, let resolved = localURL.resolveAlias() {
                    localURL = resolved
                }

                let isPackage = localURL.isPackage

                if localURL.isDirectory, !isPackage {
                    if recursive {
                        allFiles += getPackages(in: localURL,
                                                withExtension: withExtension,
                                                recursive: recursive,
                                                skipHidden: skipHidden)
                    }
                } else if isPackage {
                    if let withExtension {
                        if localURL.pathExtension.equalsIgnoringCase(withExtension) {
                            allFiles.append(localURL)
                        }
                    } else {
                        allFiles.append(localURL)
                    }
                }
            }
        }
        return allFiles
    }

    /// Create a flat array of urls containing only file urls.
    /// Recursively scans directories.
    public static func getFileURLs(in urls: [URL]) -> Set<URL> {
        let directories = urls.filter(\.isDirectoryOrPackage)
        var directoryURLs = [URL]()

        if directories.isNotEmpty {
            for directoryURL in directories {
                let innerURLs = FileSystem.getFileURLs(in: directoryURL, recursive: true).filter {
                    !$0.isDirectoryOrPackage
                }

                directoryURLs += innerURLs
            }
        }

        let result = (urls + directoryURLs).filter { !$0.isDirectoryOrPackage }

        return Set<URL>(result)
    }

    ///  Returns all files at the given URL.
    public static func getFileURLs(
        in directory: URL,
        withExtension: String? = nil,
        recursive: Bool,
        allowedPackageTypes: [String] = [],
        skipsHiddenFiles: Bool = true,
        skipsPackageDescendants: Bool = true,
        sorted: Bool = false
    ) -> [URL] {
        var allFiles = [URL]()

        guard directory.exists else {
            Log.error(directory, "doesn't exist")
            return []
        }

        var options: FileManager.DirectoryEnumerationOptions = [.skipsSubdirectoryDescendants]

        if skipsHiddenFiles {
            options.insert(.skipsHiddenFiles)
        }

        if skipsPackageDescendants {
            options.insert(.skipsPackageDescendants)
        }

        guard let enumerator = FileManager().enumerator(
            at: directory,
            includingPropertiesForKeys: [],
            options: options
        ) else {
            return []
        }

        while var localURL = enumerator.nextObject() as? URL {
            // resolve target if it's an alias.
            // an alias/symlink can be a file or folder.
            if localURL.isAlias, let resolved = localURL.resolveAlias() {
                localURL = resolved
            }

            if localURL.isPackage, skipsPackageDescendants {
                // SKIP
                continue

            } else if localURL.isPackage, !allowedPackageTypes.contains(localURL.pathExtension) {
                // treat package as leaf
                allFiles.append(localURL)

            } else if localURL.isDirectoryOrPackage, recursive {
                // treat package as directory
                allFiles += getFileURLs(
                    in: localURL,
                    withExtension: withExtension,
                    recursive: recursive,
                    skipsHiddenFiles: skipsHiddenFiles,
                    skipsPackageDescendants: skipsPackageDescendants
                )

            } else if let withExtension {
                if localURL.pathExtension.equalsIgnoringCase(withExtension) {
                    allFiles.append(localURL)
                }
            } else {
                allFiles.append(localURL)
            }
        }

        if sorted {
            allFiles = allFiles.sorted {
                $0.lastPathComponent.standardCompare(
                    with: $1.lastPathComponent,
                    ascending: true
                )
            }
        }

        return allFiles
    }
}
