// Copyright Ryan Francesconi. All Rights Reserved.

import Foundation
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKFileSystem

@Suite(.tags(.file))
final class FileSystemIdentityTests: BinTestCase {
    private func makeFile(_ name: String, in directory: URL? = nil) throws -> URL {
        let url = (directory ?? bin).appending(component: name, directoryHint: .notDirectory)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(name.utf8).write(to: url)
        return url
    }

    @Test func aFileMatchesItselfThroughASymlinkedDirectory() throws {
        let real = bin.appending(component: "real", directoryHint: .isDirectory)
        let file = try makeFile("a.txt", in: real)

        let alias = bin.appending(component: "alias", directoryHint: .isDirectory)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: real)

        #expect(FileSystem.isSameFile(alias.appending(component: "a.txt", directoryHint: .notDirectory), file))
    }

    @Test func twoFilesWithTheSameContentsAreDifferentFiles() throws {
        let first = try makeFile("same.txt", in: bin.appending(component: "one", directoryHint: .isDirectory))
        let second = try makeFile("same.txt", in: bin.appending(component: "two", directoryHint: .isDirectory))

        #expect(!FileSystem.isSameFile(first, second))
    }

    @Test func aMissingFileMatchesNothing() {
        let missing = bin.appending(component: "missing.txt", directoryHint: .notDirectory)

        #expect(!FileSystem.isSameFile(missing, missing))
    }

    /// A URL that answered once still answers for whatever is at its path now.
    @Test func aPathNamesTheFileNowAtItNotTheOneMovedAway() throws {
        let path = try makeFile("replaced.txt")
        #expect(FileSystem.isSameFile(path, path))

        let moved = bin.appending(component: "moved.txt", directoryHint: .notDirectory)
        try FileManager.default.moveItem(at: path, to: moved)
        try Data("new".utf8).write(to: path)

        #expect(!FileSystem.isSameFile(path, moved))
    }
}
