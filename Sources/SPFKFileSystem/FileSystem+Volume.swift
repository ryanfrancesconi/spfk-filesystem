// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation

extension FileSystem {
    // MARK: - Volume queries

    /// How much free space is at this location
    /// - Parameter path: The path to the location to check
    /// - Returns: free space in bytes
    public static func getSystemFreeSizeInBytes(forPath path: String = "/") -> UInt64? {
        guard let attributes = try? FileManager.default
            .attributesOfFileSystem(forPath: path) else { return nil }

        let byteCount = attributes[FileAttributeKey.systemFreeSize] as? UInt64
        return byteCount
    }

    /// Total size of the file system at the given path.
    /// - Parameter path: The file system path to check.
    /// - Returns: Total size in bytes, or `nil` if attributes cannot be read.
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
        return ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    /// - Parameter path: The path to read from
    /// - Returns: A readable string such as 1 MB
    public static func getSystemSizeDescription(forPath path: String = "/") -> String? {
        guard let byteCount = getSystemSizeInBytes(forPath: path)?.int64 else { return nil }
        return ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    /// Returns URLs of all currently mounted volumes.
    public static func getMountedVolumes() -> [URL] {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeIsBrowsableKey,
            .volumeIsLocalKey,
        ]

        return FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys) ?? []
    }

    /// Returns the volume URL that contains the given file URL.
    /// - Parameter url: A file URL to look up.
    /// - Returns: The volume URL, or `nil` if no matching volume is found.
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
}
