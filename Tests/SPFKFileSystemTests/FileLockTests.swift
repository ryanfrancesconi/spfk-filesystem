// Copyright Ryan Francesconi. All Rights Reserved.

#if os(macOS)

    import Foundation
    import SPFKBase
    import SPFKTesting
    import Testing

    @testable import SPFKFileSystem

    /// The `uchg` BSD flag — Finder's Get Info **"Locked"** checkbox.
    ///
    /// A locked file reads perfectly and refuses every write, including the extended-attribute
    /// write Finder tags travel in. Nothing reports the flag on its own: `fopen("rb+")` returns
    /// `EPERM`, and a library that falls back to read-only on that turns a locked file into a
    /// generic save failure with no reason attached.
    ///
    /// These pin the platform behavior a `FileLockState` is to be built on — see
    /// `file-lock-state.md`.
    @Suite(.tags(.file))
    struct FileLockTests {
        // MARK: - What the resource keys report

        @Test func aLockedFileIsUserImmutableAndNotWritable() throws {
            let file = try TemporaryFile()
            defer { file.remove() }

            try file.lock()

            let values = try file.url.resourceValues(forKeys: [
                .isUserImmutableKey, .isSystemImmutableKey, .isWritableKey, .volumeIsReadOnlyKey,
            ])

            #expect(values.isUserImmutable == true)
            #expect(values.isWritable == false)
            #expect(values.isSystemImmutable == false)
            #expect(values.volumeIsReadOnly == false)
        }

        /// Why the state cannot be a `Bool`. A file the owner has made read-only reports exactly
        /// the same `isWritable` as a locked one, and only the locked one is something an app can
        /// offer to clear — so anything deciding whether to show an Unlock control has to read
        /// `isUserImmutable`, not `isWritable`.
        @Test func isWritableAloneCannotSayWhyAFileRefusesAWrite() throws {
            let file = try TemporaryFile()
            defer { file.remove() }

            try FileManager.default.setAttributes(
                [.posixPermissions: 0o444],
                ofItemAtPath: file.url.path
            )

            let values = try file.url.resourceValues(forKeys: [.isWritableKey, .isUserImmutableKey])

            #expect(values.isWritable == false)
            #expect(values.isUserImmutable == false)

            try FileManager.default.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: file.url.path
            )
        }

        // MARK: - Finder tags

        /// The asymmetry that makes a lock confusing to diagnose: reading is untouched, so a file
        /// displays its tags normally and only the write is refused.
        @Test func aLockedFileStillReadsItsFinderTags() throws {
            let file = try TemporaryFile()
            defer { file.remove() }

            try file.url.set(tagNames: ["Red\n6"])
            try file.lock()

            #expect(file.url.tagColors.contains(.red))
        }

        /// Finder tags are an extended attribute, and `setxattr` fails with `EPERM` on a locked
        /// file — so this reaches the tag write, not only the file's data stream.
        @Test func aLockedFileRefusesAFinderTagWrite() throws {
            let file = try TemporaryFile()
            defer { file.remove() }

            try file.lock()

            #expect(throws: (any Error).self) {
                try file.url.set(tagNames: ["Blue\n4"])
            }
        }

        // MARK: - What else the flag blocks

        /// The flag is not only about writing bytes. Anything that would replace or unlink the file
        /// is refused too, so a rename or a delete needs the same check a save does.
        @Test func aLockedFileRefusesRenameAndRemoval() throws {
            let file = try TemporaryFile()
            defer { file.remove() }

            try file.lock()

            let destination = file.url.deletingLastPathComponent()
                .appendingPathComponent("renamed-\(UUID().uuidString)")

            #expect(throws: (any Error).self) {
                try FileManager.default.moveItem(at: file.url, to: destination)
            }

            #expect(throws: (any Error).self) {
                try FileManager.default.removeItem(at: file.url)
            }
        }

        // MARK: - Clearing it

        /// Foundation can clear the flag, so an app can offer to unlock rather than sending the
        /// user to Finder. This is the whole affordance.
        @Test func unlockingRestoresWritability() throws {
            let file = try TemporaryFile()
            defer { file.remove() }

            try file.lock()
            #expect(try file.url.resourceValues(forKeys: [.isWritableKey]).isWritable == false)

            try file.unlock()

            #expect(try file.url.resourceValues(forKeys: [.isWritableKey]).isWritable == true)
            #expect(try file.url.set(tagNames: ["Green\n2"]) == ())
        }

        /// Toggling the lock moves the attribute modification date and leaves the content date
        /// alone, so ``FileModificationState`` classifies it as ``FileModificationKind/attributes``.
        ///
        /// Two consequences for anything observing files: an external lock or unlock in Finder is
        /// already reported without new observation, and an app's own unlock has to be suppressed
        /// or it comes straight back as an external change and reparses the selection.
        @Test func lockingClassifiesAsAnAttributeChange() throws {
            let file = try TemporaryFile()
            defer { file.remove() }

            let before = FileModificationState(url: file.url)
            try file.lock()
            let after = FileModificationState(url: file.url)

            #expect(before.change(to: after) == .attributes)
        }
    }

    // MARK: - Harness

    /// A throwaway file whose `uchg` flag the lock suites toggle.
    ///
    /// Removal goes through here because the flag has to come off first — a locked temporary file
    /// cannot be deleted, and one left behind stays undeletable.
    struct TemporaryFile {
        let url: URL

        init() throws {
            url = FileManager.default.temporaryDirectory
                .appendingPathComponent("file-lock-\(UUID().uuidString).txt")
            try Data("spfk".utf8).write(to: url)
        }

        func lock() throws {
            try setImmutable(true)
        }

        func unlock() throws {
            try setImmutable(false)
        }

        func remove() {
            try? unlock()
            try? FileManager.default.removeItem(at: url)
        }

        private func setImmutable(_ immutable: Bool) throws {
            var url = url
            var values = URLResourceValues()
            values.isUserImmutable = immutable
            try url.setResourceValues(values)
        }
    }

#endif
