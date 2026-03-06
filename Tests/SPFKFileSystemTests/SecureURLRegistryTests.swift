// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

#if os(macOS) && !targetEnvironment(macCatalyst)
    import Foundation
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
        // MARK: - create(resolvingBookmarkData:)

        @Test func createResolvesBookmarkAndTracksActive() async throws {
            let registry = SecureURLRegistry()
            let url = try createTempFile()
            let bookmarkData = try url.bookmarkData(options: [.withSecurityScope])

            let result = try await registry.create(resolvingBookmarkData: bookmarkData)

            // Bookmark resolution may resolve symlinks (e.g., /var → /private/var)
            #expect(result.url.resolvingSymlinksInPath() == url.resolvingSymlinksInPath())
            #expect(result.isStale == false)

            let active = await registry.active
            #expect(active.contains(result.url))
        }

        @Test func createWithInvalidDataThrows() async throws {
            let registry = SecureURLRegistry()
            let bogusData = Data("not a bookmark".utf8)

            await #expect(throws: (any Error).self) {
                try await registry.create(resolvingBookmarkData: bogusData)
            }
        }

        // MARK: - Duplicate access guard

        @Test func duplicateCreateSkipsSecondStartAccess() async throws {
            let registry = SecureURLRegistry()
            let url = try createTempFile()
            let bookmarkData = try url.bookmarkData(options: [.withSecurityScope])

            let result1 = try await registry.create(resolvingBookmarkData: bookmarkData)
            let result2 = try await registry.create(resolvingBookmarkData: bookmarkData)

            // Both should resolve to the same URL
            #expect(result1.url.path == result2.url.path)

            // Active set should contain exactly one entry for this URL
            let active = await registry.active
            #expect(active.count == 1)
        }

        // MARK: - release(url:)

        @Test func releaseRemovesFromActive() async throws {
            let registry = SecureURLRegistry()
            let url = try createTempFile()
            let bookmarkData = try url.bookmarkData(options: [.withSecurityScope])

            let result = try await registry.create(resolvingBookmarkData: bookmarkData)
            var active = await registry.active
            #expect(active.contains(result.url))

            await registry.release(url: result.url)
            active = await registry.active
            #expect(!active.contains(result.url))
            #expect(active.isEmpty)
        }

        @Test func releaseNonActiveURLIsNoOp() async throws {
            let registry = SecureURLRegistry()
            let url = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString)")

            // Should not crash or alter state
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

            let result1 = try await registry.create(resolvingBookmarkData: bookmark1)
            let result2 = try await registry.create(resolvingBookmarkData: bookmark2)

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

            try await registry.create(resolvingBookmarkData: bookmark1)
            try await registry.create(resolvingBookmarkData: bookmark2)

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

        @Test func releaseAllOnEmptyRegistryIsNoOp() async throws {
            let registry = SecureURLRegistry()

            // Should not crash
            await registry.releaseAll()

            let active = await registry.active
            #expect(active.isEmpty)
        }

        // MARK: - Re-create after release

        @Test func createAfterReleaseTracksAgain() async throws {
            let registry = SecureURLRegistry()
            let url = try createTempFile()
            let bookmarkData = try url.bookmarkData(options: [.withSecurityScope])

            let result1 = try await registry.create(resolvingBookmarkData: bookmarkData)
            await registry.release(url: result1.url)

            var active = await registry.active
            #expect(active.isEmpty)

            // Re-creating should add it back to active
            let result2 = try await registry.create(resolvingBookmarkData: bookmarkData)
            active = await registry.active
            #expect(active.contains(result2.url))
            #expect(active.count == 1)
        }

        // MARK: - Multiple URLs isolation

        @Test func releasingOneURLDoesNotAffectOthers() async throws {
            let registry = SecureURLRegistry()
            let url1 = try createTempFile()
            let url2 = try createTempFile()
            let bookmark1 = try url1.bookmarkData(options: [.withSecurityScope])
            let bookmark2 = try url2.bookmarkData(options: [.withSecurityScope])

            let result1 = try await registry.create(resolvingBookmarkData: bookmark1)
            let result2 = try await registry.create(resolvingBookmarkData: bookmark2)

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
