// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

#if os(macOS)

    import Foundation
    import SPFKBase

    /// What ``FileCommands/duplicate(urls:)`` made.
    public struct FileDuplicates: Sendable, Equatable {
        /// Original → its copy.
        public var copies: [URL: URL] = [:]

        /// An original's companion → the companion copy made for its copy. These are the companion
        /// files the call created, and the only ones an undo may delete.
        public var companions: [URL: URL] = [:]

        /// Companions not copied, because the copy's name for them was taken or the copy failed.
        public var skippedCompanions: [URL] = []

        public init(copies: [URL: URL] = [:], companions: [URL: URL] = [:], skippedCompanions: [URL] = []) {
            self.copies = copies
            self.companions = companions
            self.skippedCompanions = skippedCompanions
        }
    }

    extension FileCommands {
        /// Copies `source`'s companions beside `copy`, named after it. Never overwrites.
        ///
        /// For a caller recreating a copy itself, such as a Duplicate's redo.
        public static func copyCompanions(from source: URL, toCopy copy: URL) -> FileDuplicates {
            duplicatingCompanions(of: [source: copy])
        }

        static func duplicatingCompanions(of copies: [URL: URL]) -> FileDuplicates {
            var result = FileDuplicates(copies: copies)

            for (original, copy) in copies {
                for companion in original.existingCompanionURLs {
                    let destination = companion.companionDestination(forOwner: copy)

                    guard !FileManager.default.fileExists(atPath: destination.path) else {
                        Log.error("Skipped copying \(companion.lastPathComponent): \(destination.lastPathComponent) already exists")
                        result.skippedCompanions.append(companion)
                        continue
                    }

                    do {
                        try FileManager.default.copyItem(at: companion, to: destination)
                        result.companions[companion] = destination
                    } catch {
                        Log.error("Couldn't copy \(companion.lastPathComponent) to \(destination.lastPathComponent)", error)
                        result.skippedCompanions.append(companion)
                    }
                }
            }

            return result
        }

        /// `urls` followed by the companions of each one not locked, without repeats.
        static func withCompanions(_ urls: [URL]) -> [URL] {
            var seen = Set(urls)
            var all = urls

            for url in urls where !url.isLocked {
                for companion in url.existingCompanionURLs where seen.insert(companion).inserted {
                    all.append(companion)
                }
            }

            return all
        }
    }

#endif
