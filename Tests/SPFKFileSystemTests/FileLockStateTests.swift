// Copyright Ryan Francesconi. All Rights Reserved.

#if os(macOS)

    import Foundation
    import SPFKTesting
    import Testing

    @testable import SPFKFileSystem

    /// ``FileLockState`` and the `URL` API over it.
    ///
    /// `FileLockTests` pins what the platform does; this pins what the type makes of it. The pair
    /// that matters is ``FileLockState/locked`` against ``FileLockState/notPermitted`` — both read
    /// `isWritable == false`, and only the first is something the app can offer to clear.
    ///
    /// - Note: ``FileLockState/readOnlyVolume`` is not covered. Reaching it means mounting a real
    ///   read-only volume, which a unit test has no business doing to the machine it runs on.
    @Suite(.tags(.file))
    struct FileLockStateTests {
        // MARK: - Resolving a state from a real file

        @Test func anOrdinaryFileIsWritable() throws {
            let file = try TemporaryFile()
            defer { file.remove() }

            #expect(file.url.lockState == .writable)
            #expect(file.url.isLocked == false)
            #expect(throws: Never.self) { try file.url.requireWritable() }
        }

        @Test func aLockedFileIsLocked() throws {
            let file = try TemporaryFile()
            defer { file.remove() }

            try file.url.lock()

            #expect(file.url.lockState == .locked)
            #expect(file.url.isLocked)
        }

        /// Permissions rather than the flag. The state the Unlock control must *not* offer to
        /// clear, and the reason this is not a `Bool`.
        @Test func anUnwritableFileIsNotPermittedRatherThanLocked() throws {
            let file = try TemporaryFile()
            defer {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o644], ofItemAtPath: file.url.path
                )
                file.remove()
            }

            try FileManager.default.setAttributes(
                [.posixPermissions: 0o444], ofItemAtPath: file.url.path
            )

            #expect(file.url.lockState == .notPermitted)
            #expect(file.url.lockState.canUnlock == false)
        }

        /// Precedence, where both apply. `locked` wins over `notPermitted` because it is the one
        /// the user can act on from inside the app.
        @Test func theFlagOutranksPermissions() throws {
            let file = try TemporaryFile()
            defer {
                try? file.url.unlock()
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o644], ofItemAtPath: file.url.path
                )
                file.remove()
            }

            try FileManager.default.setAttributes(
                [.posixPermissions: 0o444], ofItemAtPath: file.url.path
            )
            try file.url.lock()

            #expect(file.url.lockState == .locked)
        }

        /// `resourceValues` throws for a file that is not there, and this type answers `.writable`
        /// rather than inventing a permissions failure — the products already carry `isMissing`,
        /// and a save guard reporting "not writable" for a deleted file would name the wrong
        /// problem.
        @Test func aMissingFileIsWritable() throws {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("absent-\(UUID().uuidString).txt")

            #expect(url.lockState == .writable)
            #expect(throws: Never.self) { try url.requireWritable() }
        }

        // MARK: - The guard

        @Test func requireWritableThrowsWithTheStateAttached() throws {
            let file = try TemporaryFile()
            defer { file.remove() }

            try file.url.lock()

            let error = #expect(throws: FileLockError.self) {
                try file.url.requireWritable()
            }

            #expect(error?.state == .locked)
            #expect(error?.canUnlock == true)
            #expect(error?.url == file.url)
            #expect(error?.localizedDescription.contains(file.url.lastPathComponent) == true)
        }

        // MARK: - Clearing it through this API

        @Test func unlockRestoresWritability() throws {
            let file = try TemporaryFile()
            defer { file.remove() }

            try file.url.lock()
            #expect(file.url.lockState == .locked)

            try file.url.unlock()

            #expect(file.url.lockState == .writable)
            #expect(throws: Never.self) { try file.url.requireWritable() }
        }

        // MARK: - The type itself

        @Test func onlyLockedIsOfferedAsUnlockable() {
            #expect(FileLockState.allCases.filter(\.canUnlock) == [.locked])
        }

        @Test func onlyWritableReportsWritable() {
            #expect(FileLockState.allCases.filter(\.isWritable) == [.writable])
        }
    }

#endif
