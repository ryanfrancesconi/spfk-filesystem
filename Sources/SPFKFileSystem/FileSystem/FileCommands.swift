// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

#if os(macOS)

    import AppKit
    import Foundation
    import SPFKBase

    /// What went wrong with a single-file command.
    ///
    /// The batch commands report per-file instead and never throw one of these.
    public enum FileCommandError: LocalizedError, Equatable {
        /// The name is empty, whitespace-only, or contains a path separator.
        case invalidName(String)

        /// Something already occupies the destination.
        case nameInUse(URL)

        /// Something already occupies a companion's destination.
        case companionNameInUse(URL)

        /// Two of the file's own companions would take this one name.
        case companionNameClash(URL)

        /// The file carries the `uchg` flag, which refuses a rename.
        case locked(URL)

        /// A rename failed partway and the file at the first URL could not be moved back to the second.
        case rollbackFailed(URL, original: URL)

        public var errorDescription: String? {
            switch self {
            case .invalidName:
                localized("That name can't be used. Names cannot be empty or contain a slash.")
            case let .nameInUse(url):
                localized("An item named \"\(url.lastPathComponent)\" already exists in this location.")
            case let .companionNameInUse(url):
                localized("A sidecar named \"\(url.lastPathComponent)\" already exists in this location.")
            case let .companionNameClash(url):
                localized("Two of this file's sidecars would both be named \"\(url.lastPathComponent)\".")
            case let .locked(url):
                localized("\"\(url.lastPathComponent)\" is locked. Unlock it to rename it.")
            case let .rollbackFailed(url, original):
                localized("The rename failed, and \"\(url.lastPathComponent)\" couldn't be renamed back to \"\(original.lastPathComponent)\".")
            }
        }
    }

    /// The Finder's own file gestures - duplicate, trash, restore, rename - as one call each.
    ///
    /// **`@MainActor` is load-bearing for ``duplicate(urls:)`` and ``moveToTrash(urls:)``.**
    /// `NSWorkspace` delivers their completion on the queue that made the call, so a detached task
    /// creates the files and then waits forever for a handler that has no run loop to arrive on.
    ///
    /// **Those two take the completion-handler spelling rather than `NSWorkspace`'s own `async`
    /// overloads, which lose a partial batch.** The handler receives a populated map *and* an
    /// error when some files succeeded and others did not; the generated `async` form resumes with
    /// the error alone, so the map naming what actually moved is gone while the files are moved
    /// regardless. Measured on both calls - a trash of two writable files plus one locked one threw
    /// with the two already in the Trash and no way to name them, which is exactly what an undo
    /// needs.
    ///
    /// Two error conventions, split by arity. The single-URL ``rename(_:to:)`` throws, because there
    /// is one outcome and the caller must react to it. The batch calls report per-file so that one
    /// bad file does not cost the caller the other nine: ``duplicate(urls:)`` and
    /// ``moveToTrash(urls:)`` hand back whatever succeeded and throw only when nothing did, while
    /// ``restoreFromTrash(_:)`` and ``delete(urls:)`` return a map naming just the failures.
    @MainActor
    public enum FileCommands {
        /// Finder-named copies beside each original - `Song.txt` becomes `Song copy.txt`, then
        /// `Song copy 2.txt` - each with a copy of its companions named after it.
        ///
        /// A copy inherits the original's extended attributes, Finder tags and `uchg` flag. A
        /// companion whose name is taken is skipped, never overwritten.
        @discardableResult
        public static func duplicate(urls: [URL]) async throws -> FileDuplicates {
            guard urls.isNotEmpty else { return FileDuplicates() }

            let copies = try await withCheckedThrowingContinuation { continuation in
                NSWorkspace.shared.duplicate(urls) { newURLs, error in
                    continuation.resume(with: Self.partial(newURLs, error))
                }
            }

            return duplicatingCompanions(of: copies, companions: await FileCompanions.resolve(urls))
        }

        /// Returns original → its location in the Trash, companions included under their own URLs.
        ///
        /// A locked file is simply absent from the map - the caller that wants to offer
        /// unlock-and-retry checks the selection before calling rather than discovering it here.
        /// Its companions stay with it.
        @discardableResult
        public static func moveToTrash(urls: [URL]) async throws -> [URL: URL] {
            try await moveToTrash(trashSet: await trashSet(for: urls))
        }

        /// Trashes exactly `trashSet`, as ``trashSet(for:)`` gave it, for a caller that needs the
        /// set before the files move.
        @discardableResult
        public static func moveToTrash(trashSet all: [URL]) async throws -> [URL: URL] {
            guard all.isNotEmpty else { return [:] }

            return try await withCheckedThrowingContinuation { continuation in
                NSWorkspace.shared.recycle(all) { newURLs, error in
                    continuation.resume(with: Self.partial(newURLs, error))
                }
            }
        }

        /// Moves each file back out of the Trash. Keys are original locations, values Trash
        /// locations - the shape ``moveToTrash(urls:)`` returns, companions included.
        ///
        /// Returns the failures only; an empty result means every file came back.
        @discardableResult
        public static func restoreFromTrash(_ mapping: [URL: URL]) -> [URL: any Error] {
            var failures: [URL: any Error] = [:]

            for (original, trashURL) in mapping {
                do {
                    try FileManager.default.moveItem(at: trashURL, to: original)
                } catch {
                    failures[original] = error
                }
            }

            return failures
        }

        /// Deletes outright, bypassing the Trash, clearing `uchg` first. Deletes only the URLs
        /// given: a companion is listed by the caller, from ``FileDuplicates/companions``.
        ///
        /// **Only for files the app itself created and is now taking back** - undoing a Duplicate is
        /// the one caller. Clearing the user-immutable flag without asking is defensible only
        /// because the lock was inherited from the original moments ago, never set by the user on
        /// this file. `removeItem` refuses a locked file, and a duplicate of a locked file is
        /// itself locked, so these are exactly the files that would otherwise refuse removal.
        ///
        /// Returns the failures only.
        @discardableResult
        public static func delete(urls: [URL]) -> [URL: any Error] {
            var failures: [URL: any Error] = [:]

            for url in urls {
                do {
                    try url.withSecurityScopedAccess {
                        if url.isLocked {
                            try url.unlock()
                        }

                        try FileManager.default.removeItem(at: url)
                    }
                } catch {
                    failures[url] = error
                }
            }

            return failures
        }

        /// In-place rename, returning the file's new URL. Companions are renamed to the new base
        /// name, keeping their own extensions, and a companion name held by another file refuses
        /// the rename before anything moves.
        ///
        /// A name with no extension keeps the original's, the way Finder does - a user retyping a
        /// basename must not silently drop `.wav`. A case-only change succeeds on a case-insensitive
        /// volume. The one-entry case of ``renameAll(_:rollingBackOnFailure:)``.
        @discardableResult
        public static func rename(_ url: URL, to newName: String) throws -> URL {
            let destination = try renameDestination(for: url, newName: newName)

            return try renameAll([url: destination], rollingBackOnFailure: true).renamed[url] ?? url
        }

        /// The URL ``rename(_:to:)`` would move to, or a throw describing why it cannot.
        ///
        /// Separate so the validation is reachable without a file on disk.
        public static func renameDestination(for url: URL, newName: String) throws -> URL {
            let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)

            guard trimmed.isNotEmpty, !trimmed.contains("/") else {
                throw FileCommandError.invalidName(newName)
            }

            // `appendingPathComponent` would read a leading dot as an extension-only name, and
            // `..` as a traversal; neither is a rename the user meant.
            guard trimmed != ".", trimmed != ".." else {
                throw FileCommandError.invalidName(newName)
            }

            let sourceExtension = url.pathExtension
            let hasExtension = (trimmed as NSString).pathExtension.isNotEmpty

            let filename = hasExtension || sourceExtension.isEmpty
                ? trimmed
                : "\(trimmed).\(sourceExtension)"

            return url.deletingLastPathComponent().appendingPathComponent(filename)
        }

        /// `NSWorkspace` reports a partial batch as a populated map *and* an error, so the map wins
        /// whenever it holds anything - the caller needs to see what did happen.
        private nonisolated static func partial(_ newURLs: [URL: URL], _ error: (any Error)?) -> Result<[URL: URL], any Error> {
            if newURLs.isEmpty, let error {
                return .failure(error)
            }

            return .success(newURLs)
        }
    }

#endif
