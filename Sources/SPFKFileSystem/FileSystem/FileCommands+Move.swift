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
        @discardableResult
        public static func move(_ plan: MovePlan, rollingBackOnFailure: Bool) throws -> FileMoves {
            try execute(executionPlan(plan.groups), rollingBackOnFailure: rollingBackOnFailure)
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

            return plan
        }

        static func execute(_ plan: MoveExecutionPlan, rollingBackOnFailure: Bool) throws -> FileMoves {
            if let (_, error) = plan.conflicts.min(by: { $0.key.path < $1.key.path }) {
                throw error
            }

            let createdFolders = try createDestinationFolders(for: plan.units)
            var journal = MoveExecutionJournal()

            do {
                for unit in plan.units where unit.isStaged {
                    try journal.perform(unit.moves.map { $0.staging() }, phase: .staging)
                }

                for unit in plan.units where !unit.isStaged {
                    try journal.perform(unit.moves, phase: .direct)
                    journal.finish(unit)
                }

                for unit in plan.units where unit.isStaged {
                    let moves = unit.moves.map { $0.fromStaging(journal.stagedLocation(of: $0.from)) }
                    try journal.perform(moves, phase: .final)
                    journal.finish(unit)
                }
            } catch {
                if let rollbackError = journal.rollBack(keepingDirect: !rollingBackOnFailure) {
                    throw rollbackError
                }

                if rollingBackOnFailure { throw error }

                return moves(journal.finished, createdFolders: createdFolders, failure: error)
            }

            return moves(journal.finished, createdFolders: createdFolders, failure: nil)
        }

        private static func moves(_ units: [MoveUnit], createdFolders: [URL], failure: (any Error)?) -> FileMoves {
            var result = FileMoves(createdFolders: createdFolders, failure: failure)

            for unit in units {
                result.moved[unit.source] = unit.destination
                result.companions.merge(unit.companions) { first, _ in first }
            }

            return result
        }

        /// Creates every destination folder that does not exist yet. Returns each one created,
        /// parents before children.
        private static func createDestinationFolders(for units: [MoveUnit]) throws -> [URL] {
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
                    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
                    created.append(url)
                }
            }

            return created
        }
    }

#endif
