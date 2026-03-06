// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation

/// Cross-platform recursive directory observer using kqueue-based ``DirectoryObserver`` instances.
///
/// **Available on all Apple platforms** (macOS, iOS, tvOS, watchOS).
///
/// This class performs a deep enumeration of the target directory and creates one
/// ``DirectoryObserver`` per subdirectory, coordinated by ``ObservationData``. Events from
/// all subdirectories are collected, debounced (0.3s), and delivered as a batch through the
/// ``DirectoryEnumerationObserverDelegate`` protocol.
///
/// When new subdirectories are created, observation is automatically extended to them.
/// When subdirectories are deleted, their observers are cleaned up.
///
/// > Warning: Exercise caution when observing large directory trees — each subdirectory
/// > consumes one file descriptor and one `DispatchSource`. For large hierarchies on macOS,
/// > prefer ``FSEventsDirectoryObserver`` which uses a single `FSEventStream`.
///
/// ## Usage
///
/// ```swift
/// let observer = try DirectoryEnumerationObserver(url: rootURL, delegate: myDelegate)
/// try await observer.start()
/// // ... events delivered via myDelegate.directoryUpdated(events:) ...
/// await observer.stop()
/// ```
///
/// ## Platform Comparison
///
/// | | `DirectoryEnumerationObserver` | `FSEventsDirectoryObserver` |
/// |---|---|---|
/// | Platform | All Apple platforms | macOS only |
/// | Resources | 1 file descriptor per subdirectory | 1 FSEventStream total |
/// | Subdirectory handling | Manual (create/remove observers) | Automatic |
/// | Event source URL | Per-subdirectory | Root URL only |
public final class DirectoryEnumerationObserver: Sendable {
    /// The root directory URL being observed.
    public let url: URL

    /// The delegate receiving batched change events.
    public let delegate: DirectoryEnumerationObserverDelegate

    let storage: ObservationData

    /// Creates a new recursive directory observer.
    /// - Parameters:
    ///   - url: The root directory URL to observe recursively. Must be an existing directory.
    ///   - delegate: The delegate to receive batched ``DirectoryEvent`` notifications.
    /// - Throws: If the URL is not a directory.
    public init(url: URL, delegate: DirectoryEnumerationObserverDelegate) throws {
        storage = try ObservationData(url: url)

        self.url = url
        self.delegate = delegate
    }

    deinit {
        Log.debug("- { \(self) }")
    }

    /// Begins recursive observation by creating a ``DirectoryObserver`` for each subdirectory.
    ///
    /// Performs a deep enumeration to discover all subdirectories, then starts monitoring each one.
    /// Idempotent — calling `start()` while already observing is a no-op.
    public func start() async throws {
        guard await !storage.isObserving else { return }

        await stop()
        try await storage.start()
        await storage.update(delegate: self)
    }

    /// Stops all subdirectory observers and cleans up resources.
    public func stop() async {
        guard await storage.isObserving else { return }
        await storage.update(delegate: nil)
        await storage.stop()
    }
}

extension DirectoryEnumerationObserver: CustomStringConvertible {
    public var description: String {
        "DirectoryEnumerationObserver(url: \"\(url.path)\")"
    }
}

extension DirectoryEnumerationObserver: DirectoryEnumerationObserverDelegate {
    public func directoryUpdated(events: Set<DirectoryEvent>) async throws {
        try await delegate.directoryUpdated(events: events)
    }
}
