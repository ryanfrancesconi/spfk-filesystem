// Copyright Ryan Francesconi. All Rights Reserved.

import Foundation
import SPFKBase
import Testing

@testable import SPFKFileSystem

struct FileConflictSchemeTests {
    // MARK: - displayName

    @Test func overwriteDisplayName() {
        #expect(FileConflictScheme.overwrite.displayName == "Overwrite Files")
    }

    @Test func uniqueDisplayName() {
        #expect(FileConflictScheme.unique.displayName == "Rename Uniquely")
    }

    @Test func errorDisplayName() {
        #expect(FileConflictScheme.error.displayName == "Show Errors")
    }

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

    // MARK: - Codable

    @Test func codableRoundTripOverwrite() throws {
        let data = try JSONEncoder().encode(FileConflictScheme.overwrite)
        let decoded = try JSONDecoder().decode(FileConflictScheme.self, from: data)
        #expect(decoded == .overwrite)
    }

    @Test func codableRoundTripUnique() throws {
        let data = try JSONEncoder().encode(FileConflictScheme.unique)
        let decoded = try JSONDecoder().decode(FileConflictScheme.self, from: data)
        #expect(decoded == .unique)
    }

    @Test func codableRoundTripError() throws {
        let data = try JSONEncoder().encode(FileConflictScheme.error)
        let decoded = try JSONDecoder().decode(FileConflictScheme.self, from: data)
        #expect(decoded == .error)
    }
}
