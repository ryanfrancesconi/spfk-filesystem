// Copyright Ryan Francesconi. All Rights Reserved.

#if os(macOS)

    import Foundation
    import SPFKBase
    import SPFKTesting
    import Testing

    @testable import SPFKFileSystem

    /// A RAW's XMP sidecar travelling with it through Rename, Duplicate, Move to Trash and their
    /// inverses. The files are not RAW: the rule is by extension.
    @Suite(.tags(.file, .xmpSidecar))
    @MainActor
    struct FileCommandsCompanionTests {
        typealias Sandbox = FileCommandsTests.Sandbox

        // MARK: - Companions

        @Test func aRAWWithASidecarHasItAsItsCompanion() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let raw = try dir.file(named: "DSCF3303.RAF")
            #expect(raw.existingCompanionURLs.isEmpty)

            let sidecar = try dir.file(named: "DSCF3303.xmp")
            #expect(raw.existingCompanionURLs == [sidecar])
        }

        @Test func aDNGBesideASameNamedSidecarHasNoCompanion() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let dng = try dir.file(named: "DSCF0060.dng")
            _ = try dir.file(named: "DSCF0060.xmp")

            #expect(dng.existingCompanionURLs.isEmpty)
        }

        // MARK: - Rename

        @Test func renameCarriesTheSidecar() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let raw = try dir.file(named: "DSCF3303.RAF")
            _ = try dir.file(named: "DSCF3303.xmp", contents: "sidecar")

            let renamed = try FileCommands.rename(raw, to: "Harbor")

            #expect(renamed.lastPathComponent == "Harbor.RAF")
            #expect(try Set(dir.names()) == ["Harbor.RAF", "Harbor.xmp"])
            #expect(try String(contentsOf: dir.url.appendingPathComponent("Harbor.xmp"), encoding: .utf8) == "sidecar")
        }

        @Test func renameKeepsTheSidecarsOwnExtension() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let raw = try dir.file(named: "DSCF3303.RAF")
            _ = try dir.file(named: "DSCF3303.XMP")

            try FileCommands.rename(raw, to: "Harbor")

            #expect(try Set(dir.names()) == ["Harbor.RAF", "Harbor.XMP"])
        }

        @Test func renameLeavesATakenSidecarNameAlone() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let raw = try dir.file(named: "DSCF3303.RAF")
            _ = try dir.file(named: "DSCF3303.xmp", contents: "mine")
            let taken = try dir.file(named: "Harbor.xmp", contents: "theirs")

            try FileCommands.rename(raw, to: "Harbor")

            #expect(try Set(dir.names()) == ["Harbor.RAF", "Harbor.xmp", "DSCF3303.xmp"])
            #expect(try String(contentsOf: taken, encoding: .utf8) == "theirs")
        }

        @Test func renameWithoutASidecarBehavesAsBefore() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let raw = try dir.file(named: "DSCF3303.RAF")
            try FileCommands.rename(raw, to: "Harbor")

            #expect(try dir.names() == ["Harbor.RAF"])
        }

        // MARK: - Duplicate

        @Test func duplicateCopiesTheSidecarToTheCopysName() async throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let raw = try dir.file(named: "DSCF3303.RAF")
            let sidecar = try dir.file(named: "DSCF3303.xmp", contents: "sidecar")

            let result = try await FileCommands.duplicate(urls: [raw])
            let copy = try #require(result.copies[raw])
            let copiedSidecar = copy.deletingPathExtension().appendingPathExtension("xmp")

            #expect(result.copies.count == 1)
            #expect(result.companions == [sidecar: copiedSidecar])
            #expect(result.skippedCompanions.isEmpty)
            #expect(try String(contentsOf: copiedSidecar, encoding: .utf8) == "sidecar")
            #expect(try String(contentsOf: sidecar, encoding: .utf8) == "sidecar")
        }

        @Test func duplicateSkipsATakenSidecarNameWithoutOverwritingIt() async throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let raw = try dir.file(named: "DSCF3303.RAF")
            let sidecar = try dir.file(named: "DSCF3303.xmp", contents: "sidecar")
            let taken = try dir.file(named: "DSCF3303 copy.xmp", contents: "theirs")

            let result = try await FileCommands.duplicate(urls: [raw])
            let copy = try #require(result.copies[raw])

            // Read from the result: `NSWorkspace` picks the name.
            #expect(copy.deletingPathExtension().appendingPathExtension("xmp") == taken)
            #expect(result.companions.isEmpty)
            #expect(result.skippedCompanions == [sidecar])
            #expect(try String(contentsOf: taken, encoding: .utf8) == "theirs")
        }

        @Test func duplicateWithoutASidecarBehavesAsBefore() async throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let raw = try dir.file(named: "DSCF3303.RAF")
            let result = try await FileCommands.duplicate(urls: [raw])

            #expect(result.copies.count == 1)
            #expect(result.companions.isEmpty)
            #expect(try dir.names().count == 2)
        }

        @Test func deleteRemovesTheListedSidecarToo() async throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let raw = try dir.file(named: "DSCF3303.RAF")
            _ = try dir.file(named: "DSCF3303.xmp")

            let result = try await FileCommands.duplicate(urls: [raw])
            let copies = Array(result.copies.values) + Array(result.companions.values)

            #expect(FileCommands.delete(urls: copies).isEmpty)
            #expect(try Set(dir.names()) == ["DSCF3303.RAF", "DSCF3303.xmp"])
        }

        // MARK: - Trash

        @Test func trashMovesBothAndRestoreBringsBothBack() async throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let name = "Trash-\(UUID().uuidString)"
            let raw = try dir.file(named: "\(name).RAF", contents: "raw")
            let sidecar = try dir.file(named: "\(name).xmp", contents: "sidecar")

            let trashed = try await FileCommands.moveToTrash(urls: [raw])

            #expect(Set(trashed.keys) == [raw, sidecar])
            #expect(try dir.names().isEmpty)

            #expect(FileCommands.restoreFromTrash(trashed).isEmpty)
            #expect(try String(contentsOf: raw, encoding: .utf8) == "raw")
            #expect(try String(contentsOf: sidecar, encoding: .utf8) == "sidecar")
        }

        @Test func trashingADNGLeavesASameNamedSidecar() async throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let name = "Trash-\(UUID().uuidString)"
            let dng = try dir.file(named: "\(name).dng")
            _ = try dir.file(named: "\(name).xmp")

            let trashed = try await FileCommands.moveToTrash(urls: [dng])
            defer { _ = FileCommands.restoreFromTrash(trashed) }

            #expect(Set(trashed.keys) == [dng])
            #expect(try dir.names() == ["\(name).xmp"])
        }
    }

#endif
