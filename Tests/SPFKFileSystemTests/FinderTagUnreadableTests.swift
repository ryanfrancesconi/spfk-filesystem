// Copyright Ryan Francesconi. All Rights Reserved.

#if os(macOS)
    import Darwin
    import Foundation
    import SPFKBase
    import SPFKTesting
    import Testing

    @testable import SPFKFileSystem

    /// A Finder tag attribute that will not decode is not the same as no tags, and is not
    /// overwritten as if it were.
    @Suite(.tags(.file))
    final class FinderTagUnreadableTests: BinTestCase {
        private let malformed = Data("not a property list".utf8)

        /// Written with a bare `setxattr`, the way another app would, so no tag code is involved.
        private func fileWithMalformedTags() throws -> URL {
            let url = bin.appendingPathComponent("malformed-tags.txt")
            try Data("x".utf8).write(to: url)

            let status = malformed.withUnsafeBytes { buffer in
                setxattr(url.path, URL.userTagsKey, buffer.baseAddress, buffer.count, 0, 0)
            }
            try #require(status == 0)
            return url
        }

        private func rawTagAttribute(of url: URL) -> Data? {
            let size = getxattr(url.path, URL.userTagsKey, nil, 0, 0, 0)
            guard size >= 0 else { return nil }
            var data = Data(count: size)
            _ = data.withUnsafeMutableBytes { getxattr(url.path, URL.userTagsKey, $0.baseAddress, size, 0, 0) }
            return data
        }

        @Test func anUnreadableAttributeIsReportedRatherThanReadAsNoTags() throws {
            deleteBinOnExit = true
            let url = try fileWithMalformedTags()

            #expect(throws: (any Error).self) {
                try url.readTagNames()
            }
        }

        @Test func aFileWithoutTagsReadsAsNoTags() throws {
            deleteBinOnExit = true
            let url = bin.appendingPathComponent("untagged.txt")
            try Data("x".utf8).write(to: url)

            #expect(try url.readTagNames().isEmpty)
        }

        @Test func writingTagsOverAnUnreadableAttributeIsRefused() throws {
            deleteBinOnExit = true
            let url = try fileWithMalformedTags()

            #expect(throws: (any Error).self) {
                try url.set(tagNames: ["Red\n6"])
            }
            #expect(rawTagAttribute(of: url) == malformed)
        }
    }
#endif
