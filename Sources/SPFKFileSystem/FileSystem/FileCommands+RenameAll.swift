// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

#if os(macOS)

    import Foundation
    import SPFKBase

    /// What ``FileCommands/renameAll(_:rollingBackOnFailure:)`` did.
    public struct FileRenames: Sendable {
        /// Source → its new URL, for each file renamed. Companions are not listed.
        public var renamed: [URL: URL] = [:]

        /// The first failure, when the set was not rolled back. Every file missing from ``renamed``
        /// is where it began.
        public var failure: (any Error)?
    }

    extension FileCommands {
        /// Renames each key to its value as one set, in an order that lets the set reuse its own
        /// names - a swap, a chain, a shift - with companions following their owners.
        ///
        /// Nothing moves until every destination and every companion's has been checked; one held
        /// by a file outside the set throws. No file is ever left under a temporary name. On a
        /// failure partway `rollingBackOnFailure` moves every file back and throws; otherwise the
        /// finished renames stay and are returned with the error.
        @discardableResult
        public static func renameAll(_ mapping: [URL: URL], rollingBackOnFailure: Bool) throws -> FileRenames {
            let plan = renamePlan(mapping)

            if let (_, error) = plan.conflicts.min(by: { $0.key.path < $1.key.path }) {
                throw error
            }

            var journal = RenameJournal()

            do {
                for unit in plan.units where unit.isStaged {
                    try journal.perform(unit.moves.map { $0.staging() }, phase: .staging)
                }

                for unit in plan.units where !unit.isStaged {
                    try journal.perform(unit.moves, phase: .direct)
                    journal.finished[unit.source] = unit.destination
                }

                for unit in plan.units where unit.isStaged {
                    let moves = unit.moves.map { $0.fromStaging(journal.stagedLocation(of: $0.from)) }
                    try journal.perform(moves, phase: .final)
                    journal.finished[unit.source] = unit.destination
                }
            } catch {
                if let rollbackError = journal.rollBack(keepingDirect: !rollingBackOnFailure) {
                    throw rollbackError
                }

                if rollingBackOnFailure { throw error }

                return FileRenames(renamed: journal.finished.filter { journal.directSources.contains($0.key) }, failure: error)
            }

            return FileRenames(renamed: journal.finished)
        }

        /// Why each entry of `mapping` cannot be renamed as part of the set, keyed by source. Empty
        /// when ``renameAll(_:rollingBackOnFailure:)`` would start moving files.
        ///
        /// A conflict depends on the rest of the set, so dropping an entry can expose another.
        public static func renameConflicts(in mapping: [URL: URL]) -> [URL: FileCommandError] {
            renamePlan(mapping).conflicts
        }

        // MARK: - Plan

        private static func renamePlan(_ mapping: [URL: URL]) -> RenamePlan {
            var plan = RenamePlan()

            for (source, destination) in mapping where source != destination {
                let name = destination.lastPathComponent

                guard name.isNotEmpty, name != ".", name != "..",
                      destination.deletingLastPathComponent().standardizedFileURL.path
                      == source.deletingLastPathComponent().standardizedFileURL.path
                else {
                    plan.conflicts[source] = .invalidName(name)
                    continue
                }

                guard !source.isLocked else {
                    plan.conflicts[source] = .locked(source)
                    continue
                }

                var moves = [RenameMove(from: source, to: destination, isCompanion: false)]

                for companion in source.existingCompanionURLs {
                    let companionDestination = companion.companionDestination(forOwner: destination)
                    guard companionDestination != companion else { continue }

                    moves.append(RenameMove(from: companion, to: companionDestination, isCompanion: true))
                }

                plan.units.append(RenameUnit(source: source, destination: destination, moves: moves))
            }

            let moving = MovingFiles(plan.units.flatMap { $0.moves.map(\.from) })
            var claimed: Set<String> = []

            for index in plan.units.indices {
                for move in plan.units[index].moves {
                    let conflict: FileCommandError = move.isCompanion ? .companionNameInUse(move.to) : .nameInUse(move.to)

                    guard claimed.insert(move.to.standardizedFileURL.path).inserted else {
                        plan.conflicts[plan.units[index].source] = plan.conflicts[plan.units[index].source] ?? conflict
                        continue
                    }

                    switch moving.occupant(of: move.to) {
                    case .none:
                        break
                    case let .moving(occupant) where occupant == move.from:
                        break
                    case .moving:
                        plan.units[index].isStaged = true
                    case .outside:
                        plan.conflicts[plan.units[index].source] = plan.conflicts[plan.units[index].source] ?? conflict
                    }
                }
            }

            plan.units.removeAll { plan.conflicts[$0.source] != nil }

            return plan
        }

        /// A hidden name beside `url` to park it under while the set reuses its name. Never the
        /// render-sibling shape, which a sweep deletes.
        nonisolated static func renameStagingURL(for url: URL) -> URL {
            url.deletingLastPathComponent().appendingPathComponent(".spfk-rename-\(UUID().uuidString)-\(url.lastPathComponent)")
        }
    }

    // MARK: - Types

    private struct RenamePlan {
        var units: [RenameUnit] = []
        var conflicts: [URL: FileCommandError] = [:]
    }

    /// A file and its companions, which move together.
    private struct RenameUnit {
        let source: URL
        let destination: URL

        /// The owner's move first.
        let moves: [RenameMove]

        /// A destination is held by another file in the set, so this unit is parked under a
        /// temporary name until the rest have moved.
        var isStaged = false
    }

    private struct RenameMove {
        let from: URL
        let to: URL
        let isCompanion: Bool

        func staging() -> RenameMove {
            RenameMove(from: from, to: FileCommands.renameStagingURL(for: from), isCompanion: isCompanion)
        }

        func fromStaging(_ staged: URL) -> RenameMove {
            RenameMove(from: staged, to: to, isCompanion: isCompanion)
        }
    }

    /// The files the set moves, found by path or, on a case-insensitive volume, by identity.
    private struct MovingFiles {
        enum Occupant {
            case moving(URL)
            case outside
        }

        private let byFoldedPath: [String: [URL]]

        init(_ urls: [URL]) {
            byFoldedPath = Dictionary(grouping: urls, by: { Self.folded($0) })
        }

        func occupant(of url: URL) -> Occupant? {
            let candidates = byFoldedPath[Self.folded(url)] ?? []
            let path = url.standardizedFileURL.path

            if let exact = candidates.first(where: { $0.standardizedFileURL.path == path }) {
                return .moving(exact)
            }

            guard FileManager.default.fileExists(atPath: url.path) else { return nil }

            if let same = candidates.first(where: { FileSystem.isSameFile($0, url) }) {
                return .moving(same)
            }

            return .outside
        }

        private static func folded(_ url: URL) -> String {
            url.standardizedFileURL.path.decomposedStringWithCanonicalMapping.lowercased()
        }
    }

    /// Every move made so far, so a failure can undo them in reverse.
    private struct RenameJournal {
        enum Phase {
            case staging, direct, final
        }

        private var done: [(move: RenameMove, phase: Phase)] = []
        private var staged: [URL: URL] = [:]

        var finished: [URL: URL] = [:]
        private(set) var directSources: Set<URL> = []

        func stagedLocation(of url: URL) -> URL {
            staged[url] ?? url
        }

        /// One unit's moves. A failure undoes this unit's own moves before rethrowing.
        mutating func perform(_ moves: [RenameMove], phase: Phase) throws {
            var made: [RenameMove] = []

            do {
                for move in moves {
                    try Self.move(move)
                    made.append(move)
                }
            } catch {
                if let stranded = Self.moveBack(made) { throw stranded }
                throw error
            }

            for move in made {
                done.append((move, phase))
                if phase == .staging { staged[move.from] = move.to }
            }

            if phase == .direct, let owner = moves.first { directSources.insert(owner.from) }
        }

        /// Moves files back, newest first. Keeping `.direct` moves is safe: their destinations were
        /// free of the set, so no staged file needs one to go back. Returns the first file stranded.
        mutating func rollBack(keepingDirect: Bool) -> FileCommandError? {
            let undone = done.filter { !(keepingDirect && $0.phase == .direct) }.map(\.move)
            done.removeAll { !(keepingDirect && $0.phase == .direct) }

            return Self.moveBack(undone)
        }

        /// Reverses `moves`, last first, carrying on past a failure. Returns the first file stranded.
        private static func moveBack(_ moves: [RenameMove]) -> FileCommandError? {
            var firstFailure: FileCommandError?

            for move in moves.reversed() {
                do {
                    try self.move(from: move.to, to: move.from)
                } catch {
                    Log.error("Couldn't move \(move.to.lastPathComponent) back to \(move.from.lastPathComponent)", error)
                    firstFailure = firstFailure ?? .rollbackFailed(move.to, original: move.from)
                }
            }

            return firstFailure
        }

        private static func move(_ move: RenameMove) throws {
            do {
                try self.move(from: move.from, to: move.to)
            } catch let error as NSError where error.code == NSFileWriteFileExistsError {
                throw move.isCompanion ? FileCommandError.companionNameInUse(move.to) : FileCommandError.nameInUse(move.to)
            }
        }

        private static func move(from: URL, to: URL) throws {
            try from.withSecurityScopedAccess {
                try FileManager.default.moveItem(at: from, to: to)
            }
        }
    }

#endif
