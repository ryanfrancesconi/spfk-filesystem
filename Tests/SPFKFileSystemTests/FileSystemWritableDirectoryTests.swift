// Copyright Ryan Francesconi. All Rights Reserved.

import Foundation
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKFileSystem

@Suite(.tags(.file, .cacheLocation))
final class FileSystemWritableDirectoryTests: BinTestCase {
    private let fm = FileManager.default

    @Test func anAbsentDirectoryIsCreatedWithItsParents() throws {
        let url = bin.appendingPathComponent("a/b/c", isDirectory: true)

        try FileSystem.ensureWritableDirectory(at: url)

        #expect(url.isDirectory)
    }

    @Test func anExistingWritableDirectoryIsAccepted() throws {
        try fm.createDirectory(at: bin.appendingPathComponent("Existing"), withIntermediateDirectories: true)

        try FileSystem.ensureWritableDirectory(at: bin.appendingPathComponent("Existing"))
    }

    @Test func aFileInItsPlaceIsRefused() throws {
        let url = bin.appendingPathComponent("File")
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        try Data("not a directory".utf8).write(to: url)

        #expect(throws: (any Error).self) {
            try FileSystem.ensureWritableDirectory(at: url)
        }
    }

    @Test func anExistingReadOnlyDirectoryIsRefused() throws {
        let url = bin.appendingPathComponent("ReadOnly")
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: url.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }

        #expect(throws: CocoaError.self) {
            try FileSystem.ensureWritableDirectory(at: url)
        }
    }

    @Test func aDirectoryThatCannotBeCreatedIsRefused() throws {
        let parent = bin.appendingPathComponent("Locked")
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: parent.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: parent.path) }

        #expect(throws: (any Error).self) {
            try FileSystem.ensureWritableDirectory(at: parent.appendingPathComponent("Child"))
        }
    }
}
