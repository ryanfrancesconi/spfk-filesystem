// Copyright Ryan Francesconi. All Rights Reserved.

#if os(macOS)

    import Foundation
    import SPFKBase
    import SPFKTesting
    import Testing

    @testable import SPFKFileSystem

    /// ``FileCommands/move(_:rollingBackOnFailure:log:progress:)`` run off the main actor, stopped
    /// by its task's cancellation.
    @Suite(.tags(.file, .renameOrganize))
    struct FileMoveCancellationTests {
        typealias Sandbox = FileCommandsTests.Sandbox

        /// `count` files in `from`, each moving to the same name in `to`.
        static func directPlan(_ count: Int, in dir: Sandbox) throws -> (plan: MovePlan, from: URL, to: URL) {
            let from = dir.url.appendingPathComponent("from", isDirectory: true)
            let to = dir.url.appendingPathComponent("to", isDirectory: true)
            try FileManager.default.createDirectory(at: from, withIntermediateDirectories: true)

            var entries: [MovePlan.Entry] = []

            for index in 0 ..< count {
                let name = String(format: "%04d.jpg", index)
                let source = from.appendingPathComponent(name)
                try Data().write(to: source)
                entries.append(.move(MovePlan.Group(source: source, destination: to.appendingPathComponent(name))))
            }

            return (MovePlan(entries: entries), from, to)
        }

        static func names(in folder: URL) -> Set<String> {
            Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        }

        static func stagingNames(under url: URL) -> [String] {
            let all = FileManager.default.enumerator(atPath: url.path)?.allObjects as? [String] ?? []
            return all.filter { ($0 as NSString).lastPathComponent.hasPrefix(".spfk-rename-") }
        }

        private static func cancelCurrentTask() {
            withUnsafeCurrentTask { $0?.cancel() }
        }

        @Test func aDetachedMoveMovesEveryFile() async throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let (plan, from, to) = try Self.directPlan(3, in: dir)

            let moves = try await Task.detached {
                try FileCommands.move(plan, rollingBackOnFailure: false)
            }.value

            #expect(moves.moved.count == 3)
            #expect(!moves.wasCancelled)
            #expect(Self.names(in: from).isEmpty)
            #expect(Self.names(in: to).count == 3)
        }

        @Test func aTaskCancelledBeforeTheFirstUnitMovesNothing() async throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let (plan, from, _) = try Self.directPlan(5, in: dir)

            let moves = try await Task.detached {
                Self.cancelCurrentTask()
                return try FileCommands.move(plan, rollingBackOnFailure: false)
            }.value

            #expect(moves.wasCancelled)
            #expect(moves.moved.isEmpty)
            #expect(Self.names(in: from).count == 5)
        }

        @Test func aCancelAtTheFirstReportKeepsTheFirstHundred() async throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let (plan, from, to) = try Self.directPlan(250, in: dir)

            let moves = try await Task.detached {
                try FileCommands.move(plan, rollingBackOnFailure: false, progress: { _, _ in Self.cancelCurrentTask() })
            }.value

            let firstHundred = Set(plan.groups.prefix(100).map(\.destination.lastPathComponent))

            #expect(moves.wasCancelled)
            #expect(Set(moves.moved.values.map(\.lastPathComponent)) == firstHundred)
            #expect(Self.names(in: to) == firstHundred)
            #expect(Self.names(in: from).count == 150)
            #expect(Self.stagingNames(under: dir.url).isEmpty)
        }

        /// The parked unit goes back; the direct units that finished stay.
        @Test func aCancelDuringStagingMovesTheParkedUnitBack() async throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let (direct, from, to) = try Self.directPlan(200, in: dir)
            let a = try dir.file(named: "a.jpg", contents: "a")
            let b = try dir.file(named: "b.jpg", contents: "b")
            let plan = MovePlan(entries: [
                .move(MovePlan.Group(source: a, destination: b)),
                .move(MovePlan.Group(source: b, destination: a)),
            ] + direct.entries)

            let moves = try await Task.detached {
                try FileCommands.move(plan, rollingBackOnFailure: false, progress: { _, _ in Self.cancelCurrentTask() })
            }.value

            #expect(moves.wasCancelled)
            #expect(moves.moved.count == 100)
            #expect(moves.moved[a] == nil && moves.moved[b] == nil)
            #expect(try String(contentsOf: a, encoding: .utf8) == "a")
            #expect(try String(contentsOf: b, encoding: .utf8) == "b")
            #expect(Self.names(in: to).count == 100)
            #expect(Self.names(in: from).count == 100)
            #expect(Self.stagingNames(under: dir.url).isEmpty)
        }

        @Test func aCancelWhenRollingBackMovesEverythingBackAndThrows() async throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let (plan, from, to) = try Self.directPlan(250, in: dir)

            await #expect(throws: CancellationError.self) {
                try await Task.detached {
                    try FileCommands.move(plan, rollingBackOnFailure: true, progress: { _, _ in Self.cancelCurrentTask() })
                }.value
            }

            #expect(Self.names(in: from).count == 250)
            #expect(Self.names(in: to).isEmpty)
        }

        @Test func progressReportsEveryHundredAndTheEnd() async throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let (plan, _, _) = try Self.directPlan(250, in: dir)
            let reports = Reports()

            try await Task.detached {
                try FileCommands.move(plan, rollingBackOnFailure: false, progress: { reports.append($0, $1) })
            }.value

            #expect(reports.values.map(\.finished) == [100, 200, 250])
            #expect(reports.values.allSatisfy { $0.total == 250 })
        }

        final class Reports: @unchecked Sendable {
            private let lock = NSLock()
            private var stored: [(finished: Int, total: Int)] = []

            var values: [(finished: Int, total: Int)] { lock.withLock { stored } }

            func append(_ finished: Int, _ total: Int) {
                lock.withLock { stored.append((finished, total)) }
            }
        }
    }

#endif
