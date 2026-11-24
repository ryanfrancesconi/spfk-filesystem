// Copyright Ryan Francesconi. All Rights Reserved.

#if os(macOS)

    import Foundation
    import SPFKBase
    import SPFKTesting
    import Testing

    @testable import SPFKFileSystem

    /// The Live Photo rule, with identifiers from a table rather than the files.
    @Suite(.tags(.file, .renameOrganize))
    @MainActor
    struct FileCompanionsTests {
        typealias Sandbox = FileCommandsTests.Sandbox

        /// Identifiers by file name, counting each read.
        final class Identifiers: @unchecked Sendable {
            private let lock = NSLock()
            private let table: [String: String]
            private var _reads: [String] = []

            init(_ table: [String: String]) {
                self.table = table
            }

            var reads: [String] {
                lock.withLock { _reads }
            }

            var reading: LivePhotoIdentifierReading {
                LivePhotoIdentifierReading(still: { self.read($0) }, movie: { self.read($0) })
            }

            func record(_ url: URL) {
                lock.withLock { _reads.append(url.lastPathComponent) }
            }

            private func read(_ url: URL) -> String? {
                lock.withLock {
                    _reads.append(url.lastPathComponent)
                    return table[url.lastPathComponent]
                }
            }
        }

        @Test func equalIdentifiersPair() async throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let still = try dir.file(named: "IMG_1234.HEIC")
            let movie = try dir.file(named: "IMG_1234.MOV")
            let identifiers = Identifiers(["IMG_1234.HEIC": "A", "IMG_1234.MOV": "A"])

            let companions = await FileCompanions.resolve([still], identifiers: identifiers.reading)

            #expect(companions == [still: [movie]])
        }

        @Test func differentIdentifiersDoNotPair() async throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let still = try dir.file(named: "IMG_1234.HEIC")
            _ = try dir.file(named: "IMG_1234.MOV")
            let identifiers = Identifiers(["IMG_1234.HEIC": "A", "IMG_1234.MOV": "B"])

            #expect(await FileCompanions.resolve([still], identifiers: identifiers.reading) == [still: []])
        }

        /// A short video sharing a photo's name, with no identifier of its own.
        @Test func aMovieWithoutAnIdentifierDoesNotPair() async throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let still = try dir.file(named: "IMG_1234.HEIC")
            _ = try dir.file(named: "IMG_1234.MOV")
            let identifiers = Identifiers(["IMG_1234.HEIC": "A"])

            #expect(await FileCompanions.resolve([still], identifiers: identifiers.reading) == [still: []])
        }

        @Test func aStillWithoutAnIdentifierDoesNotPairOrReadTheMovie() async throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let still = try dir.file(named: "IMG_1234.HEIC")
            _ = try dir.file(named: "IMG_1234.MOV")
            let identifiers = Identifiers(["IMG_1234.MOV": "A"])

            #expect(await FileCompanions.resolve([still], identifiers: identifiers.reading) == [still: []])
            #expect(identifiers.reads == ["IMG_1234.HEIC"])
        }

        @Test func aPairedMovieThatIsAlsoARowIsOnlyACompanion() async throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let movie = try dir.file(named: "IMG_1234.MOV")
            let still = try dir.file(named: "IMG_1234.HEIC")
            let identifiers = Identifiers(["IMG_1234.HEIC": "A", "IMG_1234.MOV": "A"])

            let companions = await FileCompanions.resolve([movie, still], identifiers: identifiers.reading)

            #expect(companions == [still: [movie]])
        }

        @Test func aStillWithNoMovieBesideItReadsNoIdentifier() async throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let still = try dir.file(named: "IMG_1234.HEIC")
            let identifiers = Identifiers(["IMG_1234.HEIC": "A"])

            _ = await FileCompanions.resolve([still], identifiers: identifiers.reading)

            #expect(identifiers.reads.isEmpty)
        }

        @Test func aRAWIsNeverPaired() async throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let raw = try dir.file(named: "DSCF0001.RAF")
            _ = try dir.file(named: "DSCF0001.MOV")
            let identifiers = Identifiers(["DSCF0001.RAF": "A", "DSCF0001.MOV": "A"])

            #expect(await FileCompanions.resolve([raw], identifiers: identifiers.reading) == [raw: []])
            #expect(identifiers.reads.isEmpty)
        }

        @Test func eachFolderIsListedOnce() async throws {
            let folders = try (0 ..< 3).map { _ in try Sandbox() }
            defer { folders.forEach { $0.remove() } }

            var stills: [URL] = []

            for folder in folders {
                for number in 1 ... 4 {
                    stills.append(try folder.file(named: "IMG_000\(number).HEIC"))
                }
            }

            let listed = Identifiers([:])

            _ = await FileCompanions.resolve(stills, identifiers: Identifiers([:]).reading) { folder in
                listed.record(folder)
                return (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            }

            #expect(listed.reads.count == 3)
        }

        @Test func theEditRecordsComeBeforeTheMovie() async throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let still = try dir.file(named: "IMG_1234.HEIC")
            let movie = try dir.file(named: "IMG_1234.MOV")
            let record = try dir.file(named: "IMG_1234.aae")
            let identifiers = Identifiers(["IMG_1234.HEIC": "A", "IMG_1234.MOV": "A"])

            #expect(await FileCompanions.resolve([still], identifiers: identifiers.reading) == [still: [record, movie]])
        }

        /// A RAW and its JPEG share a base name, so both find the one edit record.
        @Test func aCompanionIsListedUnderTheFirstOwnerOnly() async throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let jpeg = try dir.file(named: "IMG_1234.JPG")
            let heic = try dir.file(named: "IMG_1234.HEIC")
            let record = try dir.file(named: "IMG_1234.aae")

            let companions = await FileCompanions.resolve([jpeg, heic], identifiers: Identifiers([:]).reading)

            #expect(companions == [jpeg: [record], heic: []])
        }

        /// The real reader, over a still and a movie written with one identifier.
        @Test func theSystemReaderPairsWrittenFixtures() async throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let identifier = UUID().uuidString
            let still = try LivePhotoFixtures.still(.heic, identifier: identifier, in: dir.url)
            let movie = try await LivePhotoFixtures.movie(identifier: identifier, in: dir.url)

            let companions = await FileCompanions.resolve([still])

            #expect(companions[still]?.map(\.lastPathComponent) == [movie.lastPathComponent])
        }

        // MARK: - Trash

        @Test func trashingAPairedStillTrashesItsMovieAndRestoreBringsBothBack() async throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let identifier = UUID().uuidString
            let name = "IMG_\(Int.random(in: 1000 ... 9999))"
            let still = try LivePhotoFixtures.still(.heic, identifier: identifier, named: name, in: dir.url)
            let movie = try await LivePhotoFixtures.movie(identifier: identifier, named: name, in: dir.url)

            #expect(await FileCommands.trashSet(for: [still]) == [still, movie])

            let trashed = try await FileCommands.moveToTrash(urls: [still])

            #expect(Set(trashed.keys) == [still, movie])
            #expect(try dir.names().isEmpty)

            #expect(FileCommands.restoreFromTrash(trashed).isEmpty)
            #expect(still.exists && movie.exists)
        }

        // MARK: - Duplicate

        @Test func duplicatingAPairedStillCopiesItsMovie() async throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let identifier = UUID().uuidString
            let still = try LivePhotoFixtures.still(.heic, identifier: identifier, in: dir.url)
            let movie = try await LivePhotoFixtures.movie(identifier: identifier, in: dir.url)

            let result = try await FileCommands.duplicate(urls: [still])
            let copy = try #require(result.copies[still])
            let copiedMovie = try #require(result.companions[movie])

            #expect(copiedMovie.deletingPathExtension().lastPathComponent == copy.deletingPathExtension().lastPathComponent)
            #expect(await LivePhotoIdentifier.movie(at: copiedMovie) == identifier)
        }

        /// A movie selected with its still is copied once, as a row of its own.
        @Test func duplicatingAStillAndItsMovieCopiesTheMovieOnce() async throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let identifier = UUID().uuidString
            let still = try LivePhotoFixtures.still(.heic, identifier: identifier, in: dir.url)
            let movie = try await LivePhotoFixtures.movie(identifier: identifier, in: dir.url)

            let result = try await FileCommands.duplicate(urls: [still, movie])

            #expect(Set(result.copies.keys) == [still, movie])
            #expect(result.companions.isEmpty)
            #expect(result.skippedCompanions.isEmpty)
            #expect(try dir.names().count == 4)
        }
    }

#endif
