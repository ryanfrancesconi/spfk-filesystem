// Copyright Ryan Francesconi. All Rights Reserved.

#if os(macOS)

    import Foundation
    import SPFKBase
    import SPFKTesting
    import Testing

    @testable import SPFKFileSystem

    /// ``MoveRunLog/recover(at:)`` over journals written by hand and a disk arranged to look
    /// interrupted.
    @Suite(.tags(.file, .renameOrganize))
    struct MoveRunLogRecoveryTests {
        typealias Sandbox = FileCommandsTests.Sandbox
        typealias Step = MoveRunLog.Record.Step

        /// A journal holding `units`, with `done`, an optional final-phase marker and end line,
        /// then `tail` written as-is.
        static func journal(
            in dir: Sandbox,
            units: [[Step]],
            done: [Int] = [],
            final: Bool = false,
            rolledBack: [Int]? = nil,
            tail: String = ""
        ) throws -> URL {
            let log = try MoveRunLog.create(in: dir.url.appendingPathComponent("Journals"), context: Data("ctx".utf8))
            var data = try Data(contentsOf: log.url)

            for (index, moves) in units.enumerated() {
                data.append(try MoveRunLog.line(.init(kind: .unit, index: index, moves: moves)))
            }

            if done.isNotEmpty { data.append(try MoveRunLog.line(.init(kind: .done, units: done))) }
            if final { data.append(try MoveRunLog.line(.init(kind: .final))) }
            if let rolledBack { data.append(try MoveRunLog.line(.init(kind: .end, rolledBack: rolledBack))) }

            data.append(Data(tail.utf8))
            try data.write(to: log.url)

            return log.url
        }

        static func step(_ from: URL, _ to: URL, staging: URL? = nil, companion: Bool = false) -> Step {
            Step(from: from.path, to: to.path, staging: staging?.path, companion: companion)
        }

        static func touch(_ url: URL, _ contents: String = "spfk") throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: url)
        }

        static func contents(_ url: URL) -> String? {
            try? String(contentsOf: url, encoding: .utf8)
        }

        @Test func withAnEndLineTheMovesAreDoneMinusRolledBackWithoutReadingTheDisk() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let a = dir.url.appendingPathComponent("a.jpg")
            let b = dir.url.appendingPathComponent("b.jpg")
            let to = dir.url.appendingPathComponent("to")

            let url = try Self.journal(
                in: dir,
                units: [[Self.step(a, to.appendingPathComponent("a.jpg"))], [Self.step(b, to.appendingPathComponent("b.jpg"))]],
                done: [0, 1],
                rolledBack: [1]
            )

            let recovered = try MoveRunLog.recover(at: url)

            #expect(recovered.context == Data("ctx".utf8))
            #expect(recovered.moves.moved == [a: to.appendingPathComponent("a.jpg")])
        }

        @Test func aUnitNotDoneWhoseOwnerIsAtItsDestinationCountsAsMoved() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let a = dir.url.appendingPathComponent("a.jpg")
            let b = dir.url.appendingPathComponent("b.jpg")
            let movedA = dir.url.appendingPathComponent("to/a.jpg")
            try Self.touch(movedA)
            try Self.touch(b)

            let url = try Self.journal(in: dir, units: [
                [Self.step(a, movedA)],
                [Self.step(b, dir.url.appendingPathComponent("to/b.jpg"))],
            ])

            #expect(try MoveRunLog.recover(at: url).moves.moved == [a: movedA])
        }

        @Test func aParkedFileGoesToItsDestinationWhenFree() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let a = dir.url.appendingPathComponent("a.jpg")
            let to = dir.url.appendingPathComponent("to/a.jpg")
            let parked = dir.url.appendingPathComponent(".spfk-rename-X-a.jpg")
            try Self.touch(parked, "a")
            try FileManager.default.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)

            let url = try Self.journal(in: dir, units: [[Self.step(a, to, staging: parked)]])
            let moves = try MoveRunLog.recover(at: url).moves

            #expect(moves.moved == [a: to])
            #expect(Self.contents(to) == "a")
            #expect(!parked.exists)
        }

        @Test func aParkedFileGoesBackWhenItsDestinationIsTaken() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let a = dir.url.appendingPathComponent("a.jpg")
            let b = dir.url.appendingPathComponent("b.jpg")
            let parked = dir.url.appendingPathComponent(".spfk-rename-X-a.jpg")
            try Self.touch(parked, "a")
            try Self.touch(b, "b")

            let url = try Self.journal(in: dir, units: [
                [Self.step(a, b, staging: parked)],
                [Self.step(b, a, staging: dir.url.appendingPathComponent(".spfk-rename-Y-b.jpg"))],
            ])
            let moves = try MoveRunLog.recover(at: url).moves

            #expect(moves.moved.isEmpty)
            #expect(Self.contents(a) == "a")
            #expect(Self.contents(b) == "b")
            #expect(!parked.exists)
        }

        /// In a swap both names are held either way, so only the final-phase marker tells a unit
        /// that finished from one never parked.
        @Test func aStagedUnitNotParkedHasMovedOnlyOnceTheFinalPhaseBegan() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let a = dir.url.appendingPathComponent("a.jpg")
            let b = dir.url.appendingPathComponent("b.jpg")
            try Self.touch(a, "a")
            try Self.touch(b, "b")

            let units = [
                [Self.step(a, b, staging: dir.url.appendingPathComponent(".spfk-rename-X-a.jpg"))],
                [Self.step(b, a, staging: dir.url.appendingPathComponent(".spfk-rename-Y-b.jpg"))],
            ]

            let staging = try Self.journal(in: dir, units: units)
            #expect(try MoveRunLog.recover(at: staging).moves.moved.isEmpty)

            let final = try Self.journal(in: dir, units: units, final: true)
            #expect(try MoveRunLog.recover(at: final).moves.moved == [a: b, b: a])
        }

        @Test func anOwnerAtItsDestinationPullsItsCompanionAlong() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let raw = dir.url.appendingPathComponent("A.RAF")
            let xmp = dir.url.appendingPathComponent("A.xmp")
            let newRaw = dir.url.appendingPathComponent("to/A.RAF")
            let newXmp = dir.url.appendingPathComponent("to/A.xmp")
            try Self.touch(newRaw)
            try Self.touch(xmp, "sidecar")

            let url = try Self.journal(in: dir, units: [[Self.step(raw, newRaw), Self.step(xmp, newXmp, companion: true)]])
            let moves = try MoveRunLog.recover(at: url).moves

            #expect(moves.moved == [raw: newRaw])
            #expect(moves.companions == [xmp: newXmp])
            #expect(Self.contents(newXmp) == "sidecar")
            #expect(!xmp.exists)
        }

        @Test func anOwnerStillAtItsSourceCallsItsCompanionBack() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let raw = dir.url.appendingPathComponent("A.RAF")
            let xmp = dir.url.appendingPathComponent("A.xmp")
            let newXmp = dir.url.appendingPathComponent("to/A.xmp")
            try Self.touch(raw)
            try Self.touch(newXmp, "sidecar")

            let url = try Self.journal(in: dir, units: [[
                Self.step(raw, dir.url.appendingPathComponent("to/A.RAF")),
                Self.step(xmp, newXmp, companion: true),
            ]])
            let moves = try MoveRunLog.recover(at: url).moves

            #expect(moves.moved.isEmpty)
            #expect(moves.companions.isEmpty)
            #expect(Self.contents(xmp) == "sidecar")
            #expect(!newXmp.exists)
        }

        @Test func aTruncatedLastLineIsIgnoredAndASecondRecoveryMovesNothing() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let a = dir.url.appendingPathComponent("a.jpg")
            let to = dir.url.appendingPathComponent("to/a.jpg")
            let parked = dir.url.appendingPathComponent(".spfk-rename-X-a.jpg")
            try Self.touch(parked, "a")
            try FileManager.default.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)

            let url = try Self.journal(in: dir, units: [[Self.step(a, to, staging: parked)]], tail: #"{"kind":"do"#)

            let first = try MoveRunLog.recover(at: url).moves
            #expect(first.moved == [a: to])

            // The disk no longer agrees; the journal's answer stands.
            try FileManager.default.moveItem(at: to, to: a)

            let second = try MoveRunLog.recover(at: url).moves
            #expect(second.moved == [a: to])
            #expect(Self.contents(a) == "a")
        }

        @Test func aMissingJournalThrows() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            #expect(throws: (any Error).self) {
                try MoveRunLog.recover(at: dir.url.appendingPathComponent("none.jsonl"))
            }
        }

        /// The engine's own journal of a finished run recovers to exactly what it moved.
        @Test func aFinishedRunRecoversToWhatItMoved() async throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let (plan, _, _) = try FileMoveCancellationTests.directPlan(150, in: dir)
            let log = try MoveRunLog.create(in: dir.url.appendingPathComponent("Journals"), context: Data())

            let moves = try await Task.detached {
                try FileCommands.move(plan, rollingBackOnFailure: false, log: log)
            }.value

            #expect(try MoveRunLog.recover(at: log.url).moves.moved == moves.moved)
        }
    }

#endif
