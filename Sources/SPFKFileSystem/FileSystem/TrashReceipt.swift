// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation

/// Where a set of trashed files currently sit in the Trash, keyed by their original location.
///
/// **Mutable because the location is not stable.** A file re-trashed while a file of the same name
/// is already in the Trash gets a timestamp appended, so a redo cannot know in advance where its
/// own undo will have to look. The undo engine registers the inverse action *before* the handler
/// runs, so a redo has no way to hand a freshly computed value back into an already-registered
/// undo — updating this shared reference is the only channel.
@MainActor
public final class TrashReceipt {
    public private(set) var trashURLs: [URL: URL]

    public init(trashURLs: [URL: URL]) {
        self.trashURLs = trashURLs
    }

    public func update(_ trashURLs: [URL: URL]) {
        self.trashURLs = trashURLs
    }
}
