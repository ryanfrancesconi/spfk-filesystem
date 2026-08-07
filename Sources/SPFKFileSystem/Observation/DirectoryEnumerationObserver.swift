// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation
import SPFKBase

/// Cross-platform recursive directory observer using kqueue-based ``DirectoryObserver`` instances.
///
/// One ``DirectoryObserver`` per subdirectory, extended and cleaned up as the tree changes, with
/// events debounced into batches.
///
/// > Warning: Each subdirectory costs a file descriptor and a `DispatchSource`. Prefer
/// > ``FSEventsDirectoryObserver`` for a large tree — it uses one `FSEventStream`.
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
/// ## Event Delivery Latency
///
/// Events pass through several stages before reaching the delegate, each adding latency:
///
/// 1. **kqueue notification** — kernel delivers the initial directory-change signal (near-instant).
/// 2. **Stabilization polling** — ``DirectoryObserver`` polls file sizes every 0.25 s until they
///    are stable for 1 consecutive check (~0.25–0.5 s).
/// 3. **Event debounce** — ``ObservationData`` collects events from all subdirectory observers
///    and coalesces them over a 0.3 s window before delivering a batch.
///
/// **Typical total latency: ~0.8–1.0 s** from filesystem change to delegate callback.
/// When many files are written concurrently, stabilization may take additional poll cycles.
/// Tests observing this class should allow at least 2 s for events to arrive.
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
    public let url: URL

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
