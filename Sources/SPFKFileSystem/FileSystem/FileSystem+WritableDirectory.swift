// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation

extension FileSystem {
    /// Creates `url` and its parents if absent, then requires a directory this process can write.
    ///
    /// - Throws: when it cannot be created, when a file is in its place, or when it is read-only.
    public static func ensureWritableDirectory(at url: URL, fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)

        guard fileManager.isWritableFile(atPath: url.path) else {
            throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: url.path])
        }
    }
}
