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
            let moves = try execute(renamePlan(mapping), rollingBackOnFailure: rollingBackOnFailure)

            return FileRenames(renamed: moves.moved, failure: moves.failure)
        }

        /// Why each entry of `mapping` cannot be renamed as part of the set, keyed by source. Empty
        /// when ``renameAll(_:rollingBackOnFailure:)`` would start moving files.
        ///
        /// A conflict depends on the rest of the set, so dropping an entry can expose another.
        public static func renameConflicts(in mapping: [URL: URL]) -> [URL: FileCommandError] {
            renamePlan(mapping).conflicts
        }

        // MARK: - Plan

        /// The same-folder case of ``move(_:rollingBackOnFailure:)``, with each file's companions
        /// found on disk.
        private static func renamePlan(_ mapping: [URL: URL]) -> MoveExecutionPlan {
            var groups: [MovePlan.Group] = []
            var conflicts: [URL: FileCommandError] = [:]

            for (source, destination) in mapping where source != destination {
                guard destination.deletingLastPathComponent().standardizedFileURL.path
                    == source.deletingLastPathComponent().standardizedFileURL.path
                else {
                    conflicts[source] = .invalidName(destination.lastPathComponent)
                    continue
                }

                let companions = source.existingCompanionURLs.map {
                    MovePlan.CompanionMove(from: $0, to: $0.companionDestination(forOwner: destination))
                }

                groups.append(MovePlan.Group(source: source, destination: destination, companions: companions))
            }

            return executionPlan(groups, conflicts: conflicts)
        }

        /// A hidden name beside `url` to park it under while the set reuses its name. Never the
        /// render-sibling shape, which a sweep deletes.
        nonisolated static func renameStagingURL(for url: URL) -> URL {
            url.deletingLastPathComponent().appendingPathComponent(".spfk-rename-\(UUID().uuidString)-\(url.lastPathComponent)")
        }
    }

#endif
