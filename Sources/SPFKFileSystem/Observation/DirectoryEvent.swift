// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation

/// Represents a change detected in a monitored directory.
///
/// Both the kqueue-based ``DirectoryObserver`` (cross-platform) and the FSEvents-based
/// ``FSEventsDirectoryObserver`` (macOS only) produce `DirectoryEvent` values, making this
/// the shared currency type for all observation strategies.
///
/// - ``new(files:source:)``: One or more files or directories were added.
/// - ``removed(files:source:)``: One or more files or directories were deleted.
///
/// A file rename appears as a paired `.removed` + `.new` event.
///
/// ## Source URL Behavior
///
/// The ``source`` URL differs by observation strategy:
/// - **kqueue** (``DirectoryObserver`` / ``DirectoryEnumerationObserver``): `source` is the
///   specific subdirectory where the change occurred.
/// - **FSEvents** (``FSEventsDirectoryObserver``): `source` is always the root observed URL,
///   since a single stream monitors the entire tree.
public enum DirectoryEvent: Hashable, Sendable {
    /// Files or directories were added to the observed location.
    case new(files: Set<URL>, source: URL)

    /// Files or directories were removed from the observed location.
    case removed(files: Set<URL>, source: URL)

    /// Whether this event represents newly added files.
    public var isNew: Bool {
        switch self {
        case .new: true
        case .removed: false
        }
    }

    /// The directory that was being observed when the change occurred.
    ///
    /// For kqueue observers, this is the specific subdirectory. For FSEvents, this is the root URL.
    public var source: URL {
        switch self {
        case let .new(files: _, source: source):
            source

        case let .removed(files: _, source: source):
            source
        }
    }

    /// The set of file or directory URLs that were added or removed.
    public var files: Set<URL> {
        switch self {
        case let .new(files: files, source: _):
            files

        case let .removed(files: files, source: _):
            files
        }
    }
}
