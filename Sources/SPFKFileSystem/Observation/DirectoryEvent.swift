// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation

public enum DirectoryEvent: Hashable, Sendable {
    case new(files: Set<URL>, source: URL)
    case removed(files: Set<URL>, source: URL)

    public var isNew: Bool {
        switch self {
        case .new: true
        case .removed: false
        }
    }

    public var source: URL {
        switch self {
        case let .new(files: _, source: source):
            source

        case let .removed(files: _, source: source):
            source
        }
    }

    public var files: Set<URL> {
        switch self {
        case let .new(files: files, source: _):
            files

        case let .removed(files: files, source: _):
            files
        }
    }
}
