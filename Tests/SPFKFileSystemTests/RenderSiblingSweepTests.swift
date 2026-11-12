// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation
import SPFKBase
@testable import SPFKFileSystem
import Testing

/// A crash mid-render leaves a hidden sibling behind; the sweep removes only those, and only old ones.
final class RenderSiblingSweepTests {
    private let directory: URL
    private let launch = Date()

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("render-sibling-sweep-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    private func file(_ name: String, modified: Date) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data([1]).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        return url
    }

    private var leftover: String { ".\(UUID().uuidString)-photo.jpg" }

    @Test func aRenderSiblingIsNamedSoTheSweepFindsIt() {
        let sibling = URL(fileURLWithPath: "/Photos/photo.jpg").renderSiblingURL()
        #expect(URL.isRenderSiblingName(sibling.lastPathComponent))
        #expect(sibling.deletingLastPathComponent().path == "/Photos")
    }

    @Test func anOldLeftoverIsRemoved() throws {
        let url = try file(leftover, modified: .distantPast)

        URL.removeStaleRenderSiblings(in: directory, olderThan: launch)

        #expect(!url.exists)
    }

    /// One this process may still be writing.
    @Test func aNewLeftoverIsKept() throws {
        let url = try file(leftover, modified: launch.addingTimeInterval(1))

        URL.removeStaleRenderSiblings(in: directory, olderThan: launch)

        #expect(url.exists)
    }

    @Test func anOrdinaryFileIsKept() throws {
        let url = try file("photo.jpg", modified: .distantPast)

        URL.removeStaleRenderSiblings(in: directory, olderThan: launch)

        #expect(url.exists)
    }

    @Test func aVisibleFileNamedLikeALeftoverIsKept() throws {
        let url = try file("\(UUID().uuidString)-photo.jpg", modified: .distantPast)

        URL.removeStaleRenderSiblings(in: directory, olderThan: launch)

        #expect(url.exists)
    }
}
