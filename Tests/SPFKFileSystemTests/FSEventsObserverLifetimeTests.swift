// Copyright Ryan Francesconi. All Rights Reserved.

#if os(macOS)
    import Foundation
    @testable import SPFKFileSystem
    import Testing

    /// An observer released without `stop()` must not leave its stream reading freed memory: the
    /// next event in a watched directory has to be delivered to nothing.
    @Suite(.serialized)
    struct FSEventsObserverLifetimeTests {
        private final class ModificationDelegate: FileModificationObserverDelegate {
            func fileModificationObserver(didDetectModifications _: [URL: FileModificationKind]) async {}
        }

        private final class DirectoryDelegate: DirectoryEnumerationObserverDelegate {
            func directoryUpdated(events _: Set<DirectoryEvent>) async throws {}
        }

        private static func makeDirectory() throws -> URL {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("fsevents-lifetime-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        /// Same size as the observers' callback context, so these land in the freed context's
        /// memory and a stream still reading it finds junk where its weak reference was.
        private final class Filler {
            let junk = Int(bitPattern: 0x0100_0000_0300_0010)
        }

        private static func reuseFreedMemory() -> [Filler] {
            (0 ..< 50000).map { _ in Filler() }
        }

        /// Written by another process, since `FileModificationObserver` ignores this one's own changes.
        private static func touchExternally(_ url: URL) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/touch")
            process.arguments = [url.path]
            try process.run()
            process.waitUntilExit()
        }

        @Test func aFileModificationObserverReleasedWithoutStoppingIgnoresLaterEvents() async throws {
            let directory = try Self.makeDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }

            let file = directory.appendingPathComponent("tracked.txt")
            try Data("a".utf8).write(to: file)

            let delegate = ModificationDelegate()
            weak var released: FileModificationObserver?

            do {
                let observer = FileModificationObserver(
                    trackedFiles: [file: FileModificationState(url: file)],
                    delegate: delegate,
                    latency: 0.05
                )
                await observer.start()
                released = observer
            }

            #expect(released == nil)
            var filler: [[Filler]] = []

            for _ in 0 ..< 5 {
                filler.append(Self.reuseFreedMemory())
                try Self.touchExternally(file)
                try await Task.sleep(for: .milliseconds(200))
            }

            withExtendedLifetime(filler) {}
        }

        @Test func aDirectoryObserverReleasedWithoutStoppingIgnoresLaterEvents() async throws {
            let directory = try Self.makeDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }

            let delegate = DirectoryDelegate()
            weak var released: FSEventsDirectoryObserver?

            do {
                let observer = try FSEventsDirectoryObserver(url: directory, delegate: delegate, latency: 0.05)
                await observer.start()
                released = observer
            }

            #expect(released == nil)
            var filler: [[Filler]] = []

            for index in 0 ..< 5 {
                filler.append(Self.reuseFreedMemory())
                try Self.touchExternally(directory.appendingPathComponent("\(index).txt"))
                try await Task.sleep(for: .milliseconds(200))
            }

            withExtendedLifetime(filler) {}
        }
    }
#endif
