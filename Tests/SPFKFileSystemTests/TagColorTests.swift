#if os(macOS)
    import AppKit
    import Foundation
import SPFKBase
    @testable import SPFKFileSystem
    import SPFKTesting
    import Testing

    @Suite(.serialized)
    class TagColorTests: BinTestCase {
        @Test func tagColors() async throws {
            deleteBinOnExit = false
            let url = try createFolder(named: #function)

            let tagColors: [TagColor] = [.red, .green, .orange, .yellow]

            try url.set(tagColors: tagColors)
            #expect(url.tagColors == tagColors)
        }

        @Test func customTags() async throws {
            deleteBinOnExit = false
            let url = try createFolder(named: #function)

            let tagNames = ["Hello1", "Hello2", TagColor.none.dataElement]

            try url.set(tagNames: tagNames)
            #expect(url.tagNames == tagNames)
        }

        @Test func removeAllTags() async throws {
            deleteBinOnExit = false
            let url = try createFolder(named: #function)

            let tagColors: [TagColor] = [.red, .green, .orange, .yellow]

            try url.set(tagColors: tagColors)
            #expect(url.tagColors == tagColors)

            try url.removeAllTags()
            #expect(url.tagColors == [])
        }

        @Test func tagColorsOnArray() async throws {
            deleteBinOnExit = false
            let url = try createFolder(named: #function)

            for i in 1 ..< 10 {
                _ = try createFolder(named: "folder\(i)", in: url)
            }

            let urls = url.directoryContents ?? []

            try urls.set(tagColors: TagColor.allCases)

            for url in urls {
                let colors = url.tagColors

                #expect(colors == TagColor.allCases)
            }
        }

        @Test func tagNSColor() async throws {
            let colors = TagColor.allCases.compactMap { $0.nsColor }

            #expect(colors.count == TagColor.allCases.count)

            Log.debug(TagColor.array)
        }
    }

    extension TagColorTests {
        func createFolder(named name: String, in directory: URL? = nil) throws -> URL {
            let directory = directory ?? bin

            let url = directory.appendingPathComponent(name, conformingTo: .folder)
            try? url.delete()

            if !url.exists { try url.createDirectory() }

            #expect(url.tagNames == [])

            return url
        }
    }
#endif
