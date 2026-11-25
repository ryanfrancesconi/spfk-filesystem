// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation
import SPFKBase
@testable import SPFKFileSystem
import SPFKTesting
import Testing

@Suite(.tags(.file))
final class OriginalsStoreTests: BinTestCase {
    private lazy var store = OriginalsStore(root: bin.appendingPathComponent("Originals"), product: "test", productIdentifier: "com.test")

    private func file(_ name: String = "kick.wav", contents: String = "original") throws -> URL {
        let folder = bin.appendingPathComponent("Files", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    private func contents(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Keep

    @Test func aKeptOriginalIsFoundForItsFile() throws {
        let url = try file()

        let kept = try #require(try store.keep(url))

        #expect(store.original(for: url) == kept)
        #expect(try contents(kept.url) == "original")
        #expect(kept.url.pathExtension == "wav")

        let record = try store.record(of: kept)
        #expect(record.filename == "kick.wav")
        #expect(record.path == url.path)
        #expect(record.size == 8)
        #expect(record.product == "com.test")
        #expect(record.renders.isEmpty)
    }

    @Test func aSecondKeepKeepsNothingAndLeavesTheFirstOriginal() throws {
        let url = try file()
        let first = try #require(try store.keep(url))
        try Data("rendered".utf8).write(to: url)

        #expect(try store.keep(url) == nil)
        #expect(try contents(first.url) == "original")
        #expect(store.total().count == 1)
    }

    @Test func theFileIsMarkedAndItsOriginalIsNot() throws {
        let url = try file()

        let kept = try #require(try store.keep(url))

        #expect(try FileXattrs.value(store.attributeName, of: url) == Data(kept.id.uuidString.utf8))
        #expect(try FileXattrs.value(store.attributeName, of: kept.url) == nil)
    }

    /// A copy written as a new file drops every product's mark and keeps the file's other attributes.
    @Test(.tags(.renameOrganize)) func removingMarksLeavesACopyWithNoOriginal() throws {
        let url = try file()
        let other = OriginalsStore(root: bin.appendingPathComponent("Other"), product: "other")
        _ = try store.keep(url)
        _ = try other.keep(url)
        try url.setExtendedAttribute(name: "com.example.keep", value: Data("x".utf8))

        try OriginalsStore.removeMarks(from: url)

        #expect(store.original(for: url) == nil)
        #expect(other.original(for: url) == nil)
        #expect(try FileXattrs.value("com.example.keep", of: url) == Data("x".utf8))
    }

    @Test func removingMarksFromAnUnmarkedFileDoesNothing() throws {
        try OriginalsStore.removeMarks(from: try file())
    }

    @Test func keepingLeavesTheModificationDateAlone() throws {
        let url = try file()
        let date = Date(timeIntervalSince1970: 1_000_000_000)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)

        _ = try store.keep(url)

        let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        #expect(modified == date)
    }

    @Test func aFailedCopyLeavesNothingBehind() throws {
        let url = try file()
        let root = bin.appendingPathComponent("ReadOnly", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path) }
        let readOnly = OriginalsStore(root: root, product: "test")

        #expect(throws: (any Error).self) { try readOnly.keep(url) }

        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        #expect(try FileXattrs.value(readOnly.attributeName, of: url) == nil)
    }

    /// The mark of an original that is gone would otherwise ride the copy into the store.
    @Test func aStaleMarkIsReplacedAndNotCopiedIntoTheOriginal() throws {
        let url = try file()
        try FileXattrs.set(store.attributeName, value: Data(UUID().uuidString.utf8), on: url)

        let kept = try #require(try store.keep(url))

        #expect(try FileXattrs.value(store.attributeName, of: kept.url) == nil)
        #expect(store.original(for: url) == kept)
    }

    @Test func anOriginalIsFoundAfterTheFilesExtensionChanges() throws {
        let url = try file("kick.wav")
        let kept = try #require(try store.keep(url))
        let renamed = url.deletingPathExtension().appendingPathExtension("aif")

        try FileManager.default.moveItem(at: url, to: renamed)

        #expect(store.original(for: renamed) == kept)
    }

    // MARK: - Discard

    @Test func discardRemovesTheOriginalItsRecordAndTheMark() throws {
        let url = try file()
        let kept = try #require(try store.keep(url))

        store.discard(kept, unmarking: url)

        #expect(!FileManager.default.fileExists(atPath: kept.url.path))
        #expect(!FileManager.default.fileExists(atPath: kept.recordURL.path))
        #expect(try FileXattrs.value(store.attributeName, of: url) == nil)
    }

    // MARK: - Replace

    @Test func replaceKeepsSwapsAndNotesInThatOrder() throws {
        let url = try file()
        let render = try file(".render.wav", contents: "rendered")

        try OriginalsStore.replace(url, with: render, kinds: ["trim"], keeping: store)

        let kept = try #require(store.original(for: url))
        #expect(try contents(kept.url) == "original")
        #expect(try contents(url) == "rendered")
        #expect(try store.record(of: kept).renders.map(\.kinds) == [["trim"]])
    }

    @Test func aSecondReplaceNotesAgainAndKeepsNothingMore() throws {
        let url = try file()
        try OriginalsStore.replace(url, with: try file(".r1.wav", contents: "one"), kinds: ["trim"], keeping: store)
        try OriginalsStore.replace(url, with: try file(".r2.wav", contents: "two"), kinds: ["fade", "trim"], keeping: store)

        let kept = try #require(store.original(for: url))
        #expect(try contents(kept.url) == "original")
        #expect(try store.record(of: kept).renders.map(\.kinds) == [["trim"], ["fade", "trim"]])
        #expect(try store.record(of: kept).renderedKinds == ["trim", "fade"])
        #expect(store.total().count == 1)
    }

    @Test func aFailedSwapDiscardsTheOriginalItKept() throws {
        let url = try file()
        let missing = bin.appendingPathComponent(".missing.wav")

        #expect(throws: (any Error).self) {
            try OriginalsStore.replace(url, with: missing, kinds: ["trim"], keeping: store)
        }

        #expect(store.original(for: url) == nil)
        #expect(store.total().count == 0)
        #expect(try contents(url) == "original")
    }

    @Test func replaceWithoutAStoreOnlySwaps() throws {
        let url = try file()
        let render = try file(".render.wav", contents: "rendered")

        try OriginalsStore.replace(url, with: render, kinds: ["trim"], keeping: nil)

        #expect(try contents(url) == "rendered")
        #expect(store.original(for: url) == nil)
    }

    // MARK: - The mark travels

    @Test func theMarkFollowsARenameAndAReplace() throws {
        let url = try file()
        let kept = try #require(try store.keep(url))
        let renamed = url.deletingLastPathComponent().appendingPathComponent("snare.wav")
        try FileManager.default.moveItem(at: url, to: renamed)

        _ = try FileManager.default.replaceItemAt(renamed, withItemAt: try file(".tags.wav", contents: "tagged"))

        #expect(store.original(for: renamed) == kept)
    }

    @Test(.tags(.renameOrganize)) func theMarkFollowsAMoveIntoAnotherFolder() throws {
        let url = try file()
        let kept = try #require(try store.keep(url))
        let folder = url.deletingLastPathComponent().appendingPathComponent("2026/05", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let moved = folder.appendingPathComponent("2026-05-24 kick.wav")

        try FileManager.default.moveItem(at: url, to: moved)

        #expect(store.original(for: moved) == kept)
    }

    @Test func aCopyOfTheFileSharesItsOriginal() throws {
        let url = try file()
        let kept = try #require(try store.keep(url))
        let copy = url.deletingLastPathComponent().appendingPathComponent("kick copy.wav")

        try FileManager.default.copyItem(at: url, to: copy)

        #expect(store.original(for: copy) == kept)
        #expect(try store.keep(copy) == nil)
    }

    // MARK: - Records

    @Test func noteRenderIsANoOpWithoutAnOriginal() throws {
        let url = try file()

        try store.noteRender(of: url, kinds: ["trim"])

        #expect(store.total().count == 0)
    }

    @Test func aRecordWrittenWithoutRendersOrWithUnknownKeysStillReads() throws {
        let url = try file()
        let kept = try #require(try store.keep(url))
        let json = """
        {"version": 2, "id": "\(kept.id.uuidString)", "filename": "kick.wav", "path": "/x/kick.wav",
         "size": 8, "keptDate": "2026-11-17T10:00:00Z", "product": "com.test", "chain": []}
        """
        try Data(json.utf8).write(to: kept.recordURL)

        try store.noteRender(of: url, kinds: ["reverse"])

        let record = try store.record(of: kept)
        #expect(record.version == 2)
        #expect(record.renders.map(\.kinds) == [["reverse"]])
    }

    @Test func clearRendersEmptiesTheRecordAndKeepsTheOriginal() throws {
        let url = try file()
        try OriginalsStore.replace(url, with: try file(".r.wav", contents: "r"), kinds: ["trim"], keeping: store)
        let kept = try #require(store.original(for: url))

        try store.clearRenders(of: kept)

        #expect(try store.record(of: kept).renders.isEmpty)
        #expect(store.original(for: url) == kept)
    }

    // MARK: - Space

    @Test func costCountsOnlyTheFilesWithoutAnOriginal() throws {
        let kept = try file("a.wav", contents: "12345")
        _ = try store.keep(kept)
        let fresh = try file("b.wav", contents: "123")

        let cost = store.cost(toKeep: [kept, fresh])

        #expect(cost.count == 1)
        #expect(cost.bytes == 3)
    }

    @Test func totalAndRemoveAll() throws {
        _ = try store.keep(try file("a.wav", contents: "12345"))
        _ = try store.keep(try file("b.wav", contents: "123"))

        let total = store.total()
        #expect(total.count == 2)
        #expect(total.bytes > 8)

        try store.removeAll()

        #expect(store.total().count == 0)
        #expect(FileManager.default.fileExists(atPath: store.root.path))
    }

    @Test func aFileTheStoreCanCloneNeedsNoRoom() throws {
        let url = try file()
        try FileManager.default.createDirectory(at: store.root, withIntermediateDirectories: true)
        let values = try store.root.resourceValues(forKeys: [.volumeSupportsFileCloningKey])
        try #require(values.volumeSupportsFileCloning == true, "the temporary folder's volume cannot clone")

        #expect(store.hasRoom(for: [url]))
    }
}
