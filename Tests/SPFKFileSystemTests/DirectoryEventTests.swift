import Foundation
import SPFKFileSystem
import Testing

@Suite
struct DirectoryEventTests {
    @Test func isNewProperty() {
        let newEvent = DirectoryEvent.new(files: [], source: URL(fileURLWithPath: "/tmp"))
        let removedEvent = DirectoryEvent.removed(files: [], source: URL(fileURLWithPath: "/tmp"))

        #expect(newEvent.isNew == true)
        #expect(removedEvent.isNew == false)
    }

    @Test func sourceProperty() {
        let source = URL(fileURLWithPath: "/tmp/test")
        let newEvent = DirectoryEvent.new(files: [], source: source)
        let removedEvent = DirectoryEvent.removed(files: [], source: source)

        #expect(newEvent.source == source)
        #expect(removedEvent.source == source)
    }

    @Test func filesProperty() {
        let files: Set<URL> = [
            URL(fileURLWithPath: "/tmp/a.txt"),
            URL(fileURLWithPath: "/tmp/b.txt"),
        ]
        let source = URL(fileURLWithPath: "/tmp")

        let newEvent = DirectoryEvent.new(files: files, source: source)
        let removedEvent = DirectoryEvent.removed(files: files, source: source)

        #expect(newEvent.files == files)
        #expect(removedEvent.files == files)
    }

    @Test func hashableConformance() {
        let source = URL(fileURLWithPath: "/tmp")
        let files: Set<URL> = [URL(fileURLWithPath: "/tmp/a.txt")]

        let event1 = DirectoryEvent.new(files: files, source: source)
        let event2 = DirectoryEvent.new(files: files, source: source)
        let event3 = DirectoryEvent.removed(files: files, source: source)

        #expect(event1 == event2)
        #expect(event1 != event3)

        let eventSet: Set<DirectoryEvent> = [event1, event2, event3]
        #expect(eventSet.count == 2, "Duplicate events should be deduplicated in a Set")
    }
}
