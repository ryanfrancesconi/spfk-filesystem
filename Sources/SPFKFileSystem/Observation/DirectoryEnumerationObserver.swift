// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation

/// Observe this directory url and all its subdirectory children by sending a common event.
///
/// Be careful with this class and only establish on known directories as it will perform
/// a deep enumeration.
public final class DirectoryEnumerationObserver: Sendable {
    public let url: URL
    public let delegate: DirectoryEnumerationObserverDelegate

    let storage: ObservationData

    public init(url: URL, delegate: DirectoryEnumerationObserverDelegate) throws {
        storage = try ObservationData(url: url)

        self.url = url
        self.delegate = delegate
    }

    deinit {
        Log.debug("- { \(self) }")
    }

    public func start() async throws {
        guard await !storage.isObserving else { return }

        await stop()
        try await storage.start()
        await storage.update(delegate: self)
    }

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
