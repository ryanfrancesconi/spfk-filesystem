// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

#if os(macOS)

    import Foundation
    import SPFKBase

    /// The groups of a run in the order they can move, and the ones refused before anything does.
    struct MoveExecutionPlan {
        var units: [MoveUnit] = []
        var conflicts: [URL: FileCommandError] = [:]
    }

    /// A file and its companions, which move together.
    struct MoveUnit {
        let source: URL
        let destination: URL

        /// The owner's move first.
        var moves: [MoveStep]

        /// A destination is held by another file in the set, so this unit is parked under a
        /// temporary name until the rest have moved.
        var isStaged = false

        var companions: [URL: URL] {
            Dictionary(moves.filter(\.isCompanion).map { ($0.from, $0.to) }, uniquingKeysWith: { first, _ in first })
        }
    }

    struct MoveStep {
        let from: URL
        let to: URL
        let isCompanion: Bool

        /// Where a staged unit parks this file, fixed by the plan so a journal can name it before
        /// anything moves.
        var stagingURL: URL?

        func staging() -> MoveStep {
            MoveStep(from: from, to: stagingURL ?? FileCommands.renameStagingURL(for: from), isCompanion: isCompanion)
        }

        func fromStaging(_ staged: URL) -> MoveStep {
            MoveStep(from: staged, to: to, isCompanion: isCompanion)
        }
    }

    /// The files the set moves, found by path or, on a case-insensitive volume, by identity.
    struct MovingFiles {
        enum Occupant {
            case moving(URL)
            case outside
        }

        /// Each file with its standardized path, read once: standardizing touches the disk.
        private let byFoldedPath: [String: [(url: URL, path: String)]]

        init(_ urls: [URL]) {
            byFoldedPath = Dictionary(grouping: urls.map { ($0, $0.standardizedFileURL.path) }, by: { Self.folded($0.1) })
        }

        /// - Parameter path: `url.standardizedFileURL.path`.
        func occupant(of url: URL, standardizedPath path: String) -> Occupant? {
            let candidates = byFoldedPath[Self.folded(path)] ?? []

            if let exact = candidates.first(where: { $0.path == path }) {
                return .moving(exact.url)
            }

            guard FileManager.default.fileExists(atPath: url.path) else { return nil }

            if let same = candidates.first(where: { FileSystem.isSameFile($0.url, url) }) {
                return .moving(same.url)
            }

            return .outside
        }

        static func folded(_ standardizedPath: String) -> String {
            standardizedPath.decomposedStringWithCanonicalMapping.lowercased()
        }
    }

    /// Every move made so far, so a failure can undo them in reverse.
    struct MoveExecutionJournal {
        enum Phase {
            case staging, direct, final
        }

        private var done: [(move: MoveStep, phase: Phase, unit: Int)] = []
        private var staged: [URL: URL] = [:]

        /// The units that reached their destinations, in the order they did.
        private(set) var finished: [MoveUnit] = []

        /// Each finished unit's index in the plan, matching ``finished``.
        private(set) var finishedIndexes: [Int] = []
        private(set) var directSources: Set<URL> = []

        func stagedLocation(of url: URL) -> URL {
            staged[url] ?? url
        }

        mutating func finish(_ unit: MoveUnit, index: Int) {
            finished.append(unit)
            finishedIndexes.append(index)
        }

        /// One unit's moves. A failure undoes this unit's own moves before rethrowing, and throws
        /// ``FileCommandError/rollbackFailed(_:original:)`` instead when one cannot go back.
        ///
        /// - Parameter unit: the unit's index in the plan.
        mutating func perform(_ moves: [MoveStep], phase: Phase, unit: Int) throws {
            var made: [MoveStep] = []

            do {
                for move in moves {
                    try Self.move(move)
                    made.append(move)
                }
            } catch {
                let stranded = made.reversed().compactMap { Self.moveBack($0) }.first
                throw stranded ?? error
            }

            for move in made {
                done.append((move, phase, unit))
                if phase == .staging { staged[move.from] = move.to }
            }

            if phase == .direct, let owner = moves.first { directSources.insert(owner.from) }
        }

        /// Moves files back, newest first, carrying on past a failure. Keeping `.direct` moves is
        /// safe: their destinations were free of the set, so no staged file needs one to go back.
        /// Returns the first file stranded and the index of every unit with a file that stayed.
        mutating func rollBack(keepingDirect: Bool) -> (failure: FileCommandError?, strandedUnits: Set<Int>) {
            let undone = done.filter { !(keepingDirect && $0.phase == .direct) }
            done.removeAll { !(keepingDirect && $0.phase == .direct) }
            let kept = finished.map { keepingDirect && directSources.contains($0.source) }
            finished = zip(finished, kept).filter(\.1).map(\.0)
            finishedIndexes = zip(finishedIndexes, kept).filter(\.1).map(\.0)

            var firstFailure: FileCommandError?
            var strandedUnits: Set<Int> = []

            for entry in undone.reversed() {
                guard let failure = Self.moveBack(entry.move) else { continue }
                firstFailure = firstFailure ?? failure
                strandedUnits.insert(entry.unit)
            }

            return (firstFailure, strandedUnits)
        }

        private static func moveBack(_ move: MoveStep) -> FileCommandError? {
            do {
                try self.move(from: move.to, to: move.from)
                return nil
            } catch {
                Log.error("Couldn't move \(move.to.lastPathComponent) back to \(move.from.lastPathComponent)", error)
                return .rollbackFailed(move.to, original: move.from)
            }
        }

        private static func move(_ move: MoveStep) throws {
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
