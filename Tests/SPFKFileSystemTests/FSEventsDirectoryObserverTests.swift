#if os(macOS)
    import Foundation
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
        private let testDelegate = FSEventsTestDelegate()

        @Test func fileCreationDetected() async throws {
            #expect(bin.exists)

            let observer = try FSEventsDirectoryObserver(
                url: bin,
                delegate: testDelegate
            )
            await observer.start()

            // Create files directly to avoid test bundle resource issues
            let fileCount = 3
            for i in 0 ..< fileCount {
                let fileURL = bin.appendingPathComponent("created_\(i).txt")
                try "content \(i)".write(to: fileURL, atomically: true, encoding: .utf8)
            }

            try await wait(sec: 2)

            let addedCount = await testDelegate.added.count
            #expect(addedCount == fileCount, "Should detect all added files")

            await observer.stop()
            await testDelegate.reset()
        }

        @Test func fileDeletionDetected() async throws {
            #expect(bin.exists)

            // Pre-populate bin with a file
            let fileURL = bin.appendingPathComponent("to_delete.txt")
            try "content".write(to: fileURL, atomically: true, encoding: .utf8)

            let observer = try FSEventsDirectoryObserver(
                url: bin,
                delegate: testDelegate
            )
            await observer.start()

            // Delete the file
            try FileManager.default.removeItem(at: fileURL)

            try await wait(sec: 2)

            let removedCount = await testDelegate.removed.count
            #expect(removedCount >= 1, "Should detect deleted file")

            await observer.stop()
            await testDelegate.reset()
        }

        @Test func subdirectoryFileDetected() async throws {
            #expect(bin.exists)

            let observer = try FSEventsDirectoryObserver(
                url: bin,
                delegate: testDelegate
            )
            await observer.start()

            // Create a subdirectory and write a file into it
            let subdir = bin.appendingPathComponent("subdir")
            try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)

            let fileURL = subdir.appendingPathComponent("nested.txt")
            try "nested content".write(to: fileURL, atomically: true, encoding: .utf8)

            try await wait(sec: 2)

            let addedCount = await testDelegate.added.count
            // Should detect the subdirectory and/or the file within it
            #expect(addedCount >= 1, "Should detect file added in subdirectory")

            await observer.stop()
            await testDelegate.reset()
        }

        @Test func multipleRapidChangesCoalesced() async throws {
            #expect(bin.exists)

            let observer = try FSEventsDirectoryObserver(
                url: bin,
                delegate: testDelegate
            )
            await observer.start()

            // Create multiple files rapidly
            for i in 0 ..< 5 {
                let fileURL = bin.appendingPathComponent("rapid_\(i).txt")
                try "content \(i)".write(to: fileURL, atomically: true, encoding: .utf8)
            }

            try await wait(sec: 2)

            let addedCount = await testDelegate.added.count
            #expect(addedCount == 5, "Should detect all rapidly created files")

            await observer.stop()
            await testDelegate.reset()
        }

        @Test func stopPreventsNotifications() async throws {
            #expect(bin.exists)

            let observer = try FSEventsDirectoryObserver(
                url: bin,
                delegate: testDelegate
            )
            await observer.start()
            await observer.stop()

            // Create files after stopping
            for i in 0 ..< 3 {
                let fileURL = bin.appendingPathComponent("after_stop_\(i).txt")
                try "content".write(to: fileURL, atomically: true, encoding: .utf8)
            }

            try await wait(sec: 1)

            let addedCount = await testDelegate.added.count
            #expect(addedCount == 0, "No events should fire after stop()")

            await testDelegate.reset()
        }

        @Test func renameDetected() async throws {
            #expect(bin.exists)

            // Pre-populate with a file
            let originalURL = bin.appendingPathComponent("original.txt")
            try "content".write(to: originalURL, atomically: true, encoding: .utf8)

            let observer = try FSEventsDirectoryObserver(
                url: bin,
                delegate: testDelegate
            )
            await observer.start()

            // Rename the file
            let renamedURL = bin.appendingPathComponent("renamed.txt")
            try FileManager.default.moveItem(at: originalURL, to: renamedURL)

            try await wait(sec: 2)

            let addedCount = await testDelegate.added.count
            let removedCount = await testDelegate.removed.count

            // Rename should appear as a remove + add
            #expect(removedCount >= 1, "Should detect removal of original file")
            #expect(addedCount >= 1, "Should detect addition of renamed file")

            await observer.stop()
            await testDelegate.reset()
        }
    }
#endif
