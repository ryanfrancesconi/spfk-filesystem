// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

#if os(macOS)

    import Foundation
    import SPFKBase

    /// What an interrupted run moved, read back from its journal.
    public struct RecoveredMoves: Sendable {
        /// The context the journal was created with.
        public let context: Data

        public let moves: FileMoves
    }

    extension MoveRunLog {
        /// The groups the journaled run moved, after bringing the disk to a state where no file is
        /// left under a temporary name and every group is whole.
        ///
        /// A journal that ended is answered from its lines alone. Otherwise each group not
        /// recorded as finished is read from disk: a parked file goes on to its destination if
        /// that is free, else back; then its companions join the owner, wherever it ended. The
        /// answer is appended to the journal, so a second recovery returns it without touching
        /// the disk. A step that can go neither way is left where it is and logged.
        public static func recover(at url: URL) throws -> RecoveredMoves {
            let journal = try Contents(reading: url)

            if let rolledBack = journal.rolledBack {
                let moved = journal.done.subtracting(rolledBack)
                return RecoveredMoves(context: journal.context, moves: moves(of: moved, in: journal.units))
            }

            var moved = journal.done

            for (index, steps) in journal.units.sorted(by: { $0.key < $1.key }) where !journal.done.contains(index) {
                if Self.settle(steps, finalPhaseBegan: journal.finalPhaseBegan) {
                    moved.insert(index)
                }
            }

            var lines = try line(Record(kind: .done, units: moved.sorted()))
            lines.append(try line(Record(kind: .end, rolledBack: [])))

            // Drops a last line cut short, so the next reading finds whole lines only.
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.truncate(atOffset: UInt64(journal.wholeLinesLength))
            try handle.seekToEnd()
            try handle.write(contentsOf: lines)

            return RecoveredMoves(context: journal.context, moves: moves(of: moved, in: journal.units))
        }

        private static func moves(of indexes: Set<Int>, in units: [Int: [Record.Step]]) -> FileMoves {
            var result = FileMoves()

            for index in indexes {
                guard let steps = units[index], let owner = steps.first else { continue }

                result.moved[URL(fileURLWithPath: owner.from)] = URL(fileURLWithPath: owner.to)

                for step in steps.dropFirst() {
                    result.companions[URL(fileURLWithPath: step.from)] = URL(fileURLWithPath: step.to)
                }
            }

            return result
        }

        // MARK: - Disk

        /// Settles one unfinished group on disk. Returns whether its owner ended at its destination.
        private static func settle(_ steps: [Record.Step], finalPhaseBegan: Bool) -> Bool {
            guard let owner = steps.first else { return false }

            // Where the owner's parked file went, when it was parked.
            var parkedOwnerMoved: Bool?

            for (number, step) in steps.enumerated() {
                guard let staging = step.staging, FileManager.default.fileExists(atPath: staging) else { continue }

                let wentForward: Bool

                if !exists(step.to) {
                    wentForward = move(staging, to: step.to)
                } else if !exists(step.from) {
                    _ = move(staging, to: step.from)
                    wentForward = false
                } else {
                    Log.error("Couldn't return \(staging) to either \(step.to) or \(step.from)")
                    wentForward = false
                }

                if number == 0 { parkedOwnerMoved = wentForward }
            }

            let ownerMoved: Bool = if let parkedOwnerMoved {
                parkedOwnerMoved
            } else if owner.staging != nil {
                // Every staged group parks before any finishes, so one not parked has finished
                // only if the final phase began.
                finalPhaseBegan && exists(owner.to)
            } else {
                isAt(owner.to, insteadOf: owner.from)
            }

            for companion in steps.dropFirst() {
                let (here, there) = ownerMoved ? (companion.from, companion.to) : (companion.to, companion.from)

                guard isAt(here, insteadOf: there) else { continue }

                if exists(there) {
                    Log.error("Couldn't move the companion \(here) to \(there): the name is taken")
                } else {
                    _ = move(here, to: there)
                }
            }

            return ownerMoved
        }

        /// A file is at `path` and not at `other`. On a case-insensitive volume a case-only rename
        /// leaves both paths resolving, so the folder listing decides.
        private static func isAt(_ path: String, insteadOf other: String) -> Bool {
            guard path.lowercased() == other.lowercased() else {
                return exists(path) && !exists(other)
            }

            let url = URL(fileURLWithPath: path)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)) ?? []

            return names.contains(url.lastPathComponent)
        }

        private static func exists(_ path: String) -> Bool {
            FileManager.default.fileExists(atPath: path)
        }

        private static func move(_ from: String, to: String) -> Bool {
            do {
                try FileManager.default.moveItem(atPath: from, toPath: to)
                return true
            } catch {
                Log.error("Couldn't move \(from) to \(to) while recovering an interrupted move", error)
                return false
            }
        }

        // MARK: - Reading

        struct Contents {
            var context = Data()
            var units: [Int: [Record.Step]] = [:]
            var done: Set<Int> = []
            var finalPhaseBegan = false
            var rolledBack: Set<Int>?

            /// The bytes up to and including the last newline.
            var wholeLinesLength = 0

            /// A last line cut short by a crash is ignored; any other unreadable line throws.
            init(reading url: URL) throws {
                let data = try Data(contentsOf: url)
                let lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601

                let endsWithNewline = data.last == 0x0A
                wholeLinesLength = (data.lastIndex(of: 0x0A).map { $0 - data.startIndex + 1 }) ?? 0
                var sawHeader = false

                for (number, line) in lines.enumerated() {
                    let record: Record

                    do {
                        record = try decoder.decode(Record.self, from: Data(line))
                    } catch {
                        if number == lines.count - 1, !endsWithNewline { break }
                        throw error
                    }

                    switch record.kind {
                    case .header:
                        sawHeader = true
                        context = record.context ?? Data()
                    case .unit:
                        if let index = record.index { units[index] = record.moves ?? [] }
                    case .done:
                        done.formUnion(record.units ?? [])
                    case .final:
                        finalPhaseBegan = true
                    case .end:
                        rolledBack = Set(record.rolledBack ?? [])
                    }
                }

                guard sawHeader else {
                    throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: url.path])
                }
            }
        }
    }

#endif
