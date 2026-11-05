// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Darwin
import Foundation

extension FileSystem {
    /// What a directory tree holds, counting each inode once, as `du` does.
    public struct DiskUsage: Sendable, Equatable {
        /// Paths to regular files, including every path of a hardlinked file.
        public var fileCount = 0
        /// Space allocated on disk.
        public var allocatedBytes: Int64 = 0
        /// Bytes a copy writes.
        public var logicalBytes: Int64 = 0
    }

    public static func diskUsage(of directory: URL) -> DiskUsage {
        var usage = DiskUsage()
        var seen = Set<InodeKey>()

        forEachEntry(under: directory.path) { _, info in
            guard info.isRegularFile else { return }

            usage.fileCount += 1

            guard seen.insert(info.key).inserted else { return }

            usage.allocatedBytes += Int64(info.stat.st_blocks) * 512
            usage.logicalBytes += Int64(info.stat.st_size)
        }

        return usage
    }

    /// Moves every entry under `source` into `destination`, which is created if absent. `source`
    /// itself stays, empty. Where both hold an entry at the same path, the destination's is kept.
    ///
    /// On one volume each entry is renamed. Across volumes the tree is copied with files sharing an
    /// inode linked rather than copied again, and the source is removed only once the copy is
    /// complete. Cancelling the calling task, or an error during the copy, removes what was written
    /// and leaves the source whole.
    ///
    /// - Parameter progress: the fraction of bytes copied; called only for a copy.
    public static func mergeMove(
        contentsOf source: URL,
        into destination: URL,
        progress: ((Double) -> Void)? = nil
    ) throws {
        try mergeMove(contentsOf: source, into: destination, forceCopy: false, progress: progress)
    }

    static func mergeMove(
        contentsOf source: URL,
        into destination: URL,
        forceCopy: Bool,
        progress: ((Double) -> Void)?
    ) throws {
        let fm = FileManager.default
        let destinationExisted = fm.fileExists(atPath: destination.path)
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        guard let sourceInfo = EntryInfo(path: source.path), let destinationInfo = EntryInfo(path: destination.path) else {
            throw POSIXError(.ENOENT)
        }

        if !forceCopy, sourceInfo.stat.st_dev == destinationInfo.stat.st_dev {
            try mergeRename(source.path, into: destination.path)
            return
        }

        var copier = HardlinkPreservingCopier(
            totalBytes: diskUsage(of: source).logicalBytes,
            progress: progress
        )

        if !destinationExisted {
            copier.created.append(destination.path)
        }

        do {
            try copier.copyContents(of: source.path, into: destination.path, parentIsNew: !destinationExisted)
        } catch {
            for path in copier.created.reversed() {
                try? fm.removeItem(atPath: path)
            }
            throw error
        }

        for name in try fm.contentsOfDirectory(atPath: source.path) {
            try fm.removeItem(atPath: (source.path as NSString).appendingPathComponent(name))
        }
    }

    private static func mergeRename(_ source: String, into destination: String) throws {
        let fm = FileManager.default

        for name in try fm.contentsOfDirectory(atPath: source) {
            let from = (source as NSString).appendingPathComponent(name)
            let to = (destination as NSString).appendingPathComponent(name)

            guard let existing = EntryInfo(path: to) else {
                guard rename(from, to) == 0 else { throw POSIXError.current }
                continue
            }

            if existing.isDirectory, EntryInfo(path: from)?.isDirectory == true {
                try mergeRename(from, into: to)
            }

            try fm.removeItem(atPath: from)
        }
    }
}

// MARK: - Copy

private struct HardlinkPreservingCopier {
    let totalBytes: Int64
    let progress: ((Double) -> Void)?

    /// The topmost entries this copy created, removed on failure.
    var created: [String] = []
    private var firstCopy: [InodeKey: String] = [:]
    private var copiedBytes: Int64 = 0

    init(totalBytes: Int64, progress: ((Double) -> Void)?) {
        self.totalBytes = totalBytes
        self.progress = progress
    }

    mutating func copyContents(of source: String, into destination: String, parentIsNew: Bool) throws {
        let fm = FileManager.default

        for name in try fm.contentsOfDirectory(atPath: source) {
            try Task.checkCancellation()

            let from = (source as NSString).appendingPathComponent(name)
            let to = (destination as NSString).appendingPathComponent(name)

            guard let info = EntryInfo(path: from) else { continue }
            let existing = EntryInfo(path: to)

            if info.isDirectory {
                if existing == nil {
                    try fm.createDirectory(atPath: to, withIntermediateDirectories: false)
                    if !parentIsNew { created.append(to) }
                    try copyContents(of: from, into: to, parentIsNew: true)
                } else if existing?.isDirectory == true {
                    try copyContents(of: from, into: to, parentIsNew: false)
                }
                continue
            }

            guard existing == nil else { continue }

            if info.isRegularFile, info.stat.st_nlink > 1, let first = firstCopy[info.key] {
                guard link(first, to) == 0 else { throw POSIXError.current }
            } else {
                try fm.copyItem(atPath: from, toPath: to)

                if info.isRegularFile {
                    if info.stat.st_nlink > 1 { firstCopy[info.key] = to }
                    copiedBytes += Int64(info.stat.st_size)
                    if totalBytes > 0 { progress?(min(1, Double(copiedBytes) / Double(totalBytes))) }
                }
            }

            if !parentIsNew { created.append(to) }
        }
    }
}

// MARK: - Entries

struct InodeKey: Hashable {
    let device: dev_t
    let inode: ino_t
}

private struct EntryInfo {
    let stat: Darwin.stat

    /// `nil` when nothing is at `path`. Does not follow a symlink.
    init?(path: String) {
        var info = Darwin.stat()
        guard lstat(path, &info) == 0 else { return nil }
        stat = info
    }

    var key: InodeKey { InodeKey(device: stat.st_dev, inode: stat.st_ino) }
    var isDirectory: Bool { stat.st_mode & S_IFMT == S_IFDIR }
    var isRegularFile: Bool { stat.st_mode & S_IFMT == S_IFREG }
}

private func forEachEntry(under directory: String, _ body: (String, EntryInfo) -> Void) {
    guard let enumerator = FileManager.default.enumerator(atPath: directory) else { return }

    while let relative = enumerator.nextObject() as? String {
        let path = (directory as NSString).appendingPathComponent(relative)
        if let info = EntryInfo(path: path) { body(path, info) }
    }
}

extension POSIXError {
    fileprivate static var current: POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
