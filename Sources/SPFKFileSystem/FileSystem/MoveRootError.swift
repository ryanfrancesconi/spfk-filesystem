// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation

/// Why a folder cannot be the root a run files its folders under.
public enum MoveRootError: LocalizedError, Hashable, Sendable {
    /// The folder is, or is inside, a bundle or a Photos library, whose layout belongs to its app.
    case insidePackage(URL)

    case notWritable(URL)

    case unreadable(URL)

    public var errorDescription: String? {
        switch self {
        case let .insidePackage(url):
            localized("\"\(url.lastPathComponent)\" is inside a package or a Photos library, so files can't be moved into it.")
        case let .notWritable(url):
            localized("\"\(url.lastPathComponent)\" can't be written to.")
        case let .unreadable(url):
            localized("The disk holding \"\(url.lastPathComponent)\" can't be read.")
        }
    }
}
