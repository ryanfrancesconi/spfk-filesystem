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
        let moves: [MoveStep]

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

        func staging() -> MoveStep {
            MoveStep(from: from, to: FileCommands.renameStagingURL(for: from), isCompanion: isCompanion)
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

        static func folded(_ url: URL) -> String {
            url.standardizedFileURL.path.decomposedStringWithCanonicalMapping.lowercased()
        }
    }

    /// Every move made so far, so a failure can undo them in reverse.
    struct MoveExecutionJournal {
        enum Phase {
            case staging, direct, final
        }

        private var done: [(move: MoveStep, phase: Phase)] = []
        private var staged: [URL: URL] = [:]

        /// The units that reached their destinations, in the order they did.
        private(set) var finished: [MoveUnit] = []
        private(set) var directSources: Set<URL> = []

        func stagedLocation(of url: URL) -> URL {
            staged[url] ?? url
        }

        mutating func finish(_ unit: MoveUnit) {
            finished.append(unit)
        }

        /// One unit's moves. A failure undoes this unit's own moves before rethrowing.
        mutating func perform(_ moves: [MoveStep], phase: Phase) throws {
            var made: [MoveStep] = []

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
            finished.removeAll { !(keepingDirect && directSources.contains($0.source)) }

            return Self.moveBack(undone)
        }

        /// Reverses `moves`, last first, carrying on past a failure. Returns the first file stranded.
        private static func moveBack(_ moves: [MoveStep]) -> FileCommandError? {
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
