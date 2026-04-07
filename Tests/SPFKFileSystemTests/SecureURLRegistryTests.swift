// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

#if os(macOS) && !targetEnvironment(macCatalyst)
    import Foundation
    import SPFKBase
    @testable import SPFKFileSystem
    import SPFKTesting
    import Testing

    /// Tests for ``SecureURLRegistry`` bookmark resolution.
    @Suite(.serialized)
    final class SecureURLRegistryTests: BinTestCase, @unchecked Sendable {
        // MARK: - resolveBookmark

        @Test func resolveBookmarkReturnsURL() throws {
            let url = try createTempFile()
            let bookmarkData = try url.bookmarkData(options: [.withSecurityScope])

            let result = try SecureURLRegistry.resolveBookmark(bookmarkData)

            #expect(result.url.resolvingSymlinksInPath() == url.resolvingSymlinksInPath())
            #expect(result.isStale == false)
        }

        @Test func resolveBookmarkWithInvalidDataThrows() throws {
            let bogusData = Data("not a bookmark".utf8)

            #expect(throws: (any Error).self) {
                try SecureURLRegistry.resolveBookmark(bogusData)
            }
        }
    }

    // MARK: - Helpers

    extension SecureURLRegistryTests {
        /// Creates a temporary file in the test bin directory and returns its URL.
        func createTempFile() throws -> URL {
            let url = bin.appendingPathComponent(UUID().uuidString, conformingTo: .data)
            try Data().write(to: url)
            return url
        }
    }
#endif
