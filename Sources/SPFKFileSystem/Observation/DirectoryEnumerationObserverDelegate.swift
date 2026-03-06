// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation

public protocol DirectoryEnumerationObserverDelegate: AnyObject, Sendable {
    func directoryUpdated(events: Set<DirectoryEvent>) async throws
}
