// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

#if os(macOS)
    import Foundation
    import SPFKBase
    @testable import SPFKFileSystem
    import Testing

    /// Per-file suppression, driven through the comparison `handleFSEvents` runs, since the stream
    /// delivers no events for the test process's own writes.
    @Suite
    final class FileModificationObserverFileSuppressionTests {
        private final class Recorder: FileModificationObserverDelegate {
            func fileModificationObserver(didDetectModifications modifications: [URL: FileModificationKind]) async {}
        }

        private let directory: URL
        private let recorder = Recorder()
        private let rendered: URL
        private let other: URL

        /// Keyed as the observer keys it, by the files' parent URL.
        private var watched: Set<URL> {
            [rendered.deletingLastPathComponent()]
        }

        /// A cached state the files on disk have moved on from, as a rewrite leaves it.
        private let stale = FileModificationState(
            contentModificationDate: .distantPast,
            attributeModificationDate: .distantPast
        )

        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("observer-file-suppression-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            rendered = directory.appendingPathComponent("rendered.jpg")
            other = directory.appendingPathComponent("other.jpg")

            try Data([1]).write(to: rendered)
            try Data([2]).write(to: other)
        }

        deinit {
            try? FileManager.default.removeItem(at: directory)
        }

        private func makeObserver() -> FileModificationObserver {
            FileModificationObserver(trackedFiles: [rendered: stale, other: stale], delegate: recorder)
        }

        @Test func aSuppressedFileIsSkippedWhileItsNeighborIsReported() async {
            let observer = makeObserver()

            await observer.suppress(urls: [rendered])

            let modifications = await observer.modifications(in: watched)

            #expect(Set(modifications.keys) == [other])
            #expect(await observer.trackedState(for: rendered) == stale)
        }

        @Test func aRefreshedFileReportsNothingOnceUnsuppressed() async {
            let observer = makeObserver()

            await observer.suppress(urls: [rendered])
            _ = await observer.modifications(in: watched)

            await observer.refreshTrackedState(for: [rendered])
            await observer.unsuppress(urls: [rendered])

            #expect(await observer.modifications(in: watched).isEmpty)
        }

        @Test func nestedSuppressionNeedsAsManyUnsuppressCalls() async {
            let observer = makeObserver()

            await observer.suppress(urls: [rendered])
            await observer.suppress(urls: [rendered])

            await observer.unsuppress(urls: [rendered])
            #expect(await observer.isSuppressed(rendered))
            #expect(await observer.modifications(in: watched).keys.contains(rendered) == false)

            await observer.unsuppress(urls: [rendered])
            #expect(await observer.isSuppressed(rendered) == false)
            #expect(await observer.modifications(in: watched).keys.contains(rendered))
        }

        @Test func refreshIgnoresAFileThatIsNotTracked() async {
            let observer = makeObserver()
            let untracked = directory.appendingPathComponent("untracked.jpg")

            await observer.refreshTrackedState(for: [untracked])

            #expect(await observer.trackedURLs == [rendered, other])
        }
    }
#endif
