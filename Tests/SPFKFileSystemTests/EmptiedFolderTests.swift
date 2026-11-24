// Copyright Ryan Francesconi. All Rights Reserved.

#if os(macOS)

    import Foundation
    import SPFKBase
    import SPFKTesting
    import Testing

    @testable import SPFKFileSystem

    /// The folders a move leaves empty, and the ones it created, removed afterwards.
    @Suite(.tags(.file, .renameOrganize))
    struct EmptiedFolderTests {
        typealias Sandbox = FileCommandsTests.Sandbox

        static func make(_ path: String, in root: URL) throws -> URL {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url)
            return url
        }

        static func folder(_ path: String, in root: URL) throws -> URL {
            let url = root.appendingPathComponent(path, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        /// `root/a/b/x.jpg`, with `x.jpg` already moved away.
        static func emptiedTree(in dir: Sandbox) throws -> (root: URL, a: URL, b: URL, source: URL) {
            let root = try folder("root", in: dir.url)
            let source = try make("a/b/x.jpg", in: root)
            try FileManager.default.removeItem(at: source)
            return (root, root.appendingPathComponent("a"), root.appendingPathComponent("a/b"), source)
        }

        @Test func emptiedFoldersAreRemovedUpToButNotIncludingTheRoot() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let (root, a, _, source) = try Self.emptiedTree(in: dir)

            let removed = FileSystem.removeFoldersEmptied(byMoving: [source], within: root)

            #expect(removed.map(\.lastPathComponent) == ["b", "a"])
            #expect(!a.exists)
            #expect(root.exists)
        }

        @Test func aFolderHoldingOnlyDSStoreCountsAsEmpty() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let (root, a, _, source) = try Self.emptiedTree(in: dir)
            _ = try Self.make(".DS_Store", in: a)

            #expect(FileSystem.removeFoldersEmptied(byMoving: [source], within: root).count == 2)
            #expect(!a.exists)
        }

        @Test(arguments: [".hidden", "other.jpg"])
        func aFolderHoldingAnythingElseStays(_ name: String) throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let (root, a, b, source) = try Self.emptiedTree(in: dir)
            _ = try Self.make(name, in: a)

            #expect(FileSystem.removeFoldersEmptied(byMoving: [source], within: root).map(\.lastPathComponent) == ["b"])
            #expect(!b.exists)
            #expect(a.exists)
        }

        @Test func aSourceOutsideOrDirectlyInTheRootRemovesNothing() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let root = try Self.folder("root", in: dir.url)
            let outside = try Self.folder("elsewhere/deeper", in: dir.url)

            let removed = FileSystem.removeFoldersEmptied(
                byMoving: [outside.appendingPathComponent("x.jpg"), root.appendingPathComponent("y.jpg")],
                within: root
            )

            #expect(removed.isEmpty)
            #expect(outside.exists)
            #expect(root.exists)
        }

        @Test func createdFoldersAreRemovedChildrenFirstWhenEmpty() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let parent = try Self.folder("2024", in: dir.url)
            let child = try Self.folder("2024/2024-05-01", in: dir.url)

            #expect(FileSystem.removeEmptyFolders([parent, child]).map(\.lastPathComponent) == ["2024-05-01", "2024"])
            #expect(!parent.exists)
        }

        @Test func aCreatedParentHoldingAFileStays() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let parent = try Self.folder("2024", in: dir.url)
            let child = try Self.folder("2024/2024-05-01", in: dir.url)
            _ = try Self.make("2024/kept.jpg", in: dir.url)

            #expect(FileSystem.removeEmptyFolders([parent, child]).map(\.lastPathComponent) == ["2024-05-01"])
            #expect(parent.exists)
        }

        @Test func movedFoldersInverseSwapsCreatedAndRemoved() {
            let created = [URL(fileURLWithPath: "/r/2024")]
            let removed = [URL(fileURLWithPath: "/r/old")]
            let inverse = MovedFolders(created: created, removed: removed).inverse

            #expect(inverse.created == removed)
            #expect(inverse.removed == created)
        }

        @Test func movesAcrossFoldersIsTrueOnlyWhenAKeyChangesFolder() {
            let a = URL(fileURLWithPath: "/r/a.jpg")

            #expect(![a: URL(fileURLWithPath: "/r/b.jpg")].movesAcrossFolders)
            #expect([a: URL(fileURLWithPath: "/r/b.jpg"), URL(fileURLWithPath: "/r/c.jpg"): URL(fileURLWithPath: "/r/2024/c.jpg")].movesAcrossFolders)
        }
    }

#endif
