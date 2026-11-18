// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation
import SPFKBase

extension OriginalsStore {
    /// The files among `urls` a keep would copy (no original yet), and their total size.
    public func cost(toKeep urls: [URL]) -> (count: Int, bytes: Int64) {
        urls.filter { original(for: $0) == nil }.reduce(into: (count: 0, bytes: Int64(0))) { total, url in
            total.count += 1
            total.bytes += Self.size(of: url)
        }
    }

    /// Whether keeping the originals `urls` still need fits. A file the store can clone needs no room.
    public func hasRoom(for urls: [URL]) -> Bool {
        let rootValues: URLResourceValues

        do {
            rootValues = try root.resourceValues(forKeys: [
                .volumeIdentifierKey, .volumeSupportsFileCloningKey, .volumeAvailableCapacityForImportantUsageKey,
            ])
        } catch {
            Log.error("The free space of the originals folder could not be read", error)
            return false
        }

        let cloneable = rootValues.volumeSupportsFileCloning == true
        let rootVolume = rootValues.volumeIdentifier as? NSObject

        let needed = urls.filter { original(for: $0) == nil }.reduce(Int64(0)) { needed, url in
            if cloneable, let rootVolume,
               let volume = (try? url.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? NSObject,
               volume.isEqual(rootVolume) {
                return needed
            }

            return needed + Self.size(of: url)
        }

        guard needed > 0 else { return true }

        return (rootValues.volumeAvailableCapacityForImportantUsage ?? 0) >= needed
    }

    /// Every original in the store, a crash's `.partial` included, and the bytes the folder holds.
    public func total() -> (count: Int, bytes: Int64) {
        items().reduce(into: (count: 0, bytes: Int64(0))) { total, url in
            if url.pathExtension != "json" { total.count += 1 }
            total.bytes += Self.size(of: url)
        }
    }

    /// Deletes every original and record. The files they were kept for keep their marks, which now
    /// name nothing.
    public func removeAll() throws {
        for url in items() {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Every item in ``root``; none when it does not exist.
    public func items() -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }

        do {
            return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey])
        } catch {
            Log.error("The originals folder could not be listed", error)
            return []
        }
    }

    static func size(of url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    }
}
