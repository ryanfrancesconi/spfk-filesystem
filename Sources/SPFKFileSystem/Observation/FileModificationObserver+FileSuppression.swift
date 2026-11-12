// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

#if os(macOS)
    import Foundation

    extension FileModificationObserver {
        /// Ignores changes to `urls` while every other tracked file is still watched. Their cached state is
        /// left alone, so call ``refreshTrackedState(for:)`` once the app's own write is done.
        ///
        /// Nests per file: each call needs its own ``unsuppress(urls:)``.
        public func suppress(urls: Set<URL>) {
            for url in urls {
                suppressedFiles[url, default: 0] += 1
            }
        }

        /// Ends one ``suppress(urls:)`` for each of `urls`. Clamped at zero.
        public func unsuppress(urls: Set<URL>) {
            for url in urls {
                guard let count = suppressedFiles[url] else { continue }
                suppressedFiles[url] = count > 1 ? count - 1 : nil
            }
        }

        /// Re-reads the state of each tracked file among `urls` from disk, so the app's own write to it
        /// becomes the baseline the next event is compared against.
        public func refreshTrackedState(for urls: Set<URL>) {
            for url in urls where modificationStates[url] != nil {
                modificationStates[url] = FileModificationState(url: url)
            }
        }

        /// Whether changes to `url` are being ignored by ``suppress(urls:)``.
        public func isSuppressed(_ url: URL) -> Bool {
            suppressedFiles[url] != nil
        }
    }
#endif
