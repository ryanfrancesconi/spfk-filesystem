// Copyright Ryan Francesconi. All Rights Reserved.

#if os(macOS)

    import Foundation
    import SPFKBase
    import SPFKTesting
    import Testing

    @testable import SPFKFileSystem

    /// ``MoveRunLog/recover(at:)`` over a copy's journal: a copy left under its hidden name may be
    /// partial, so it goes; a copy renamed into place is whole, so it stays.
    @Suite(.tags(.file, .renameOrganize))
    struct MoveRunLogCopyRecoveryTests {
        typealias Sandbox = FileCommandsTests.Sandbox
        typealias Helpers = MoveRunLogRecoveryTests

        @Test func aStagedCopyOfAnUnfinishedGroupIsRemoved() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let source = try dir.file(named: "a.jpg", contents: "a")
            let sidecar = try dir.file(named: "a.xmp", contents: "x")
            let target = dir.url.appendingPathComponent("Trip", isDirectory: true)
            let staging = target.appendingPathComponent(".spfk-rename-1-a.jpg")
            let sidecarStaging = target.appendingPathComponent(".spfk-rename-2-a.xmp")
            try Helpers.touch(staging, "partial")
            try Helpers.touch(sidecarStaging, "x")
            try sidecarStaging.lock()

            let url = try Helpers.journal(in: dir, units: [[
                Helpers.step(source, target.appendingPathComponent("a.jpg"), staging: staging),
                Helpers.step(sidecar, target.appendingPathComponent("a.xmp"), staging: sidecarStaging, companion: true),
            ]], operation: .copy)

            let recovered = try MoveRunLog.recover(at: url)

            #expect(recovered.moves.moved.isEmpty)
            #expect(recovered.moves.companions.isEmpty)
            #expect(recovered.context == Data("ctx".utf8))
            #expect(!FileManager.default.fileExists(atPath: staging.path))
            #expect(!FileManager.default.fileExists(atPath: sidecarStaging.path))
            #expect(Helpers.contents(source) == "a")
            #expect(Helpers.contents(sidecar) == "x")
        }

        @Test func aFinishedGroupsCopyStays() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let first = try dir.file(named: "a.jpg", contents: "a")
            let second = try dir.file(named: "b.jpg", contents: "b")
            let target = dir.url.appendingPathComponent("Trip", isDirectory: true)
            let copied = target.appendingPathComponent("a.jpg")
            let staging = target.appendingPathComponent(".spfk-rename-2-b.jpg")
            try Helpers.touch(copied, "a")
            try Helpers.touch(staging, "partial")

            let url = try Helpers.journal(in: dir, units: [
                [Helpers.step(first, copied, staging: target.appendingPathComponent(".spfk-rename-1-a.jpg"))],
                [Helpers.step(second, target.appendingPathComponent("b.jpg"), staging: staging)],
            ], done: [0], operation: .copy)

            let recovered = try MoveRunLog.recover(at: url)

            #expect(recovered.moves.moved.isEmpty)
            #expect(Helpers.contents(copied) == "a")
            #expect(!FileManager.default.fileExists(atPath: staging.path))
            #expect(Helpers.contents(second) == "b")
        }

        @Test func anEndedCopyJournalTouchesNothing() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let source = try dir.file(named: "a.jpg", contents: "a")
            let target = dir.url.appendingPathComponent("Trip", isDirectory: true)
            let copied = target.appendingPathComponent("a.jpg")
            try Helpers.touch(copied, "a")

            let url = try Helpers.journal(in: dir, units: [
                [Helpers.step(source, copied, staging: target.appendingPathComponent(".spfk-rename-1-a.jpg"))],
            ], done: [0], rolledBack: [], operation: .copy)
            let written = try Data(contentsOf: url)

            let recovered = try MoveRunLog.recover(at: url)

            #expect(recovered.moves.moved.isEmpty)
            #expect(Helpers.contents(copied) == "a")
            #expect(Helpers.contents(source) == "a")
            #expect(try Data(contentsOf: url) == written)
        }

        /// A journal written before copies existed has no operation, and reads as a move.
        @Test func aHeaderWithoutAnOperationIsAMove() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let url = try Helpers.journal(in: dir, units: [], operation: .move)
            let header = try #require(String(data: Data(contentsOf: url), encoding: .utf8)?.split(separator: "\n").first)

            #expect(!header.contains("operation"))
            #expect(try MoveRunLog.Contents(reading: url).operation == .move)

            let copy = try Helpers.journal(in: dir, units: [], operation: .copy)
            #expect(try MoveRunLog.Contents(reading: copy).operation == .copy)
        }
    }

#endif
