import Foundation
import SPFKBase
import SPFKFileSystem
import SPFKTesting
import Testing

@Suite(.serialized)
final class DirectoryObserverActorTests: BinTestCase, @unchecked Sendable {
    @Test func invalidURLThrows() async throws {
        let fileURL = bin.appendingPathComponent("not_a_directory.txt")
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)

        #expect(throws: Error.self) {
            _ = try DirectoryObserver(url: fileURL)
        }
    }

    @Test func startAndDetectNewFile() async throws {
        #expect(bin.exists)

        let delegate = TestDirectoryDelegate()
        let observer = try DirectoryObserver(url: bin)
        await observer.setDelegate(delegate)
        try await observer.start()

        let source = TestBundleResources.shared.formats.first!
        _ = try copyToBin(urls: [source])

        try await wait(sec: 1)

        let events = await delegate.events
        let newEvents = events.filter(\.isNew)
        #expect(newEvents.count >= 1, "Should detect new file via DirectoryObserver directly")

        await observer.stop()
    }

    @Test func stopPreventsDetection() async throws {
        #expect(bin.exists)

        let delegate = TestDirectoryDelegate()
        let observer = try DirectoryObserver(url: bin)
        await observer.setDelegate(delegate)
        try await observer.start()
        await observer.stop()

        _ = try copyToBin(urls: [TestBundleResources.shared.formats.first!])

        try await wait(sec: 1)

        let events = await delegate.events
        #expect(events.isEmpty, "No events should fire after stop()")
    }
}
