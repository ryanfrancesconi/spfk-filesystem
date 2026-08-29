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

    /// The catalog these descriptions resolve against, and the keys they resolve by.
    ///
    /// - Note: Asserted in German, through the `de.lproj` sub-bundle. Every lookup falls back to
    ///   its own key, and in the source language the key *is* the English text -- so an English
    ///   assertion passes just as well with the catalog missing entirely. `String(localized:)`'s
    ///   `locale:` cannot stand in for this: it selects number and date formatting, not which
    ///   localization is read.
    @Suite(.tags(.file))
    struct FileLockStateLocalizationTests {
        private func germanBundle() throws -> Bundle {
            let path = try #require(
                Bundle.module.path(forResource: "de", ofType: "lproj"),
                "the module bundle carries no de.lproj -- is `resources:` still in Package.swift?"
            )
            return try #require(Bundle(path: path))
        }

        /// Pins the resource-bundle wiring: dropping `resources:` from `Package.swift` leaves every
        /// description silently untranslated.
        @Test func descriptionsResolveAgainstTheModuleCatalog() throws {
            let german = try germanBundle()

            #expect(String(localized: "Locked", bundle: german) == "Gesperrt")
            #expect(String(localized: "Writable", bundle: german) == "Beschreibbar")
            #expect(
                String(localized: "On a read-only volume", bundle: german)
                    == "Auf einem schreibgeschützten Volume"
            )
        }

        /// An interpolated key reaches the catalog as `%@`, so the argument landing in the German
        /// output is what separates a matched key from one that fell back to itself.
        @Test func failureDescriptionsResolveWithTheirArgument() throws {
            let german = try germanBundle()
            let name = "take.wav"

            #expect(
                String(localized: "\(name) is locked. Unlock it to save changes.", bundle: german)
                    == "take.wav ist gesperrt. Entsperren Sie die Datei, um Änderungen zu sichern."
            )
            #expect(
                String(localized: "\(name) could not be written", bundle: german)
                    == "take.wav konnte nicht geschrieben werden"
            )
        }
    }

#endif
