// Copyright Ryan Francesconi. All Rights Reserved.

#if os(macOS)

    import Foundation
    import SPFKBase
    import SPFKTesting
    import Testing

    @testable import SPFKFileSystem

    /// ``FileCommands/move(_:rollingBackOnFailure:)`` over groups whose destinations may be in
    /// another folder.
    @Suite(.tags(.file, .renameOrganize))
    @MainActor
    struct FileCommandsMoveTests {
        typealias Sandbox = FileCommandsTests.Sandbox

        private func folder(_ name: String, in dir: Sandbox) throws -> URL {
            let url = dir.url.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        private func names(in folder: URL) throws -> Set<String> {
            Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))
        }

        private func group(_ source: URL, _ destination: URL, companions: [(URL, URL)] = []) -> MovePlan.Entry {
            .move(MovePlan.Group(
                source: source,
                destination: destination,
                companions: companions.map { MovePlan.CompanionMove(from: $0.0, to: $0.1) }
            ))
        }

        @Test func aGroupMovesIntoAnotherFolderWithItsCompanions() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let raw = try dir.file(named: "A.RAF", contents: "raw")
            let sidecar = try dir.file(named: "A.xmp", contents: "sidecar")
            let target = try folder("Trip", in: dir)

            let moves = try FileCommands.move(MovePlan(entries: [
                group(raw, target.appendingPathComponent("Trip_001.RAF"), companions: [(sidecar, target.appendingPathComponent("Trip_001.xmp"))]),
            ]), rollingBackOnFailure: false)

            #expect(moves.moved == [raw: target.appendingPathComponent("Trip_001.RAF")])
            #expect(moves.companions == [sidecar: target.appendingPathComponent("Trip_001.xmp")])
            #expect(moves.failure == nil)
            #expect(try names(in: target) == ["Trip_001.RAF", "Trip_001.xmp"])
            #expect(try String(contentsOf: target.appendingPathComponent("Trip_001.xmp"), encoding: .utf8) == "sidecar")
        }

        @Test func aMissingDestinationFolderIsCreatedAndListed() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let photo = try dir.file(named: "A.jpg")
            let target = dir.url.appendingPathComponent("2026/11", isDirectory: true)

            let moves = try FileCommands.move(MovePlan(entries: [
                group(photo, target.appendingPathComponent("A.jpg")),
            ]), rollingBackOnFailure: false)

            #expect(moves.createdFolders.map(\.standardizedFileURL.path) == [
                target.deletingLastPathComponent().standardizedFileURL.path,
                target.standardizedFileURL.path,
            ])
            #expect(try names(in: target) == ["A.jpg"])
        }

        @Test func aSwapAcrossTwoFoldersLeavesNoStagingName() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let a = try folder("a", in: dir)
            let b = try folder("b", in: dir)
            let inA = a.appendingPathComponent("x.jpg")
            let inB = b.appendingPathComponent("x.jpg")
            try Data("from a".utf8).write(to: inA)
            try Data("from b".utf8).write(to: inB)

            let moves = try FileCommands.move(MovePlan(entries: [group(inA, inB), group(inB, inA)]), rollingBackOnFailure: false)

            #expect(moves.moved == [inA: inB, inB: inA])
            #expect(try String(contentsOf: inA, encoding: .utf8) == "from b")
            #expect(try String(contentsOf: inB, encoding: .utf8) == "from a")
            #expect(try names(in: a) == ["x.jpg"])
            #expect(try names(in: b) == ["x.jpg"])
        }

        @Test func aChainFinishesWithNoStagingName() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let one = try dir.file(named: "1.jpg", contents: "1")
            let two = try dir.file(named: "2.jpg", contents: "2")
            let three = try dir.file(named: "3.jpg", contents: "3")
            let target = try folder("new", in: dir)
            let new = target.appendingPathComponent("3.jpg")

            try FileCommands.move(MovePlan(entries: [group(one, two), group(two, three), group(three, new)]), rollingBackOnFailure: false)

            #expect(try Set(dir.names()) == ["2.jpg", "3.jpg", "new"])
            #expect(try String(contentsOf: two, encoding: .utf8) == "1")
            #expect(try String(contentsOf: three, encoding: .utf8) == "2")
            #expect(try String(contentsOf: new, encoding: .utf8) == "3")
        }

        @Test func anOccupantOutsideThePlanRefusesTheGroupBeforeAnythingMoves() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let first = try dir.file(named: "A.jpg")
            let second = try dir.file(named: "B.jpg")
            let target = try folder("Trip", in: dir)
            let taken = target.appendingPathComponent("Trip_002.jpg")
            try Data("theirs".utf8).write(to: taken)

            let plan = MovePlan(entries: [
                group(first, target.appendingPathComponent("Trip_001.jpg")),
                group(second, taken),
            ])

            #expect(FileCommands.moveConflicts(in: plan) == [second: .nameInUse(taken)])

            #expect(throws: FileCommandError.nameInUse(taken)) {
                try FileCommands.move(plan, rollingBackOnFailure: false)
            }

            #expect(try Set(dir.names()) == ["A.jpg", "B.jpg", "Trip"])
            #expect(try String(contentsOf: taken, encoding: .utf8) == "theirs")
        }

        /// A forward run keeps what moved and reports the failure.
        @Test func aFailurePartwayKeepsTheEarlierGroups() throws {
            let dir = try Sandbox()
            defer {
                try? dir.url.appendingPathComponent("locked").unlock()
                dir.remove()
            }

            let first = try dir.file(named: "A.jpg")
            let second = try dir.file(named: "B.jpg")
            let open = try folder("open", in: dir)
            let locked = try folder("locked", in: dir)
            try locked.lock()

            let moves = try FileCommands.move(MovePlan(entries: [
                group(first, open.appendingPathComponent("A.jpg")),
                group(second, locked.appendingPathComponent("B.jpg")),
            ]), rollingBackOnFailure: false)

            #expect(moves.moved == [first: open.appendingPathComponent("A.jpg")])
            #expect(moves.failure != nil)
            #expect(try names(in: open) == ["A.jpg"])
            #expect(second.exists)
        }

        /// An undo's replay is all or nothing.
        @Test func aFailureWhenRollingBackMovesEverythingBack() throws {
            let dir = try Sandbox()
            defer {
                try? dir.url.appendingPathComponent("locked").unlock()
                dir.remove()
            }

            let first = try dir.file(named: "A.jpg")
            let sidecar = try dir.file(named: "A.xmp")
            let second = try dir.file(named: "B.jpg")
            let open = try folder("open", in: dir)
            let locked = try folder("locked", in: dir)
            try locked.lock()

            #expect(throws: (any Error).self) {
                try FileCommands.move(MovePlan(entries: [
                    group(first, open.appendingPathComponent("A.jpg"), companions: [(sidecar, open.appendingPathComponent("A.xmp"))]),
                    group(second, locked.appendingPathComponent("B.jpg")),
                ]), rollingBackOnFailure: true)
            }

            #expect(try names(in: open).isEmpty)
            #expect(first.exists && sidecar.exists && second.exists)
        }

        @Test func skippedAndInPlaceEntriesMoveNothing() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let kept = try dir.file(named: "A.jpg")
            let skipped = try dir.file(named: "B.jpg")

            let moves = try FileCommands.move(MovePlan(entries: [
                .alreadyInPlace(kept),
                .skipped(skipped, .locked),
            ]), rollingBackOnFailure: false)

            #expect(moves.moved.isEmpty)
            #expect(try Set(dir.names()) == ["A.jpg", "B.jpg"])
        }

        @Test func theStagingNameIsNeverARenderSiblingName() {
            let url = URL(fileURLWithPath: "/tmp/IMG_1234.HEIC")

            for _ in 0 ..< 20 {
                #expect(!URL.isRenderSiblingName(FileCommands.renameStagingURL(for: url).lastPathComponent))
            }
        }
    }

#endif
