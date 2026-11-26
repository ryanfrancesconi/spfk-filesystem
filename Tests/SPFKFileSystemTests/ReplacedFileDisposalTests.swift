// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation
import SPFKTesting
import Testing

@testable import SPFKFileSystem

/// The file Revert to Original replaced reaches the Trash under its own name, leaving nothing behind.
@Suite(.tags(.file))
final class ReplacedFileDisposalTests {
    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("replaced-disposal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeBackup() throws -> URL {
        let backup = directory.appendingPathComponent(".\(UUID().uuidString)-shark.jpg")
        try Data("replaced".utf8).write(to: backup)
        return backup
    }

    @Test func theTrashedFileTakesTheFilesOwnName() throws {
        let landed = try #require(try ReplacedFileDisposal.trash.dispose(of: try makeBackup(), named: "shark.jpg"))
        defer { try? FileManager.default.removeItem(at: landed) }

        #expect(landed.lastPathComponent.hasPrefix("shark"))
        #expect(landed.pathExtension == "jpg")
        #expect(try String(contentsOf: landed, encoding: .utf8) == "replaced")
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test func deleteLeavesNothing() throws {
        #expect(try ReplacedFileDisposal.delete.dispose(of: try makeBackup(), named: "shark.jpg") == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
}
