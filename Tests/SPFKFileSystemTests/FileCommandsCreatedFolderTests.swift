// Copyright Ryan Francesconi. All Rights Reserved.

#if os(macOS)

    import Foundation
    import SPFKBase
    import SPFKTesting
    import Testing

    @testable import SPFKFileSystem

    /// A move or copy that fails removes the destination folders it created and left empty.
    @Suite(.tags(.file, .renameOrganize))
    @MainActor
    struct FileCommandsCreatedFolderTests {
        typealias Sandbox = FileCommandsTests.Sandbox

        private func group(_ source: URL, _ destination: URL) -> MovePlan.Entry {
            .move(MovePlan.Group(source: source, destination: destination))
        }

        /// An undo replay whose sources are gone: nothing moves, and none of its folders stay.
        @Test func aFailedMoveRollingBackRemovesTheFoldersItCreated() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let existing = dir.url.appendingPathComponent("existing", isDirectory: true)
            try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: false)
            let photo = try dir.file(named: "A.jpg")
            let gone = dir.url.appendingPathComponent("gone.jpg")

            #expect(throws: (any Error).self) {
                try FileCommands.move(MovePlan(entries: [
                    group(photo, existing.appendingPathComponent("A.jpg")),
                    group(gone, dir.url.appendingPathComponent("subfolder/2022/2022-02-19/gone.jpg")),
                ]), rollingBackOnFailure: true)
            }

            #expect(!dir.url.appendingPathComponent("subfolder").exists)
            #expect(existing.exists)
            #expect(photo.exists)
        }

        @Test func aMoveFailingBeforeAnyGroupMovesRemovesTheFoldersItCreated() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let gone = dir.url.appendingPathComponent("gone.jpg")

            let moves = try FileCommands.move(MovePlan(entries: [
                group(gone, dir.url.appendingPathComponent("2026/11/gone.jpg")),
            ]), rollingBackOnFailure: false)

            #expect(moves.failure != nil)
            #expect(moves.createdFolders.isEmpty)
            #expect(!dir.url.appendingPathComponent("2026").exists)
        }

        /// The folder a finished group moved into stays, and stays listed for its undo.
        @Test func aMoveFailingPartwayKeepsOnlyTheFoldersInUse() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let photo = try dir.file(named: "A.jpg")
            let gone = dir.url.appendingPathComponent("gone.jpg")
            let used = dir.url.appendingPathComponent("used", isDirectory: true)

            let moves = try FileCommands.move(MovePlan(entries: [
                group(photo, used.appendingPathComponent("A.jpg")),
                group(gone, dir.url.appendingPathComponent("unused/gone.jpg")),
            ]), rollingBackOnFailure: false)

            #expect(moves.failure != nil)
            #expect(moves.createdFolders.map(\.standardizedFileURL.path) == [used.standardizedFileURL.path])
            #expect(used.appendingPathComponent("A.jpg").exists)
            #expect(!dir.url.appendingPathComponent("unused").exists)
        }

        @Test func aFailedCopyRollingBackRemovesTheFoldersItCreated() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let photo = try dir.file(named: "A.jpg")
            let gone = dir.url.appendingPathComponent("gone.jpg")

            #expect(throws: (any Error).self) {
                try FileCommands.copy(MovePlan(entries: [
                    group(photo, dir.url.appendingPathComponent("copies/A.jpg")),
                    group(gone, dir.url.appendingPathComponent("copies/2022/gone.jpg")),
                ]), cloning: false, rollingBackOnFailure: true)
            }

            #expect(!dir.url.appendingPathComponent("copies").exists)
            #expect(photo.exists)
        }
    }

#endif
