#if os(macOS)
    import Foundation
    import SPFKBase
    import SPFKFileSystem
    import SPFKTesting
    import Testing

    /// Actor-based delegate that collects events for FSEvents observer tests.
    actor FSEventsTestDelegate: DirectoryEnumerationObserverDelegate {
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

    @Suite(.serialized)
    final class FSEventsDirectoryObserverTests: BinTestCase {
        @Test func fileCreationDetected() async throws {
            let testDelegate = FSEventsTestDelegate()
            let observeDir = createBin(suite: #function, in: bin)

            let observer = try FSEventsDirectoryObserver(url: observeDir, delegate: testDelegate)
            await observer.start()

            let fileCount = 3
            for i in 0 ..< fileCount {
                let fileURL = observeDir.appendingPathComponent("created_\(i).txt")
                try "content \(i)".write(to: fileURL, atomically: false, encoding: .utf8)
            }

            try await wait(sec: 2)

            let addedCount = await testDelegate.added.count
            #expect(addedCount == fileCount, "Should detect all added files")

            await observer.stop()
        }

        @Test func fileDeletionDetected() async throws {
            let testDelegate = FSEventsTestDelegate()
            let observeDir = createBin(suite: #function, in: bin)

            let fileURL = observeDir.appendingPathComponent("to_delete.txt")
            try "content".write(to: fileURL, atomically: false, encoding: .utf8)

            let observer = try FSEventsDirectoryObserver(url: observeDir, delegate: testDelegate)
            await observer.start()

            try FileManager.default.removeItem(at: fileURL)

            try await wait(sec: 2)

            let removedCount = await testDelegate.removed.count
            #expect(removedCount >= 1, "Should detect deleted file")

            await observer.stop()
        }

        @Test func subdirectoryFileDetected() async throws {
            let testDelegate = FSEventsTestDelegate()
            let observeDir = createBin(suite: #function, in: bin)

            let observer = try FSEventsDirectoryObserver(url: observeDir, delegate: testDelegate)
            await observer.start()

            let subdir = observeDir.appendingPathComponent("subdir")
            try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)

            let fileURL = subdir.appendingPathComponent("nested.txt")
            try "nested content".write(to: fileURL, atomically: false, encoding: .utf8)

            try await wait(sec: 2)

            let addedCount = await testDelegate.added.count
            #expect(addedCount >= 1, "Should detect file added in subdirectory")

            await observer.stop()
        }

        @Test func multipleRapidChangesCoalesced() async throws {
            let testDelegate = FSEventsTestDelegate()
            let observeDir = createBin(suite: #function, in: bin)

            let observer = try FSEventsDirectoryObserver(url: observeDir, delegate: testDelegate)
            await observer.start()

            for i in 0 ..< 5 {
                let fileURL = observeDir.appendingPathComponent("rapid_\(i).txt")
                try "content \(i)".write(to: fileURL, atomically: false, encoding: .utf8)
            }

            try await wait(sec: 2)

            let addedCount = await testDelegate.added.count
            #expect(addedCount == 5, "Should detect all rapidly created files")

            await observer.stop()
        }

        @Test func stopPreventsNotifications() async throws {
            let testDelegate = FSEventsTestDelegate()
            let observeDir = createBin(suite: #function, in: bin)

            let observer = try FSEventsDirectoryObserver(url: observeDir, delegate: testDelegate)
            await observer.start()
            await observer.stop()

            for i in 0 ..< 3 {
                let fileURL = observeDir.appendingPathComponent("after_stop_\(i).txt")
                try "content".write(to: fileURL, atomically: false, encoding: .utf8)
            }

            try await wait(sec: 1)

            let addedCount = await testDelegate.added.count
            #expect(addedCount == 0, "No events should fire after stop()")
        }

        @Test func renameDetected() async throws {
            let testDelegate = FSEventsTestDelegate()
            let observeDir = createBin(suite: #function, in: bin)

            let originalURL = observeDir.appendingPathComponent("original.txt")
            try "content".write(to: originalURL, atomically: false, encoding: .utf8)

            let observer = try FSEventsDirectoryObserver(url: observeDir, delegate: testDelegate)
            await observer.start()

            let renamedURL = observeDir.appendingPathComponent("renamed.txt")
            try FileManager.default.moveItem(at: originalURL, to: renamedURL)

            try await wait(sec: 2)

            let addedCount = await testDelegate.added.count
            let removedCount = await testDelegate.removed.count

            #expect(removedCount >= 1, "Should detect removal of original file")
            #expect(addedCount >= 1, "Should detect addition of renamed file")

            await observer.stop()
        }
    }
#endif
