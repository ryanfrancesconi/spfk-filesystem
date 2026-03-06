// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

#if os(macOS) && !targetEnvironment(macCatalyst)
    import Foundation

    /// A centralized place to store URL access to simplify matching start access with stop
    public actor SecureURLRegistry {
        public init() {}

        public private(set) var active = Set<URL>()
        public private(set) var stale = Set<URL>()
        public private(set) var errors = Set<URL>()

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

        /// To be called on app shutdown to release all security scoped URLs
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
