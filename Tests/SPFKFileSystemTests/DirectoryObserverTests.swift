import Foundation
import SPFKBase
import SPFKFileSystem
import SPFKTesting
import Testing

/// Actor-based delegate that collects directory events safely across concurrency boundaries.
actor TestEnumerationDelegate: DirectoryEnumerationObserverDelegate {
    var added = [URL]()
    var removed = [URL]()

    func directoryUpdated(events: Set<DirectoryEvent>) async throws {
        for event in events {
            switch event {
            case let .new(files: files, source: _):
                added += files

            case let .removed(files: files, source: _):
                removed += files
            }
        }
    }

    func reset() {
        added.removeAll()
        removed.removeAll()
    }
}

/// Actor-based delegate for low-level DirectoryObserver tests.
actor TestDirectoryDelegate: DirectoryObserverDelegate {
    var events = [DirectoryEvent]()

    func handleObservation(event: DirectoryEvent) async {
        events.append(event)
    }

    func reset() {
        events.removeAll()
    }
}

@Suite(.serialized)
final class DirectoryObserverTests: BinTestCase {
    private let testDelegate = TestEnumerationDelegate()

    @Test func addAndRemoveFiles() async throws {
        #expect(bin.exists)

        let observer = try DirectoryEnumerationObserver(url: bin, delegate: testDelegate)
        try await observer.start()

        let urls = TestBundleResources.shared.formats
        let newFiles = try copyToBin(urls: urls)

        try await wait(sec: 1)

        let addedCount = await testDelegate.added.count
        #expect(addedCount == urls.count)

        try newFiles.first?.delete()
        try await wait(sec: 1)

        let removedCount = await testDelegate.removed.count
        #expect(removedCount == 1)

        for newFile in newFiles {
            try? newFile.delete()
        }

        try await wait(sec: 1)

        let finalRemovedCount = await testDelegate.removed.count
        #expect(finalRemovedCount == urls.count)

        await observer.stop()
        await testDelegate.reset()
    }

    @Test func stopPreventsNotifications() async throws {
        #expect(bin.exists)

        let observer = try DirectoryEnumerationObserver(url: bin, delegate: testDelegate)
        try await observer.start()
        await observer.stop()

        // Copy files after stopping — should not be detected
        let urls = TestBundleResources.shared.formats
        _ = try copyToBin(urls: urls)

        try await wait(sec: 1)

        let addedCount = await testDelegate.added.count
        #expect(addedCount == 0, "No events should fire after stop()")

        await testDelegate.reset()
    }

    @Test func doubleStartIsIdempotent() async throws {
        #expect(bin.exists)

        let observer = try DirectoryEnumerationObserver(url: bin, delegate: testDelegate)
        try await observer.start()
        try await observer.start() // should not throw or duplicate observers

        let urls = [TestBundleResources.shared.formats.first!]
        _ = try copyToBin(urls: urls)

        try await wait(sec: 1)

        let addedCount = await testDelegate.added.count
        #expect(addedCount == 1, "Only one event per file, even after double start")

        await observer.stop()
        await testDelegate.reset()
    }

    @Test func subdirectoryObservation() async throws {
        #expect(bin.exists)

        let observer = try DirectoryEnumerationObserver(url: bin, delegate: testDelegate)

        // Create a subdirectory before starting observation
        let subdir = bin.appendingPathComponent("subdir")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)

        try await observer.start()

        // Copy a file into the subdirectory
        let source = TestBundleResources.shared.formats.first!
        let dest = subdir.appendingPathComponent(source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: dest)

        try await wait(sec: 1)

        let addedCount = await testDelegate.added.count
        #expect(addedCount >= 1, "Should detect file added in subdirectory")

        await observer.stop()
        await testDelegate.reset()
    }
}
