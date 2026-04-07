// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

#if os(macOS) && !targetEnvironment(macCatalyst)
    import Foundation
    import SPFKBase
    @testable import SPFKFileSystem
    import SPFKTesting
    import Testing

    /// Tests for ``SecureURLRegistry`` tracking behavior.
    ///
    /// Outside a sandbox, `startAccessingSecurityScopedResource()` returns `true`
    /// and is a no-op, which lets us validate the registry's set management
    /// (active/stale/errors), duplicate-access guard, and release methods.
    @Suite(.serialized)
    final class SecureURLRegistryTests: BinTestCase, @unchecked Sendable {
        // MARK: - resolveBookmark

        @Test func resolveBookmarkReturnsURL() throws {
            let registry = SecureURLRegistry()
            let url = try createTempFile()
            let bookmarkData = try url.bookmarkData(options: [.withSecurityScope])

            let result = try registry.resolveBookmark(bookmarkData)

            #expect(result.url.resolvingSymlinksInPath() == url.resolvingSymlinksInPath())
            #expect(result.isStale == false)
        }

        @Test func resolveBookmarkWithInvalidDataThrows() throws {
            let registry = SecureURLRegistry()
            let bogusData = Data("not a bookmark".utf8)

            #expect(throws: (any Error).self) {
                try registry.resolveBookmark(bogusData)
            }
        }

        // MARK: - startAccessing

        @Test func startAccessingAddsToActive() async throws {
            let registry = SecureURLRegistry()
            let url = try createTempFile()
            let bookmarkData = try url.bookmarkData(options: [.withSecurityScope])

            let (resolvedURL, isStale) = try registry.resolveBookmark(bookmarkData)
            try await registry.startAccessing(url: resolvedURL, isStale: isStale)

            let active = await registry.active
            #expect(active.contains(resolvedURL))
        }

        @Test func startAccessingDeduplicates() async throws {
            let registry = SecureURLRegistry()
            let url = try createTempFile()
            let bookmarkData = try url.bookmarkData(options: [.withSecurityScope])

            let (resolvedURL, isStale) = try registry.resolveBookmark(bookmarkData)
            try await registry.startAccessing(url: resolvedURL, isStale: isStale)
            try await registry.startAccessing(url: resolvedURL, isStale: isStale)

            let active = await registry.active
            #expect(active.count == 1)
        }

        // MARK: - release(url:)

        @Test func releaseRemovesFromActive() async throws {
            let registry = SecureURLRegistry()
            let url = try createTempFile()
            let bookmarkData = try url.bookmarkData(options: [.withSecurityScope])

            let result = try registry.resolveBookmark(bookmarkData)
            try await registry.startAccessing(url: result.url, isStale: result.isStale)

            var active = await registry.active
            #expect(active.contains(result.url))

            await registry.release(url: result.url)
            active = await registry.active
            #expect(!active.contains(result.url))
            #expect(active.isEmpty)
        }

        @Test func releaseNonActiveURLIsNoOp() async {
            let registry = SecureURLRegistry()
            let url = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString)")

            await registry.release(url: url)

            let active = await registry.active
            #expect(active.isEmpty)
        }

        // MARK: - release(urls:)

        @Test func releaseBatchRemovesMultipleURLs() async throws {
            let registry = SecureURLRegistry()
            let url1 = try createTempFile()
            let url2 = try createTempFile()
            let bookmark1 = try url1.bookmarkData(options: [.withSecurityScope])
            let bookmark2 = try url2.bookmarkData(options: [.withSecurityScope])

            let result1 = try registry.resolveBookmark(bookmark1)
            let result2 = try registry.resolveBookmark(bookmark2)
            try await registry.startAccessing(url: result1.url, isStale: result1.isStale)
            try await registry.startAccessing(url: result2.url, isStale: result2.isStale)

            var active = await registry.active
            #expect(active.count == 2)

            await registry.release(urls: [result1.url, result2.url])
            active = await registry.active
            #expect(active.isEmpty)
        }

        // MARK: - releaseAll()

        @Test func releaseAllClearsAllSets() async throws {
            let registry = SecureURLRegistry()
            let url1 = try createTempFile()
            let url2 = try createTempFile()
            let bookmark1 = try url1.bookmarkData(options: [.withSecurityScope])
            let bookmark2 = try url2.bookmarkData(options: [.withSecurityScope])

            let result1 = try registry.resolveBookmark(bookmark1)
            let result2 = try registry.resolveBookmark(bookmark2)
            try await registry.startAccessing(url: result1.url, isStale: result1.isStale)
            try await registry.startAccessing(url: result2.url, isStale: result2.isStale)

            var active = await registry.active
            #expect(active.count == 2)

            await registry.releaseAll()
            active = await registry.active
            let stale = await registry.stale
            let errors = await registry.errors
            #expect(active.isEmpty)
            #expect(stale.isEmpty)
            #expect(errors.isEmpty)
        }

        @Test func releaseAllOnEmptyRegistryIsNoOp() async {
            let registry = SecureURLRegistry()

            await registry.releaseAll()

            let active = await registry.active
            #expect(active.isEmpty)
        }

        // MARK: - Re-access after release

        @Test func startAccessingAfterReleaseTracksAgain() async throws {
            let registry = SecureURLRegistry()
            let url = try createTempFile()
            let bookmarkData = try url.bookmarkData(options: [.withSecurityScope])

            let result = try registry.resolveBookmark(bookmarkData)
            try await registry.startAccessing(url: result.url, isStale: result.isStale)
            await registry.release(url: result.url)

            var active = await registry.active
            #expect(active.isEmpty)

            // Re-accessing after release should add it back
            try await registry.startAccessing(url: result.url, isStale: result.isStale)
            active = await registry.active
            #expect(active.contains(result.url))
            #expect(active.count == 1)
        }

        // MARK: - Multiple URLs isolation

        @Test func releasingOneURLDoesNotAffectOthers() async throws {
            let registry = SecureURLRegistry()
            let url1 = try createTempFile()
            let url2 = try createTempFile()
            let bookmark1 = try url1.bookmarkData(options: [.withSecurityScope])
            let bookmark2 = try url2.bookmarkData(options: [.withSecurityScope])

            let result1 = try registry.resolveBookmark(bookmark1)
            let result2 = try registry.resolveBookmark(bookmark2)
            try await registry.startAccessing(url: result1.url, isStale: result1.isStale)
            try await registry.startAccessing(url: result2.url, isStale: result2.isStale)

            await registry.release(url: result1.url)

            let active = await registry.active
            #expect(!active.contains(result1.url))
            #expect(active.contains(result2.url))
            #expect(active.count == 1)
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
