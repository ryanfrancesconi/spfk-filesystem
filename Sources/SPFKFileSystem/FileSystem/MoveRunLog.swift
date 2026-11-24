// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

#if os(macOS)

    import Foundation
    import SPFKBase

    /// An on-disk record of one ``FileCommands/move(_:rollingBackOnFailure:log:progress:)`` run, so a
    /// run the app never finished following can be finished at the next launch.
    ///
    /// One JSON-lines file per run: a header, every group's moves before the first one is made,
    /// the groups finished in batches, a marker when parked groups start finishing, and an end
    /// line once the run returns. Lines are not synced
    /// to disk, so the record survives the app quitting or crashing, not a power loss.
    public final class MoveRunLog: Sendable {
        public let url: URL
        private let handle: FileHandle

        private init(url: URL, handle: FileHandle) {
            self.url = url
            self.handle = handle
        }

        deinit {
            try? handle.close()
        }

        /// Starts a journal in `directory`, creating the folder if needed.
        ///
        /// - Parameter context: what the caller needs to follow the run later; opaque here.
        public static func create(in directory: URL, context: Data) throws -> MoveRunLog {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let run = UUID()
            let url = directory.appendingPathComponent("\(run.uuidString).\(fileExtension)")

            guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
            }

            let log = try MoveRunLog(url: url, handle: FileHandle(forWritingTo: url))
            try log.write(Record(kind: .header, version: 1, run: run, created: Date(), context: context))

            return log
        }

        /// The journals left in `directory`, oldest first.
        public static func pending(in directory: URL) -> [URL] {
            let keys: [URLResourceKey] = [.creationDateKey]
            let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []

            func created(_ url: URL) -> Date {
                (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            }

            return urls
                .filter { $0.pathExtension == fileExtension }
                .map { (url: $0, created: created($0)) }
                .sorted { ($0.created, $0.url.lastPathComponent) < ($1.created, $1.url.lastPathComponent) }
                .map(\.url)
        }

        /// Deletes the journal. A failure is logged: a journal left behind is offered again at the
        /// next launch, which is the safe side.
        public func remove() {
            try? handle.close()

            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                Log.error("Couldn't remove the move journal \(url.lastPathComponent)", error)
            }
        }

        static let fileExtension = "jsonl"

        // MARK: - Writing

        /// Every unit's moves, before the first is made.
        func record(_ units: [MoveUnit]) throws {
            var lines = Data()

            for (index, unit) in units.enumerated() {
                let moves = unit.moves.map {
                    Record.Step(from: $0.from.path, to: $0.to.path, staging: $0.stagingURL?.path, companion: $0.isCompanion)
                }
                lines.append(try Self.line(Record(kind: .unit, index: index, moves: moves)))
            }

            try handle.write(contentsOf: lines)
        }

        func recordDone(_ units: [Int]) {
            guard units.isNotEmpty else { return }
            writeLogging(Record(kind: .done, units: units))
        }

        func recordFinalPhase() {
            writeLogging(Record(kind: .final))
        }

        func recordEnd(rolledBack: [Int]) {
            writeLogging(Record(kind: .end, rolledBack: rolledBack))
        }

        /// A line lost after the moves began costs only a re-read of the disk at recovery, so it
        /// does not stop the run.
        private func writeLogging(_ record: Record) {
            do {
                try write(record)
            } catch {
                Log.error("Couldn't write to the move journal \(url.lastPathComponent)", error)
            }
        }

        private func write(_ record: Record) throws {
            try handle.write(contentsOf: Self.line(record))
        }

        static func line(_ record: Record) throws -> Data {
            var data = try encoder.encode(record)
            data.append(0x0A)
            return data
        }

        private static var encoder: JSONEncoder {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            return encoder
        }
    }

    extension MoveRunLog {
        /// One line of the journal. Paths are stored as path strings.
        struct Record: Codable {
            enum Kind: String, Codable {
                case header, unit, done, end

                /// Every staged group has been parked and the first is about to finish.
                case final
            }

            struct Step: Codable {
                let from: String
                let to: String
                let staging: String?
                let companion: Bool
            }

            var kind: Kind
            var version: Int?
            var run: UUID?
            var created: Date?
            var context: Data?
            var index: Int?
            var moves: [Step]?
            var units: [Int]?
            var rolledBack: [Int]?
        }
    }

#endif
