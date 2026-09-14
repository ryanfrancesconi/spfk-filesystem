// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation

extension FileSystem {
    /// Whether two URLs name the same file on disk, however each path is spelled.
    ///
    /// Compared by file identity, so a symlinked directory or a case difference on a
    /// case-insensitive volume still matches. A URL naming no file matches nothing.
    public static func isSameFile(_ lhs: URL, _ rhs: URL) -> Bool {
        guard let lhsID = fileIdentifier(of: lhs), let rhsID = fileIdentifier(of: rhs) else { return false }

        return lhsID.isEqual(rhsID)
    }

    private static func fileIdentifier(of url: URL) -> (any NSObjectProtocol)? {
        // A cached identifier survives the file being replaced at the same path.
        var url = url
        url.removeCachedResourceValue(forKey: .fileResourceIdentifierKey)

        return try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
    }
}
