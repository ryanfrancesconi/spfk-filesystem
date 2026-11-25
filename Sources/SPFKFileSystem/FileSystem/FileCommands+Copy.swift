// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

#if os(macOS)

    import Foundation
    import SPFKBase

    extension FileCommands {
        /// Copies each of the plan's groups to its destination, leaving the sources in place and
        /// creating any missing destination folder. ``FileMoves/moved`` maps each source to its copy.
        ///
        /// Nothing is written until every destination has been checked; one that exists, or that
        /// two groups claim, throws. Each file is copied under a hidden name in its destination
        /// folder, cloned where the volume allows, and renamed into place once its whole group is
        /// copied, so a file at a destination is always whole. A copy of a locked file is unlocked.
        ///
        /// On a failure partway `rollingBackOnFailure` deletes every copy made and throws; otherwise
        /// the groups that finished stay and are returned with the error. Cancelling the calling
        /// task stops the run within the file being copied. `progress` reports bytes across the
        /// run, on the calling thread. `log` records the run as it goes.
        @discardableResult
        public nonisolated static func copy(
            _ plan: MovePlan,
            rollingBackOnFailure: Bool,
            log: MoveRunLog? = nil,
            progress: (@Sendable (_ copiedBytes: Int64, _ totalBytes: Int64) -> Void)? = nil
        ) throws -> FileMoves {
            try copy(plan, cloning: true, rollingBackOnFailure: rollingBackOnFailure, log: log, progress: progress)
        }

        /// Why each group of `plan` cannot be copied as part of the set, keyed by source. Empty when
        /// ``copy(_:rollingBackOnFailure:log:progress:)`` would start copying.
        public nonisolated static func copyConflicts(in plan: MovePlan) -> [URL: FileCommandError] {
            copyExecutionPlan(plan.groups).conflicts
        }

        /// - Parameter cloning: false forces a byte copy, as between volumes.
        nonisolated static func copy(
            _ plan: MovePlan,
            cloning: Bool,
            rollingBackOnFailure: Bool,
            log: MoveRunLog? = nil,
            progress: (@Sendable (_ copiedBytes: Int64, _ totalBytes: Int64) -> Void)? = nil
        ) throws -> FileMoves {
            let plan = copyExecutionPlan(plan.groups)

            if let (_, error) = plan.conflicts.min(by: { $0.key.path < $1.key.path }) {
                throw error
            }

            if Task.isCancelled {
                if rollingBackOnFailure { throw CancellationError() }
                return FileMoves(failure: CancellationError())
            }

            let createdFolders = try createDestinationFolders(for: plan.units)

            do {
                try log?.record(plan.units)
            } catch {
                removeUnusedFolders(createdFolders)
                throw error
            }

            let sizes = plan.units.map { $0.moves.map { Int64($0.from.fileSize ?? 0) } }
            let meter = CopyMeter(total: sizes.joined().reduce(0, +), report: progress)
            var finished: [Int] = []
            var unlogged: [Int] = []

            do {
                for (index, unit) in plan.units.enumerated() {
                    try Task.checkCancellation()
                    try copyUnit(unit, sizes: sizes[index], cloning: cloning, meter: meter)
                    finished.append(index)
                    unlogged.append(index)

                    if unlogged.count == 100 {
                        log?.recordDone(unlogged)
                        unlogged.removeAll()
                    }
                }

                log?.recordDone(unlogged)
                meter.finish()
            } catch {
                log?.recordDone(unlogged)

                guard rollingBackOnFailure else {
                    log?.recordEnd(rolledBack: [])
                    let inUse = removeUnusedFolders(createdFolders)
                    return copies(finished.map { plan.units[$0] }, createdFolders: inUse, failure: error)
                }

                for index in finished.reversed() {
                    removeCopies(plan.units[index].moves.reversed().map(\.to))
                }

                removeUnusedFolders(createdFolders)

                log?.recordEnd(rolledBack: finished)
                throw error
            }

            log?.recordEnd(rolledBack: [])

            return copies(plan.units, createdFolders: createdFolders, failure: nil)
        }

        // MARK: - Engine

        /// Every group as a unit whose steps each copy to a staging name beside the destination.
        nonisolated static func copyExecutionPlan(_ groups: [MovePlan.Group]) -> MoveExecutionPlan {
            var plan = MoveExecutionPlan()
            var claimedBy: [String: URL] = [:]

            for group in groups where plan.conflicts[group.source] == nil {
                let name = group.destination.lastPathComponent

                guard name.isNotEmpty, name != ".", name != ".." else {
                    plan.conflicts[group.source] = .invalidName(name)
                    continue
                }

                var steps = [MoveStep(from: group.source, to: group.destination, isCompanion: false)]
                steps += group.companions.map { MoveStep(from: $0.from, to: $0.to, isCompanion: true) }

                var refusal: FileCommandError?

                for step in steps {
                    let taken: FileCommandError = step.isCompanion ? .companionNameInUse(step.to) : .nameInUse(step.to)
                    let path = step.to.standardizedFileURL.path

                    if let claimant = claimedBy[path] {
                        refusal = refusal ?? (claimant == group.source ? .companionNameClash(step.to) : taken)
                        continue
                    }

                    claimedBy[path] = group.source

                    if FileManager.default.fileExists(atPath: step.to.path) {
                        refusal = refusal ?? taken
                    }
                }

                if let refusal {
                    plan.conflicts[group.source] = refusal
                    continue
                }

                for index in steps.indices {
                    steps[index].stagingURL = renameStagingURL(for: steps[index].to)
                }

                plan.units.append(MoveUnit(source: group.source, destination: group.destination, moves: steps))
            }

            return plan
        }

        /// Copies every file of `unit` to its staging name, then renames each into place. A failure
        /// removes what this unit wrote.
        private nonisolated static func copyUnit(_ unit: MoveUnit, sizes: [Int64], cloning: Bool, meter: CopyMeter) throws {
            var written: [URL] = []

            do {
                for (step, size) in zip(unit.moves, sizes) {
                    let staging = step.stagingURL ?? renameStagingURL(for: step.to)
                    written.append(staging)

                    try copyFile(step.from, to: staging, cloning: cloning, meter: meter)
                    if staging.isLocked { try staging.unlock() }

                    meter.fileFinished(size)
                }

                for step in unit.moves {
                    try renameIntoPlace(step.stagingURL ?? step.to, step)
                    written.append(step.to)
                }
            } catch {
                removeCopies(written.reversed())
                throw error
            }
        }

        /// Fails rather than replace a file that took the name since the check.
        private nonisolated static func renameIntoPlace(_ staging: URL, _ step: MoveStep) throws {
            guard renamex_np(staging.path, step.to.path, UInt32(RENAME_EXCL)) != 0 else { return }

            let code = errno

            if code == EEXIST {
                throw step.isCompanion ? FileCommandError.companionNameInUse(step.to) : FileCommandError.nameInUse(step.to)
            }

            throw posixError(code, url: step.to)
        }

        /// Deletes each file that exists, logging any that cannot be.
        private nonisolated static func removeCopies(_ urls: [URL]) {
            for url in urls where FileManager.default.fileExists(atPath: url.path) {
                do {
                    if url.isLocked { try url.unlock() }
                    try FileManager.default.removeItem(at: url)
                } catch {
                    Log.error("Couldn't remove the copy \(url.path)", error)
                }
            }
        }

        private nonisolated static func copies(_ units: [MoveUnit], createdFolders: [URL], failure: (any Error)?) -> FileMoves {
            var result = FileMoves(createdFolders: createdFolders, failure: failure)

            for unit in units {
                result.moved[unit.source] = unit.destination
                result.companions.merge(unit.companions) { first, _ in first }
            }

            return result
        }

        nonisolated static func posixError(_ code: Int32, url: URL) -> NSError {
            NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSFilePathErrorKey: url.path])
        }
    }

#endif
