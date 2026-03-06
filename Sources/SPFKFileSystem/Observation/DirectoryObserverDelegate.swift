// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation

/// Delegate protocol for receiving low-level directory change events from ``DirectoryObserver``.
///
/// This is the internal delegate used by the kqueue-based observation system. Each
/// ``DirectoryObserver`` monitors a single directory and delivers individual ``DirectoryEvent``
/// values through this protocol.
///
/// **Available on all Apple platforms** (macOS, iOS, tvOS, watchOS).
///
/// For higher-level recursive observation, see ``DirectoryEnumerationObserverDelegate`` which
/// delivers batched events from ``DirectoryEnumerationObserver`` or ``FSEventsDirectoryObserver``.
///
/// - SeeAlso: ``DirectoryEnumerationObserverDelegate``
public protocol DirectoryObserverDelegate: AnyObject, Sendable {
    /// Called when a directory change is detected after write stabilization.
    /// - Parameter event: The change event describing added or removed files.
    func handleObservation(event: DirectoryEvent) async
}
