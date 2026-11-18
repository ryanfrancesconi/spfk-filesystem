// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation

/// A file as it was before its first rendered save, held in an ``OriginalsStore``.
public struct KeptOriginal: Sendable, Hashable {
    public let id: UUID

    /// `<root>/<id>.<ext>`.
    public let url: URL

    /// `<root>/<id>.json`.
    public let recordURL: URL

    public init(id: UUID, url: URL, recordURL: URL) {
        self.id = id
        self.url = url
        self.recordURL = recordURL
    }
}
