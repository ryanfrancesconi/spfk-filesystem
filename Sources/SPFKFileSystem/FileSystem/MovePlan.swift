// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation
import SPFKBase

/// Where each file of a run goes, with its companions, decided before anything moves.
/// ``FileCommands/move(_:rollingBackOnFailure:)`` carries it out.
public struct MovePlan: Sendable, Equatable {
    /// A companion's move, made with its owner's.
    public struct CompanionMove: Sendable, Hashable {
        public let from: URL
        public let to: URL

        public init(from: URL, to: URL) {
            self.from = from
            self.to = to
        }
    }

    /// A file and its companions, which move together or not at all.
    public struct Group: Sendable, Hashable {
        public let source: URL
        public let destination: URL
        public let companions: [CompanionMove]

        public init(source: URL, destination: URL, companions: [CompanionMove] = []) {
            self.source = source
            self.destination = destination
            self.companions = companions
        }
    }

    public enum Entry: Sendable, Hashable {
        case move(Group)

        /// Already named and placed as the run would name and place it.
        case alreadyInPlace(URL)

        case skipped(URL, MoveSkipReason)

        public var source: URL {
            switch self {
            case let .move(group): group.source
            case let .alreadyInPlace(url): url
            case let .skipped(url, _): url
            }
        }
    }

    /// In the order the run lists its files.
    public var entries: [Entry]

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    public var groups: [Group] {
        entries.compactMap {
            guard case let .move(group) = $0 else { return nil }
            return group
        }
    }
}

/// Why a run leaves a file where it is.
public enum MoveSkipReason: Sendable, Hashable {
    case missing
    case locked
    case busy
    case sourceFolderNotWritable
    case insidePackage
    case otherVolume
    case emptyName
    case overByteCap

    /// Two of the file's companions would take the one name.
    case companionNameClash

    /// The destination is held by a file outside the run.
    case nameInUse(URL)

    /// Byte for byte the same as the earlier source taking the destination, so it stays.
    case duplicate(of: URL)

    public var message: String {
        switch self {
        case .missing:
            localized("The file can't be found.")
        case .locked:
            localized("The file is locked.")
        case .busy:
            localized("The file is being written.")
        case .sourceFolderNotWritable:
            localized("The folder holding the file can't be written to.")
        case .insidePackage:
            localized("The file is inside a package or a Photos library.")
        case .otherVolume:
            localized("The file is on a different disk from the destination folder.")
        case .emptyName:
            localized("The template gives the file an empty name.")
        case .overByteCap:
            localized("The new name is too long.")
        case .companionNameClash:
            localized("Two of the file's sidecars would take the same name.")
        case let .nameInUse(url):
            localized("An item named \"\(url.lastPathComponent)\" already exists in this location.")
        case let .duplicate(url):
            localized("An identical file, \"\(url.lastPathComponent)\", is already moving there.")
        }
    }
}

/// What ``FileCommands/move(_:rollingBackOnFailure:)`` did.
public struct FileMoves: Sendable {
    /// Each group's source → where it went. Companions are in ``companions``.
    public var moved: [URL: URL] = [:]

    /// Each moved companion → where it went.
    public var companions: [URL: URL] = [:]

    /// The folders the run created, parents before children.
    public var createdFolders: [URL] = []

    /// The first failure, when the run was not rolled back. Every group missing from ``moved`` is
    /// where it began.
    public var failure: (any Error)?

    /// The run's task was cancelled; ``failure`` is the `CancellationError`.
    public var wasCancelled: Bool {
        failure is CancellationError
    }

    public init(moved: [URL: URL] = [:], companions: [URL: URL] = [:], createdFolders: [URL] = [], failure: (any Error)? = nil) {
        self.moved = moved
        self.companions = companions
        self.createdFolders = createdFolders
        self.failure = failure
    }
}

/// The folders a move created and the ones it removed once emptied, so its undo can reverse both.
public struct MovedFolders: Sendable, Hashable {
    public var created: [URL]
    public var removed: [URL]

    public static let none = MovedFolders(created: [], removed: [])

    public init(created: [URL], removed: [URL]) {
        self.created = created
        self.removed = removed
    }

    /// The undo's view: what the run removed, the undo recreates, and the reverse.
    public var inverse: MovedFolders {
        MovedFolders(created: removed, removed: created)
    }
}

extension Dictionary where Key == URL, Value == URL {
    /// Any file in the mapping changes folder.
    public var movesAcrossFolders: Bool {
        contains {
            $0.key.deletingLastPathComponent().standardizedFileURL.path
                != $0.value.deletingLastPathComponent().standardizedFileURL.path
        }
    }
}
