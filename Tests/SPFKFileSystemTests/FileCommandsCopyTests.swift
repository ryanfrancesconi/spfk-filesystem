// Copyright Ryan Francesconi. All Rights Reserved.

#if os(macOS)

    import Foundation
    import SPFKBase
    import SPFKTesting
    import Testing

    @testable import SPFKFileSystem

    /// ``FileCommands/copy(_:rollingBackOnFailure:log:progress:)``: each group copied beside a
    /// hidden name in its destination folder, then renamed into place.
    @Suite(.tags(.file, .renameOrganize))
    struct FileCommandsCopyTests {
        typealias Sandbox = FileCommandsTests.Sandbox
        typealias Reports = FileMoveCancellationTests.Reports

        private static func group(_ source: URL, _ destination: URL, companions: [(URL, URL)] = []) -> MovePlan.Entry {
            .move(MovePlan.Group(
                source: source,
                destination: destination,
                companions: companions.map { MovePlan.CompanionMove(from: $0.0, to: $0.1) }
            ))
        }

        private static func names(in folder: URL) -> Set<String> {
            FileMoveCancellationTests.names(in: folder)
        }

        private static func stagingNames(under url: URL) -> [String] {
            FileMoveCancellationTests.stagingNames(under: url)
        }

        private static func cancelCurrentTask() {
            withUnsafeCurrentTask { $0?.cancel() }
        }

        /// `count` files of `bytes` each in `from`, each copied to the same name in `to`.
        private static func plan(_ count: Int, bytes: Int, in dir: Sandbox) throws -> (plan: MovePlan, from: URL, to: URL) {
            let from = dir.url.appendingPathComponent("from", isDirectory: true)
            let to = dir.url.appendingPathComponent("to", isDirectory: true)
            try FileManager.default.createDirectory(at: from, withIntermediateDirectories: true)

            var entries: [MovePlan.Entry] = []

            for index in 0 ..< count {
                let name = String(format: "%04d.mov", index)
                let source = from.appendingPathComponent(name)
                try Data(repeating: UInt8(index % 256), count: bytes).write(to: source)
                entries.append(group(source, to.appendingPathComponent(name)))
            }

            return (MovePlan(entries: entries), from, to)
        }

        @Test func aGroupIsCopiedWithItsCompanionsAndTheSourceStays() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let raw = try dir.file(named: "A.RAF", contents: "raw")
            let sidecar = try dir.file(named: "A.xmp", contents: "sidecar")
            let target = dir.url.appendingPathComponent("Trip", isDirectory: true)
            let copy = target.appendingPathComponent("Trip_001.RAF")
            let copiedSidecar = target.appendingPathComponent("Trip_001.xmp")

            let copies = try FileCommands.copy(MovePlan(entries: [
                Self.group(raw, copy, companions: [(sidecar, copiedSidecar)]),
            ]), rollingBackOnFailure: false)

            #expect(copies.moved == [raw: copy])
            #expect(copies.companions == [sidecar: copiedSidecar])
            #expect(copies.failure == nil)
            #expect(Self.names(in: target) == ["Trip_001.RAF", "Trip_001.xmp"])
            #expect(try String(contentsOf: copy, encoding: .utf8) == "raw")
            #expect(try String(contentsOf: copiedSidecar, encoding: .utf8) == "sidecar")
            #expect(try String(contentsOf: raw, encoding: .utf8) == "raw")
            #expect(try String(contentsOf: sidecar, encoding: .utf8) == "sidecar")
        }

        @Test func aCopyBesideItsSourceUnderANewName() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let photo = try dir.file(named: "IMG_1.jpg", contents: "photo")
            let copy = dir.url.appendingPathComponent("IMG_1 1.jpg")

            let copies = try FileCommands.copy(MovePlan(entries: [Self.group(photo, copy)]), rollingBackOnFailure: false)

            #expect(copies.moved == [photo: copy])
            #expect(try Set(dir.names()) == ["IMG_1.jpg", "IMG_1 1.jpg"])
        }

        @Test func anExistingDestinationIsRefusedBeforeAnythingIsWritten() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let a = try dir.file(named: "a.jpg")
            let b = try dir.file(named: "b.jpg")
            let target = dir.url.appendingPathComponent("Trip", isDirectory: true)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            let taken = target.appendingPathComponent("b.jpg")
            try Data("other".utf8).write(to: taken)

            let plan = MovePlan(entries: [
                Self.group(a, target.appendingPathComponent("a.jpg")),
                Self.group(b, taken),
            ])

            #expect(FileCommands.copyConflicts(in: plan) == [b: .nameInUse(taken)])

            #expect(throws: FileCommandError.nameInUse(taken)) {
                try FileCommands.copy(plan, rollingBackOnFailure: false)
            }

            #expect(Self.names(in: target) == ["b.jpg"])
            #expect(try String(contentsOf: taken, encoding: .utf8) == "other")
        }

        @Test func twoGroupsClaimingOneDestinationAreRefused() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let a = try dir.file(named: "a.jpg")
            let b = try dir.file(named: "b.jpg")
            let destination = dir.url.appendingPathComponent("Trip/x.jpg")

            let plan = MovePlan(entries: [Self.group(a, destination), Self.group(b, destination)])

            #expect(FileCommands.copyConflicts(in: plan) == [b: .nameInUse(destination)])
        }

        @Test func twoCompanionsTakingOneNameAreRefused() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let raw = try dir.file(named: "A.RAF")
            let first = try dir.file(named: "A.xmp")
            let second = try dir.file(named: "A.XMP.xmp")
            let sidecar = dir.url.appendingPathComponent("Trip/B.xmp")

            let plan = MovePlan(entries: [
                Self.group(raw, dir.url.appendingPathComponent("Trip/B.RAF"), companions: [(first, sidecar), (second, sidecar)]),
            ])

            #expect(FileCommands.copyConflicts(in: plan) == [raw: .companionNameClash(sidecar)])
        }

        @Test func aLockedSourceIsCopiedAndItsCopyIsUnlocked() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let source = try dir.file(named: "locked.jpg", contents: "locked")
            try source.lock()
            let copy = dir.url.appendingPathComponent("Trip/locked.jpg")

            #expect(FileCommands.copyConflicts(in: MovePlan(entries: [Self.group(source, copy)])).isEmpty)

            let copies = try FileCommands.copy(MovePlan(entries: [Self.group(source, copy)]), rollingBackOnFailure: false)

            #expect(copies.moved == [source: copy])
            #expect(source.isLocked)
            #expect(!copy.isLocked)
            #expect(try String(contentsOf: copy, encoding: .utf8) == "locked")
        }

        @Test func missingFoldersAreCreatedAndListed() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let photo = try dir.file(named: "A.jpg")
            let target = dir.url.appendingPathComponent("2026/11", isDirectory: true)

            let copies = try FileCommands.copy(MovePlan(entries: [
                Self.group(photo, target.appendingPathComponent("A.jpg")),
            ]), rollingBackOnFailure: false)

            #expect(copies.createdFolders.map(\.standardizedFileURL.path) == [
                target.deletingLastPathComponent().standardizedFileURL.path,
                target.standardizedFileURL.path,
            ])
        }

        @Test func aFailurePartwayKeepsTheEarlierGroups() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let (plan, from, to) = try Self.plan(2, bytes: 3, in: dir)
            let second = from.appendingPathComponent("0001.mov")
            try FileManager.default.removeItem(at: second)

            let copies = try FileCommands.copy(plan, rollingBackOnFailure: false)

            #expect(copies.moved == [from.appendingPathComponent("0000.mov"): to.appendingPathComponent("0000.mov")])
            #expect(copies.failure != nil)
            #expect(!copies.wasCancelled)
            #expect(copies.createdFolders.map(\.standardizedFileURL.path) == [to.standardizedFileURL.path])
            #expect(Self.names(in: to) == ["0000.mov"])
            #expect(Self.stagingNames(under: dir.url).isEmpty)
        }

        @Test func rollingBackOnFailureDeletesWhatItCopied() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let (plan, from, to) = try Self.plan(2, bytes: 3, in: dir)
            try FileManager.default.removeItem(at: from.appendingPathComponent("0001.mov"))

            #expect(throws: (any Error).self) {
                try FileCommands.copy(plan, rollingBackOnFailure: true)
            }

            #expect(Self.names(in: to).isEmpty)
            #expect(Self.names(in: from) == ["0000.mov"])
            #expect(Self.stagingNames(under: dir.url).isEmpty)
        }

        @Test func aCancelBetweenGroupsKeepsTheEarlierGroups() async throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let (plan, from, to) = try Self.plan(3, bytes: 1_048_576, in: dir)

            let copies = try await Task.detached {
                try FileCommands.copy(plan, rollingBackOnFailure: false, progress: { _, _ in Self.cancelCurrentTask() })
            }.value

            #expect(copies.wasCancelled)
            #expect(copies.moved == [from.appendingPathComponent("0000.mov"): to.appendingPathComponent("0000.mov")])
            #expect(Self.names(in: to) == ["0000.mov"])
            #expect(Self.names(in: from).count == 3)
            #expect(Self.stagingNames(under: dir.url).isEmpty)
        }

        /// A byte copy, as across disks, stops inside the file rather than after it.
        @Test func aCancelWithinAFileLeavesNoPartialCopy() async throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let (plan, from, to) = try Self.plan(1, bytes: 32 * 1_048_576, in: dir)
            let reports = Reports()

            let copies = try await Task.detached {
                try FileCommands.copy(plan, cloning: false, rollingBackOnFailure: false, progress: { copied, total in
                    reports.append(Int(copied), Int(total))
                    Self.cancelCurrentTask()
                })
            }.value

            #expect(copies.wasCancelled)
            #expect(copies.moved.isEmpty)
            #expect(reports.values.first.map { $0.finished < $0.total } == true)
            #expect(Self.names(in: to).isEmpty)
            #expect(Self.names(in: from).count == 1)
            #expect(Self.stagingNames(under: dir.url).isEmpty)
        }

        @Test func aCancelWhenRollingBackDeletesEverythingAndThrows() async throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let (plan, _, to) = try Self.plan(3, bytes: 1_048_576, in: dir)

            await #expect(throws: CancellationError.self) {
                try await Task.detached {
                    try FileCommands.copy(plan, rollingBackOnFailure: true, progress: { _, _ in Self.cancelCurrentTask() })
                }.value
            }

            #expect(Self.names(in: to).isEmpty)
        }

        @Test func byteProgressEndsAtTheTotal() async throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let raw = try dir.file(named: "A.RAF", contents: "raw")
            let sidecar = try dir.file(named: "A.xmp", contents: "sidecar")
            let photo = try dir.file(named: "B.jpg", contents: "photo")
            let target = dir.url.appendingPathComponent("Trip", isDirectory: true)
            let plan = MovePlan(entries: [
                Self.group(raw, target.appendingPathComponent("A.RAF"), companions: [(sidecar, target.appendingPathComponent("A.xmp"))]),
                Self.group(photo, target.appendingPathComponent("B.jpg")),
            ])
            let reports = Reports()

            _ = try await Task.detached {
                try FileCommands.copy(plan, rollingBackOnFailure: false, progress: { reports.append(Int($0), Int($1)) })
            }.value

            let total = "raw".utf8.count + "sidecar".utf8.count + "photo".utf8.count

            #expect(reports.values.last.map { $0.finished == total && $0.total == total } == true)
            #expect(reports.values.allSatisfy { $0.total == total })
            #expect(reports.values.map(\.finished) == reports.values.map(\.finished).sorted())
        }

        @Test func aJournaledCopyRecoversToNothingAndKeepsItsCopies() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let (plan, _, to) = try Self.plan(2, bytes: 3, in: dir)
            let log = try MoveRunLog.create(in: dir.url.appendingPathComponent("Journals"), context: Data(), operation: .copy)

            _ = try FileCommands.copy(plan, rollingBackOnFailure: false, log: log)
            let recovered = try MoveRunLog.recover(at: log.url)

            #expect(recovered.moves.moved.isEmpty)
            #expect(Self.names(in: to) == ["0000.mov", "0001.mov"])
        }
    }

#endif
