// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

#if os(macOS)
    import AppKit
#endif
import Foundation
import os
import SPFKBase

/// Folders swept since launch. A leftover older than launch cannot appear in one later.
private let sweptFolders = OSAllocatedUnfairLock<Set<URL>>(initialState: [])

extension URL {
    /// A hidden file beside this one to render into before swapping it in: `.<UUID>-<name>`. Beside
    /// rather than in a temporary folder, so the swap stays on one volume.
    public func renderSiblingURL() -> URL {
        deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString)-\(lastPathComponent)")
    }

    /// Removes each render sibling in `directory` last modified before `date`: what a crash mid-render
    /// left behind. Pass the process's launch date, so nothing this process is writing is touched.
    public static func removeStaleRenderSiblings(in directory: URL, olderThan date: Date) {
        let names: [String]

        do {
            names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        } catch {
            Log.error("The render leftovers in \(directory.lastPathComponent) could not be listed", error)
            return
        }

        for name in names where isRenderSiblingName(name) {
            let url = directory.appendingPathComponent(name)

            guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  modified < date
            else { continue }

            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                Log.error("A render leftover could not be removed: \(name)", error)
            }
        }
    }

    #if os(macOS)
        /// ``removeStaleRenderSiblings(in:olderThan:)`` for this file's folder, older than this process's
        /// launch, once per folder per launch. Without a launch date nothing is removed.
        public func removeStaleRenderSiblingsOnce() {
            let folder = deletingLastPathComponent()
            guard sweptFolders.withLock({ $0.insert(folder).inserted }) else { return }
            guard let launch = NSRunningApplication.current.launchDate else { return }

            Self.removeStaleRenderSiblings(in: folder, olderThan: launch)
        }
    #endif

    /// `.` then a UUID's 36 characters, then `-`.
    static func isRenderSiblingName(_ name: String) -> Bool {
        name.range(of: "^\\.[0-9A-F-]{36}-", options: .regularExpression) != nil
    }
}
