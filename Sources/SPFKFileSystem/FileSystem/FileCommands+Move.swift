// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

#if os(macOS)

    import Foundation
    import SPFKBase

    extension FileCommands {
        /// Moves each of the plan's groups as one set, in an order that lets the set reuse its own
        /// names - a swap, a chain, a shift - creating any missing destination folder.
        ///
        /// Nothing moves until every destination has been checked; one held by a file outside the
        /// set throws. No file is ever left under a temporary name. On a failure partway
        /// `rollingBackOnFailure` moves every file back and throws; otherwise the groups that
        /// finished stay and are returned with the error.
        ///
        /// Cancelling the calling task stops the run between groups, as a failure does, with
        /// ``FileMoves/wasCancelled`` set. `progress` is called after every 100 finished groups and
        /// once at the end, on the calling thread. `log` records the run as it goes.
        @discardableResult
        public nonisolated static func move(
            _ plan: MovePlan,
            rollingBackOnFailure: Bool,
            log: MoveRunLog? = nil,
            progress: (@Sendable (_ finished: Int, _ total: Int) -> Void)? = nil
        ) throws -> FileMoves {
            try execute(executionPlan(plan.groups), rollingBackOnFailure: rollingBackOnFailure, log: log, progress: progress)
        }

        /// Why each group of `plan` cannot move as part of the set, keyed by source. Empty when
        /// ``move(_:rollingBackOnFailure:)`` would start moving files.
        ///
        /// A conflict depends on the rest of the set, so dropping a group can expose another.
        public nonisolated static func moveConflicts(in plan: MovePlan) -> [URL: FileCommandError] {
            executionPlan(plan.groups).conflicts
        }

        // MARK: - Engine

        /// - Parameter conflicts: refusals already decided, whose groups are left out.
        nonisolated static func executionPlan(_ groups: [MovePlan.Group], conflicts: [URL: FileCommandError] = [:]) -> MoveExecutionPlan {
            var plan = MoveExecutionPlan(conflicts: conflicts)

            for group in groups where group.source != group.destination && plan.conflicts[group.source] == nil {
                let name = group.destination.lastPathComponent

                guard name.isNotEmpty, name != ".", name != ".." else {
                    plan.conflicts[group.source] = .invalidName(name)
                    continue
                }

                guard !group.source.isLocked else {
                    plan.conflicts[group.source] = .locked(group.source)
                    continue
                }

                var moves = [MoveStep(from: group.source, to: group.destination, isCompanion: false)]

                for companion in group.companions where companion.from != companion.to {
                    moves.append(MoveStep(from: companion.from, to: companion.to, isCompanion: true))
                }

                plan.units.append(MoveUnit(source: group.source, destination: group.destination, moves: moves))
            }

            let moving = MovingFiles(plan.units.flatMap { $0.moves.map(\.from) })
            var claimedBy: [String: URL] = [:]

            for index in plan.units.indices {
                let source = plan.units[index].source

                for move in plan.units[index].moves {
                    let conflict: FileCommandError = move.isCompanion ? .companionNameInUse(move.to) : .nameInUse(move.to)
                    let path = move.to.standardizedFileURL.path

                    if let claimant = claimedBy[path] {
                        let refusal: FileCommandError = claimant == source ? .companionNameClash(move.to) : conflict
                        plan.conflicts[source] = plan.conflicts[source] ?? refusal
                        continue
                    }

                    claimedBy[path] = source

                    switch moving.occupant(of: move.to) {
                    case .none:
                        break
                    case let .moving(occupant) where occupant == move.from:
                        break
                    case .moving:
                        plan.units[index].isStaged = true
                    case .outside:
                        plan.conflicts[source] = plan.conflicts[source] ?? conflict
                    }
                }
            }

            plan.units.removeAll { plan.conflicts[$0.source] != nil }

            for index in plan.units.indices where plan.units[index].isStaged {
                for step in plan.units[index].moves.indices {
                    plan.units[index].moves[step].stagingURL = renameStagingURL(for: plan.units[index].moves[step].from)
                }
            }

            return plan
        }

        nonisolated static func execute(
            _ plan: MoveExecutionPlan,
            rollingBackOnFailure: Bool,
            log: MoveRunLog? = nil,
            progress: (@Sendable (_ finished: Int, _ total: Int) -> Void)? = nil
        ) throws -> FileMoves {
            if let (_, error) = plan.conflicts.min(by: { $0.key.path < $1.key.path }) {
                throw error
            }

            if Task.isCancelled {
                if rollingBackOnFailure { throw CancellationError() }
                return FileMoves(failure: CancellationError())
            }

            let createdFolders = try createDestinationFolders(for: plan.units)
            try log?.record(plan.units)

            var journal = MoveExecutionJournal()
            var unlogged: [Int] = []
            let total = plan.units.count

            func finish(_ index: Int) {
                journal.finish(plan.units[index], index: index)
                unlogged.append(index)

                if journal.finished.count.isMultiple(of: 100) {
                    flush()
                    progress?(journal.finished.count, total)
                }
            }

            func flush() {
                log?.recordDone(unlogged)
                unlogged.removeAll()
            }

            do {
                for unit in plan.units where unit.isStaged {
                    try Task.checkCancellation()
                    try journal.perform(unit.moves.map { $0.staging() }, phase: .staging)
                }

                for (index, unit) in plan.units.enumerated() where !unit.isStaged {
                    try Task.checkCancellation()
                    try journal.perform(unit.moves, phase: .direct)
                    finish(index)
                }

                flush()

                if plan.units.contains(where: \.isStaged) { log?.recordFinalPhase() }

                // Not cancellable: these units have left their sources, so finishing them is
                // cheaper than unwinding.
                for (index, unit) in plan.units.enumerated() where unit.isStaged {
                    let moves = unit.moves.map { $0.fromStaging(journal.stagedLocation(of: $0.from)) }
                    try journal.perform(moves, phase: .final)
                    finish(index)
                }

                flush()

                if !total.isMultiple(of: 100) { progress?(total, total) }
            } catch {
                flush()

                let before = Set(journal.finishedIndexes)

                if let rollbackError = journal.rollBack(keepingDirect: !rollingBackOnFailure) {
                    throw rollbackError
                }

                log?.recordEnd(rolledBack: before.subtracting(journal.finishedIndexes).sorted())

                if rollingBackOnFailure { throw error }

                return moves(journal.finished, createdFolders: createdFolders, failure: error)
            }

            log?.recordEnd(rolledBack: [])

            return moves(journal.finished, createdFolders: createdFolders, failure: nil)
        }

        private nonisolated static func moves(_ units: [MoveUnit], createdFolders: [URL], failure: (any Error)?) -> FileMoves {
            var result = FileMoves(createdFolders: createdFolders, failure: failure)

            for unit in units {
                result.moved[unit.source] = unit.destination
                result.companions.merge(unit.companions) { first, _ in first }
            }

            return result
        }

        /// Creates every destination folder that does not exist yet. Returns each one created,
        /// parents before children.
        nonisolated static func createDestinationFolders(for units: [MoveUnit]) throws -> [URL] {
            var created: [URL] = []
            var checked: Set<String> = []

            for folder in units.flatMap({ $0.moves.map { $0.to.deletingLastPathComponent() } }) {
                var missing: [URL] = []
                var candidate = folder.standardizedFileURL

                while checked.insert(candidate.path).inserted, !FileManager.default.fileExists(atPath: candidate.path) {
                    missing.append(candidate)
                    candidate = candidate.deletingLastPathComponent()
                }

                for url in missing.reversed() {
                    do {
                        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
                        created.append(url)
                    } catch let error as CocoaError where error.code == .fileWriteFileExists && url.isDirectory {
                        // Made by someone else since the check; it is not this run's to remove.
                        continue
                    }
                }
            }

            return created
        }
    }

#endif
