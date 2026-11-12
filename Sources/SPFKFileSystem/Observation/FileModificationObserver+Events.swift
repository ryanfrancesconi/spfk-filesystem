// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

#if os(macOS)
    import CoreServices
    import Foundation
    import SPFKBase

    // MARK: - Event Handling

    extension FileModificationObserver {
        func handleFSEvents(paths: [String], flags: [FSEventStreamEventFlags]) {
            guard !isSuppressed else { return }

            // Determine which monitored directories are affected
            var affectedDirs = Set<URL>()

            for path in paths {
                let url = URL(fileURLWithPath: path)

                // The path could be either a file within a monitored directory
                // or the directory itself
                let parentDir = url.deletingLastPathComponent()
                let fileDir = url

                if directoryIndex[parentDir] != nil {
                    affectedDirs.insert(parentDir)
                }

                if directoryIndex[fileDir] != nil {
                    affectedDirs.insert(fileDir)
                }
            }

            guard affectedDirs.isNotEmpty else { return }

            let modifications = modifications(in: affectedDirs)

            for (fileURL, kind) in modifications where pendingModifications[fileURL] != .content {
                // A content change already implies re-reading everything, so it must not be
                // overwritten by an attribute change arriving in the same coalescing window.
                pendingModifications[fileURL] = kind
            }

            if modifications.isNotEmpty {
                scheduleFlush()
            }
        }

        /// Compares each tracked file in `directories` with its cached state, caching and returning each
        /// change. A suppressed file is skipped and keeps its cached state.
        func modifications(in directories: Set<URL>) -> [URL: FileModificationKind] {
            var modifications = [URL: FileModificationKind]()

            for dir in directories {
                guard let trackedFiles = directoryIndex[dir] else { continue }

                for fileURL in trackedFiles where suppressedFiles[fileURL] == nil {
                    guard let cachedState = modificationStates[fileURL] else { continue }

                    let currentState = FileModificationState(url: fileURL)

                    guard let kind = cachedState.change(to: currentState) else { continue }

                    modificationStates[fileURL] = currentState
                    modifications[fileURL] = kind
                }
            }

            return modifications
        }

        private func scheduleFlush() {
            coalescingTask?.cancel()
            coalescingTask = Task { [weak self] in
                try await Task.sleep(seconds: self?.coalescingInterval ?? 0.5)
                try Task.checkCancellation()

                guard let self else { return }

                let modifications = await flushPending()

                guard !modifications.isEmpty else { return }

                await delegate?.fileModificationObserver(didDetectModifications: modifications)
            }
        }

        private func flushPending() -> [URL: FileModificationKind] {
            let modifications = pendingModifications
            pendingModifications.removeAll()
            return modifications
        }
    }
#endif
