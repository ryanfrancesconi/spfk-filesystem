// Copyright Ryan Francesconi. All Rights Reserved.

#if os(macOS)

    import Foundation
    import SPFKBase
    import SPFKTesting
    import Testing

    @testable import SPFKFileSystem

    /// A group whose own undo fails strands a file: the run throws and leaves its journal open, so
    /// recovery settles that file from the disk.
    @Suite(.tags(.file, .renameOrganize))
    struct FileCommandsStrandedMoveTests {
        typealias Sandbox = FileCommandsTests.Sandbox

        /// A group moves, then the next one's owner moves into `folder`, its companion is gone, and
        /// the folder refuses to let the owner back out. The first group goes back only when rolling
        /// back, and recovery must agree.
        @Test(arguments: [true, false])
        func aGroupThatCannotUndoItselfLeavesTheJournalOpen(rollingBackOnFailure: Bool) throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let owner = try dir.file(named: "A.wav")
            let goneSidecar = dir.url.appendingPathComponent("A.xmp")
            let folder = dir.url.appendingPathComponent("Moved", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)

            try Self.chmod("+a", "everyone deny delete_child", folder)
            defer { try? Self.chmod("-a", "everyone deny delete_child", folder) }

            let earlier = try dir.file(named: "B.wav")
            let earlierMoved = dir.url.appendingPathComponent("Other/B.wav")
            let moved = folder.appendingPathComponent("A.wav")
            let plan = MovePlan(entries: [.move(MovePlan.Group(source: earlier, destination: earlierMoved)), .move(MovePlan.Group(
                source: owner,
                destination: moved,
                companions: [MovePlan.CompanionMove(from: goneSidecar, to: folder.appendingPathComponent("A.xmp"))]
            ))])

            let log = try MoveRunLog.create(in: dir.url.appendingPathComponent("Journals"), context: Data())

            #expect {
                try FileCommands.move(plan, rollingBackOnFailure: rollingBackOnFailure, log: log)
            } throws: { error in
                guard let error = error as? FileCommandError, case .rollbackFailed = error else { return false }
                return true
            }

            #expect(try MoveRunLog.Contents(reading: log.url).rolledBack == nil)
            #expect(moved.exists)
            #expect(earlierMoved.exists != rollingBackOnFailure)

            try Self.chmod("-a", "everyone deny delete_child", folder)
            let expected = rollingBackOnFailure ? [owner: moved] : [owner: moved, earlier: earlierMoved]
            #expect(try MoveRunLog.recover(at: log.url).moves.moved == expected)
        }

        private static func chmod(_ operation: String, _ entry: String, _ url: URL) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/chmod")
            process.arguments = [operation, entry, url.path]
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: url.path])
            }
        }
    }

#endif
