// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

#if os(macOS) && !targetEnvironment(macCatalyst)
    import Foundation

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
        /// is called. If the bookmark is stale, the URL is also added to ``stale``.
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

            guard url.startAccessingSecurityScopedResource() else {
                errors.insert(url)

                let message = "startAccessingSecurityScopedResource failed for \(url.path)"

                throw NSError(
                    domain: NSURLErrorDomain, code: NSURLErrorCannotOpenFile, description: message
                )
            }

            active.insert(url)

            // Log.debug("Accessing", url.path)

            return (url: url, isStale: isStale)
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
