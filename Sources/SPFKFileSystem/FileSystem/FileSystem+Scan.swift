// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation
import SPFKBase

extension FileSystem {
    /// Returns every file under `urls`, checking for a stop before each directory entry.
    ///
    /// Directories are walked, skipping hidden items and packages; Finder aliases and symlinks are
    /// resolved and folders behind them walked, each at most once. A file named in `urls` is
    /// returned as is. `includes` is asked about files only, so it never prunes a folder.
    ///
    /// - Parameters:
    ///   - recursive: `false` lists only the immediate contents of each directory.
    ///   - width: how many folders are listed at once.
    ///   - shouldStop: polled per entry alongside `Task.isCancelled`.
    ///   - onFound: the running count of included files, reported on the first one and then at
    ///     most four times a second. Awaited before the walk continues.
    public static func scanFiles(
        in urls: [URL],
        recursive: Bool = true,
        width: Int = 4,
        includes: @escaping @Sendable (URL) -> Bool = { _ in true },
        shouldStop: @escaping @Sendable () -> Bool = { false },
        onFound: (@Sendable (Int) async -> Void)? = nil
    ) async -> FileScanResult {
        var files = Set<URL>()
        var pending = [URL]()
        var reporter = FoundCountReporter(isEnabled: onFound != nil)

        func isStopped() -> Bool { shouldStop() || Task.isCancelled }

        for url in urls {
            if isStopped() { return FileScanResult(files: files, wasStopped: true) }

            if url.isDirectoryOrPackage {
                pending.append(url)
            } else if includes(url), files.insert(url).inserted, reporter.isDue() {
                await onFound?(files.count)
            }
        }

        var targetGuard = AliasTargetGuard(roots: pending)
        pending.reverse()

        let wasStopped = await withTaskGroup(of: FolderListing.self) { group -> Bool in
            var inFlight = 0

            func launch() {
                while inFlight < max(width, 1), let next = pending.popLast() {
                    group.addTask { FolderListing.list(next, includes: includes, shouldStop: shouldStop) }
                    inFlight += 1
                }
            }

            launch()

            while let listing = await group.next() {
                inFlight -= 1

                if listing.wasStopped || isStopped() {
                    group.cancelAll()
                    return true
                }

                let countBefore = files.count
                files.formUnion(listing.files)

                if recursive {
                    pending.append(contentsOf: listing.directories)
                    for target in listing.aliasTargets where targetGuard.admit(target) {
                        pending.append(target)
                    }
                }

                launch()

                if files.count > countBefore, reporter.isDue() {
                    await onFound?(files.count)
                }
            }

            return false
        }

        return FileScanResult(files: files, wasStopped: wasStopped)
    }
}

/// One folder's immediate contents, sorted for the walk.
private struct FolderListing: Sendable {
    var files: [URL] = []
    var directories: [URL] = []
    /// Folders behind an alias or symlink, which the walk admits through ``AliasTargetGuard``.
    var aliasTargets: [URL] = []
    var wasStopped = false

    static func list(_ directory: URL, includes: @Sendable (URL) -> Bool, shouldStop: @Sendable () -> Bool) -> FolderListing {
        autoreleasepool {
            var listing = FolderListing()

            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: FileSystem.enumerationResourceKeys,
                options: [.skipsHiddenFiles]
            ) else { return listing }

            for var url in entries {
                if shouldStop() || Task.isCancelled {
                    listing.wasStopped = true
                    return listing
                }

                var isResolvedAlias = false
                if url.isAlias, let resolved = url.resolveAlias() {
                    url = resolved
                    isResolvedAlias = true
                }

                if url.isPackage { continue }

                if url.isDirectory {
                    if isResolvedAlias {
                        listing.aliasTargets.append(url)
                    } else {
                        listing.directories.append(url)
                    }
                    continue
                }

                if includes(url) { listing.files.append(url) }
            }

            return listing
        }
    }
}

/// Throttles ``FileSystem/scanFiles(in:recursive:width:includes:shouldStop:onFound:)``'s count: the
/// first file is reported at once, so a caller can stop a walk too small to reach a second report.
private struct FoundCountReporter {
    let isEnabled: Bool
    private var lastReport: ContinuousClock.Instant?

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    mutating func isDue() -> Bool {
        guard isEnabled else { return false }

        let now = ContinuousClock.now
        if let lastReport, now - lastReport < .milliseconds(250) { return false }

        lastReport = now
        return true
    }
}
