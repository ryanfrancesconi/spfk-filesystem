// Copyright Ryan Francesconi. All Rights Reserved.

#if os(macOS)

    import Foundation
    import SPFKBase
    import SPFKTesting
    import Testing

    @testable import SPFKFileSystem

    /// What ``MoveRunLog`` records of a run, read back line by line.
    @Suite(.tags(.file, .renameOrganize))
    struct MoveRunLogTests {
        typealias Sandbox = FileCommandsTests.Sandbox

        static func lines(of url: URL) throws -> [[String: Any]] {
            try String(contentsOf: url, encoding: .utf8)
                .split(separator: "\n")
                .map { try #require(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]) }
        }

        static func journals(in dir: Sandbox) -> URL {
            dir.url.appendingPathComponent("Journals", isDirectory: true)
        }

        @Test func aRunRecordsEveryUnitBeforeItMovesAndEndsWithNothingRolledBack() async throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let (plan, _, _) = try FileMoveCancellationTests.directPlan(250, in: dir)
            let log = try MoveRunLog.create(in: Self.journals(in: dir), context: Data("ctx".utf8))

            try await Task.detached {
                try FileCommands.move(plan, rollingBackOnFailure: false, log: log)
            }.value

            let lines = try Self.lines(of: log.url)
            let kinds = lines.map { $0["kind"] as? String }

            #expect(kinds.first == "header")
            #expect(lines.first?["context"] as? String == Data("ctx".utf8).base64EncodedString())
            #expect(kinds.firstIndex(of: "done").map { $0 > 250 } == true)
            #expect(kinds.filter { $0 == "unit" }.count == 250)

            let done = lines.filter { $0["kind"] as? String == "done" }.flatMap { $0["units"] as? [Int] ?? [] }
            #expect(Set(done) == Set(0 ..< 250))

            #expect(kinds.last == "end")
            #expect(lines.last?["rolledBack"] as? [Int] == [])

            let firstUnit = try #require(lines.first { $0["kind"] as? String == "unit" })
            let step = try #require((firstUnit["moves"] as? [[String: Any]])?.first)
            #expect(step["from"] as? String == plan.groups[0].source.path)
            #expect(step["to"] as? String == plan.groups[0].destination.path)
        }

        /// The staging URLs are fixed by the plan, so the journal names a parked file's real place.
        @Test func aStagedUnitRecordsTheStagingURLItIsParkedUnder() async throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let (direct, _, _) = try FileMoveCancellationTests.directPlan(100, in: dir)
            let a = try dir.file(named: "a.jpg", contents: "a")
            let b = try dir.file(named: "b.jpg", contents: "b")
            let plan = MovePlan(entries: [
                .move(MovePlan.Group(source: a, destination: b)),
                .move(MovePlan.Group(source: b, destination: a)),
            ] + direct.entries)

            let log = try MoveRunLog.create(in: Self.journals(in: dir), context: Data())
            let logURL = log.url
            let parkedWhileMoving = FileMoveCancellationTests.Reports()

            try await Task.detached {
                try FileCommands.move(plan, rollingBackOnFailure: false, log: log, progress: { finished, _ in
                    guard finished == 100 else { return }

                    let lines = (try? Self.lines(of: logURL)) ?? []
                    let staging = lines.filter { $0["kind"] as? String == "unit" }
                        .flatMap { $0["moves"] as? [[String: Any]] ?? [] }
                        .compactMap { $0["staging"] as? String }

                    parkedWhileMoving.append(staging.count, staging.filter { FileManager.default.fileExists(atPath: $0) }.count)
                })
            }.value

            #expect(parkedWhileMoving.values.map(\.finished) == [2])
            #expect(parkedWhileMoving.values.map(\.total) == [2])
            #expect(try String(contentsOf: a, encoding: .utf8) == "b")
            #expect(FileMoveCancellationTests.stagingNames(under: dir.url).isEmpty)
        }

        @Test func aFailureWhenRollingBackEndsWithEveryFinishedUnitRolledBack() async throws {
            let dir = try Sandbox()
            defer {
                try? dir.url.appendingPathComponent("locked").unlock()
                dir.remove()
            }

            let first = try dir.file(named: "A.jpg")
            let second = try dir.file(named: "B.jpg")
            let open = dir.url.appendingPathComponent("open", isDirectory: true)
            let locked = dir.url.appendingPathComponent("locked", isDirectory: true)
            try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
            try locked.lock()

            let plan = MovePlan(entries: [
                .move(MovePlan.Group(source: first, destination: open.appendingPathComponent("A.jpg"))),
                .move(MovePlan.Group(source: second, destination: locked.appendingPathComponent("B.jpg"))),
            ])
            let log = try MoveRunLog.create(in: Self.journals(in: dir), context: Data())

            await #expect(throws: (any Error).self) {
                try await Task.detached {
                    try FileCommands.move(plan, rollingBackOnFailure: true, log: log)
                }.value
            }

            let lines = try Self.lines(of: log.url)
            let done = lines.filter { $0["kind"] as? String == "done" }.flatMap { $0["units"] as? [Int] ?? [] }

            #expect(done == [0])
            #expect(lines.last?["kind"] as? String == "end")
            #expect(lines.last?["rolledBack"] as? [Int] == [0])
            #expect(first.exists && second.exists)
        }

        @Test func pendingListsJournalsOldestFirstAndRemoveDeletesOne() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let journals = Self.journals(in: dir)
            let older = try MoveRunLog.create(in: journals, context: Data())
            let newer = try MoveRunLog.create(in: journals, context: Data())

            func pending() -> [String] {
                MoveRunLog.pending(in: journals).map(\.lastPathComponent)
            }

            #expect(pending() == [older.url.lastPathComponent, newer.url.lastPathComponent])

            older.remove()

            #expect(pending() == [newer.url.lastPathComponent])
            #expect(!FileManager.default.fileExists(atPath: older.url.path))
        }

        @Test func noJournalFolderMeansNothingPending() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            #expect(MoveRunLog.pending(in: Self.journals(in: dir)).isEmpty)
        }
    }

#endif
