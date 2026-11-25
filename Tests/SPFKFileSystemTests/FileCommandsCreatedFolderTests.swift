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

        /// Cancelled once 100 groups have moved, the run moves them back and leaves no new folder.
        @Test func aCancelledMoveRemovesTheFoldersItCreated() async throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let (plan, from, to) = try FileMoveCancellationTests.directPlan(150, in: dir)

            let result = await Task.detached {
                try FileCommands.move(plan, rollingBackOnFailure: true) { finished, _ in
                    if finished >= 100 { withUnsafeCurrentTask { $0?.cancel() } }
                }
            }.result

            #expect(throws: CancellationError.self) { try result.get() }
            #expect(!to.exists)
            #expect(FileMoveCancellationTests.names(in: from).count == 150)
        }

        /// A rotation in which every group parks first. Once 100 have finished, the next group's
        /// parked file is gone, so the final phase fails; the folder the first group's companion
        /// moved into does not stay.
        @Test func aFailureInTheFinalPhaseRemovesTheFoldersItCreated() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let count = 101
            let names = (0 ..< count).map { String(format: "f%03d.wav", $0) }
            let sources = try names.map { try dir.file(named: $0) }
            let sidecar = try dir.file(named: "f000.xmp")
            let created = dir.url.appendingPathComponent("Sidecars", isDirectory: true)

            var entries: [MovePlan.Entry] = []

            for index in 0 ..< count {
                let companions = index == 0 ? [MovePlan.CompanionMove(from: sidecar, to: created.appendingPathComponent("f000.xmp"))] : []
                entries.append(.move(MovePlan.Group(source: sources[index], destination: sources[(index + 1) % count], companions: companions)))
            }

            let directory = dir.url

            #expect(throws: (any Error).self) {
                try FileCommands.move(MovePlan(entries: entries), rollingBackOnFailure: true) { finished, _ in
                    guard finished == 100 else { return }

                    let parked = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
                    for name in parked where name.hasPrefix(".spfk-rename-") && name.hasSuffix("-f100.wav") {
                        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
                    }
                }
            }

            #expect(!created.exists)
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
