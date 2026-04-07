// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

#if os(macOS) && !targetEnvironment(macCatalyst)
    import Foundation

    /// Utilities for resolving security-scoped bookmark data into usable URLs.
    ///
    /// **macOS only** (`#if os(macOS) && !targetEnvironment(macCatalyst)`).
    ///
    /// Security-scoped access for each URL is acquired lazily at the point of I/O via
    /// `URL.withSecurityScopedAccess`. This type handles only bookmark resolution —
    /// there is no long-lived token registry.
    public enum SecureURLRegistry {
        /// Resolves bookmark data into a security-scoped URL without starting access.
        ///
        /// The underlying system call (`URL(resolvingBookmarkData:options:bookmarkDataIsStale:)`)
        /// is thread-safe and can be called concurrently from multiple callers.
        ///
        /// - Parameter data: The security-scoped bookmark data to resolve.
        /// - Returns: A tuple of the resolved URL and whether the bookmark was stale.
        /// - Throws: If the bookmark cannot be resolved.
        public static func resolveBookmark(_ data: Data) throws -> (url: URL, isStale: Bool) {
            var isStale = false

            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                bookmarkDataIsStale: &isStale
            )

            return (url: url, isStale: isStale)
        }
    }
#endif
