// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation

extension FileSystem {
    // MARK: - Volume queries

    /// Returns the free space in bytes at the given file system path.
    /// - Parameter path: The file system path to check. Defaults to `"/"`.
    /// - Returns: Free space in bytes, or `nil` if attributes cannot be read.
    public static func freeSpace(forPath path: String = "/") -> UInt64? {
        guard let attributes = try? FileManager.default
            .attributesOfFileSystem(forPath: path) else { return nil }

        return attributes[FileAttributeKey.systemFreeSize] as? UInt64
    }

    /// Returns the total size in bytes of the file system at the given path.
    /// - Parameter path: The file system path to check. Defaults to `"/"`.
    /// - Returns: Total size in bytes, or `nil` if attributes cannot be read.
    public static func totalSpace(forPath path: String = "/") -> UInt64? {
        guard let attributes = try? FileManager.default
            .attributesOfFileSystem(forPath: path) else { return nil }

        return attributes[FileAttributeKey.systemSize] as? UInt64
    }

    /// Returns a human-readable string describing the free space at the given path.
    /// - Parameter path: The file system path to check. Defaults to `"/"`.
    /// - Returns: A formatted string such as `"1 GB"`, or `nil` if unavailable.
    public static func freeSpaceDescription(forPath path: String = "/") -> String? {
        guard let byteCount = freeSpace(forPath: path)?.int64 else { return nil }
        return ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    /// Returns a human-readable string describing the total size at the given path.
    /// - Parameter path: The file system path to check. Defaults to `"/"`.
    /// - Returns: A formatted string such as `"500 GB"`, or `nil` if unavailable.
    public static func totalSpaceDescription(forPath path: String = "/") -> String? {
        guard let byteCount = totalSpace(forPath: path)?.int64 else { return nil }
        return ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    /// Returns URLs of all currently mounted volumes.
    public static func mountedVolumes() -> [URL] {
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
        volumeURL(forFileURL: url, among: mountedVolumes())
    }

    /// ``volumeURL(forFileURL:)`` against a list of volumes read once, for a caller asking about
    /// many URLs.
    public static func volumeURL(forFileURL url: URL, among volumes: [URL]) -> URL? {
        let isExternal = url.pathComponents.contains("Volumes")

        var volumes = volumes

        if isExternal {
            volumes = volumes.filter {
                $0.pathComponents.contains("Volumes")
            }
        }

        // By whole components, so `/Volumes/ADD` does not claim `/Volumes/ADD2`; the deepest
        // match wins over an enclosing mount such as `/`.
        let components = url.standardizedFileURL.pathComponents

        return volumes
            .filter { components.starts(with: $0.standardizedFileURL.pathComponents) }
            .max { $0.pathComponents.count < $1.pathComponents.count }
    }
}
