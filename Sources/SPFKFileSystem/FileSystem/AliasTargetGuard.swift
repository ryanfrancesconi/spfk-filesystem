// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation

/// Decides which alias and symlink targets a recursive walk descends into, so that a link back up
/// the tree ends the walk instead of repeating it.
///
/// Paths are compared after `realpath`, which keeps `/private/var` where
/// `resolvingSymlinksInPath()` strips it.
struct AliasTargetGuard {
    private let rootPaths: [String]
    private var visited: Set<String>

    /// - Parameter roots: the directories the walk was asked for.
    init(roots: [URL]) {
        rootPaths = roots.map(Self.canonicalPath)
        visited = Set(rootPaths)
    }

    /// `true` the first time a target is seen. Never for a root, an ancestor of a root (a link to
    /// `/` would otherwise walk the disk), or a folder inside a root, which the walk reaches anyway.
    mutating func admit(_ target: URL) -> Bool {
        let path = Self.canonicalPath(target)

        for root in rootPaths where Self.isAncestor(path, of: root) || Self.isAncestor(root, of: path) {
            return false
        }

        return visited.insert(path).inserted
    }

    static func canonicalPath(_ url: URL) -> String {
        url.withUnsafeFileSystemRepresentation { pointer in
            guard let pointer, let resolved = realpath(pointer, nil) else {
                return url.standardizedFileURL.path
            }
            defer { free(resolved) }
            return String(cString: resolved)
        }
    }

    /// `true` when `path` equals `ancestor` or lies beneath it.
    static func isAncestor(_ ancestor: String, of path: String) -> Bool {
        path == ancestor || path.hasPrefix(ancestor == "/" ? "/" : ancestor + "/")
    }
}
