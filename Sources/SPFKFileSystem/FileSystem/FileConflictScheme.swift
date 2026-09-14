// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation

/// What a write does when its output already exists.
public enum FileConflictScheme: Int, Codable, Hashable, Sendable, CaseIterable {
    /// delete the existing file
    case overwrite = 0

    /// rename the new file with a unique suffix such as _1
    case unique

    /// throws an error indicating the file exists
    case error

    public var displayName: String {
        switch self {
        case .overwrite: localized("Overwrite Files")
        case .error: localized("Show Errors")
        case .unique: localized("Rename Uniquely")
        }
    }

    public init?(displayName: String) {
        for item in Self.allCases where item.displayName == displayName {
            self = item
            return
        }

        return nil
    }
}
