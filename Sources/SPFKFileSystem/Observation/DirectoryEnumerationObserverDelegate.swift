// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation

/// Delegate protocol for receiving batched directory change events from recursive observers.
///
/// This is the public-facing delegate for both recursive observation strategies:
///
/// - **kqueue** (cross-platform): ``DirectoryEnumerationObserver`` collects events from
///   multiple ``DirectoryObserver`` instances and delivers them as a debounced batch through
///   this protocol.
/// - **FSEvents** (macOS only): ``FSEventsDirectoryObserver`` delivers coalesced events
///   directly through this protocol with no intermediate layer.
///
/// **Available on all Apple platforms.** Implement this protocol to receive directory change
/// notifications regardless of which observation backend is in use.
public protocol DirectoryEnumerationObserverDelegate: AnyObject, Sendable {
    /// Called when one or more directory changes have been detected and debounced.
    /// - Parameter events: The set of ``DirectoryEvent`` values accumulated since the last delivery.
    func directoryUpdated(events: Set<DirectoryEvent>) async throws
}
