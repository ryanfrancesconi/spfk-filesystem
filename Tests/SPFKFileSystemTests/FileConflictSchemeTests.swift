// Copyright Ryan Francesconi. All Rights Reserved.

import Foundation
import SPFKBase
import Testing

@testable import SPFKFileSystem

struct FileConflictSchemeTests {
    // MARK: - init?(displayName:)

    @Test func initFromOverwriteDisplayName() {
        #expect(FileConflictScheme(displayName: FileConflictScheme.overwrite.displayName) == .overwrite)
    }

    @Test func initFromUniqueDisplayName() {
        #expect(FileConflictScheme(displayName: FileConflictScheme.unique.displayName) == .unique)
    }

    @Test func initFromErrorDisplayName() {
        #expect(FileConflictScheme(displayName: FileConflictScheme.error.displayName) == .error)
    }

    @Test func initFromUnknownDisplayNameReturnsNil() {
        #expect(FileConflictScheme(displayName: "Unknown") == nil)
    }
}
