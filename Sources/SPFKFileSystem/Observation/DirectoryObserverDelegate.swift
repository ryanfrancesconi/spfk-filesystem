// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation

public protocol DirectoryObserverDelegate: AnyObject, Sendable {
    func handleObservation(event: DirectoryEvent) async
}
