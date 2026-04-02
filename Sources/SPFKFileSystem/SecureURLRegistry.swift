// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

#if os(macOS) && !targetEnvironment(macCatalyst)
    import Foundation
    import SPFKBase

    /// Centralized registry for managing security-scoped URL access in sandboxed macOS apps.
    ///
    /// **macOS only** (`#if os(macOS) && !targetEnvironment(macCatalyst)`).
    ///
    /// Sandboxed apps must call `startAccessingSecurityScopedResource()` on URLs resolved
    /// from security-scoped bookmarks, and later `stopAccessingSecurityScopedResource()` to
    /// release the kernel resource. This actor tracks all active accesses so they can be
    /// released cleanly on app shutdown via ``releaseAll()``.
    ///
    /// Also tracks stale bookmarks (which need to be re-created) and URLs that failed to
    /// start access.
    public actor SecureURLRegistry {
        public init() {}

        /// URLs currently being accessed via `startAccessingSecurityScopedResource()`.
        public private(set) var active = Set<URL>()

        /// URLs whose bookmark data was marked as stale and should be re-created.
        public private(set) var stale = Set<URL>()

        /// URLs where `startAccessingSecurityScopedResource()` returned `false`.
        public private(set) var errors = Set<URL>()

        /// Resolves bookmark data into a security-scoped URL without starting access.
        ///
        /// This is `nonisolated` so it can run concurrently across multiple callers
        /// without hopping to the actor's executor. The underlying system call
        /// (`URL(resolvingBookmarkData:options:bookmarkDataIsStale:)`) is thread-safe.
        ///
        /// Call ``startAccessing(url:isStale:)`` afterward to begin security-scoped
        /// access and register the URL with this registry.
        ///
        /// - Parameter data: The security-scoped bookmark data to resolve.
        /// - Returns: A tuple of the resolved URL and whether the bookmark was stale.
        /// - Throws: If the bookmark cannot be resolved.
        public nonisolated func resolveBookmark(_ data: Data) throws -> (url: URL, isStale: Bool) {
            var isStale = false

            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                bookmarkDataIsStale: &isStale
            )

            return (url: url, isStale: isStale)
        }

        /// Begins security-scoped access for a previously resolved URL and registers it.
        ///
        /// If the URL is already in ``active``, returns immediately without calling
        /// `startAccessingSecurityScopedResource()` again — avoiding unbalanced reference counts.
        ///
        /// - Parameters:
        ///   - url: The resolved URL from ``resolveBookmark(_:)``.
        ///   - isStale: Whether the bookmark was stale.
        /// - Throws: If `startAccessingSecurityScopedResource()` returns `false`.
        public func startAccessing(url: URL, isStale: Bool) throws {
            if isStale {
                Log.error("bookmark for \(url.path) is stale")
                stale.insert(url)
            }

            // Skip if already accessing — each startAccessing call is reference-counted
            // and must be balanced by a stopAccessing call.
            if active.contains(url) {
                return
            }

            guard url.startAccessingSecurityScopedResource() else {
                errors.insert(url)

                let message = "startAccessingSecurityScopedResource failed for \(url.path)"

                throw NSError(
                    domain: NSURLErrorDomain, code: NSURLErrorCannotOpenFile, description: message
                )
            }

            active.insert(url)
        }

        /// Begins security-scoped access for a batch of previously resolved URLs in a single actor hop.
        ///
        /// Equivalent to calling ``startAccessing(url:isStale:)`` for each item, but avoids
        /// per-item actor hop overhead for large batches. Failures are logged individually
        /// and do not interrupt access for subsequent URLs in the batch.
        ///
        /// - Parameter resolved: Array of `(url, isStale)` tuples from ``resolveBookmark(_:)``.
        public func startAccessing(resolved: [(url: URL, isStale: Bool)]) {
            for item in resolved {
                do {
                    try startAccessing(url: item.url, isStale: item.isStale)
                } catch {
                    Log.error("startAccessing failed for \(item.url.lastPathComponent): \(error)")
                }
            }
        }

        /// Resolves bookmark data into a security-scoped URL and begins access.
        ///
        /// Convenience that calls ``resolveBookmark(_:)`` then ``startAccessing(url:isStale:)``.
        /// For bulk operations, call those two methods separately to allow concurrent resolution.
        @discardableResult
        public func create(resolvingBookmarkData data: Data) throws -> (url: URL, isStale: Bool) {
            let result = try resolveBookmark(data)
            try startAccessing(url: result.url, isStale: result.isStale)
            return result
        }

        /// Releases security-scoped access for a single URL.
        ///
        /// If the URL is in ``active``, `stopAccessingSecurityScopedResource()` is called
        /// and the URL is removed from all tracking sets. If the URL is not active, this
        /// method is a no-op.
        ///
        /// Use this to release access when a playlist or document is closed, rather than
        /// waiting for ``releaseAll()`` on app shutdown.
        ///
        /// - Parameter url: The URL to stop accessing.
        public func release(url: URL) {
            guard active.remove(url) != nil else { return }
            url.stopAccessingSecurityScopedResource()
            stale.remove(url)
            errors.remove(url)
        }

        /// Releases security-scoped access for a collection of URLs.
        ///
        /// Convenience method that calls ``release(url:)`` for each URL in the collection.
        ///
        /// - Parameter urls: The URLs to stop accessing.
        public func release(urls: some Collection<URL>) {
            for url in urls {
                release(url: url)
            }
        }

        /// Releases all security-scoped URL access and clears all tracking sets.
        ///
        /// Call this on app shutdown to ensure all kernel resources are freed.
        public func releaseAll() {
            Log.debug("Releasing", active.count, "security scoped urls,", stale.count, "stale")

            for item in active {
                item.stopAccessingSecurityScopedResource()
            }

            active.removeAll()
            stale.removeAll()
            errors.removeAll()
        }
    }
#endif
