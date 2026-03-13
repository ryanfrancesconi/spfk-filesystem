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

        /// Resolves bookmark data into a security-scoped URL and begins access.
        ///
        /// The resolved URL is tracked in ``active`` and will be released when ``releaseAll()``
        /// or ``release(url:)`` is called. If the bookmark is stale, the URL is also added
        /// to ``stale``.
        ///
        /// If the resolved URL is already in ``active``, the method returns immediately
        /// without calling `startAccessingSecurityScopedResource()` again, avoiding
        /// unbalanced reference counts.
        ///
        /// - Parameter data: The security-scoped bookmark data to resolve.
        /// - Returns: A tuple of the resolved URL and whether the bookmark was stale.
        /// - Throws: If the bookmark cannot be resolved or access cannot be started.
        @discardableResult
        public func create(resolvingBookmarkData data: Data) throws -> (url: URL, isStale: Bool) {
            var isStale = false

            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                Log.error("bookmark for \(url.path) is stale")
                stale.insert(url)
            }

            // Skip if already accessing — each startAccessing call is reference-counted
            // and must be balanced by a stopAccessing call.
            if active.contains(url) {
                return (url: url, isStale: isStale)
            }

            guard url.startAccessingSecurityScopedResource() else {
                errors.insert(url)

                let message = "startAccessingSecurityScopedResource failed for \(url.path)"

                throw NSError(
                    domain: NSURLErrorDomain, code: NSURLErrorCannotOpenFile, description: message
                )
            }

            active.insert(url)

            return (url: url, isStale: isStale)
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
