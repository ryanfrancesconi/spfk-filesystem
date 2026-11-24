// Copyright Ryan Francesconi. All Rights Reserved.

#if os(macOS)

    import Foundation
    import SPFKBase
    import SPFKTesting
    import Testing

    @testable import SPFKFileSystem

    /// A photo's `.aae` edit record travelling with it: by base name, and by the `IMG_O` rule.
    extension FileCommandsCompanionTests {
        // MARK: - Which files are companions

        @Test func aPhotoHasItsSameNamedEditRecordInEitherCase() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let upper = try dir.file(named: "IMG_1234.HEIC")
            let upperEdit = try dir.file(named: "IMG_1234.AAE")
            let lower = try dir.file(named: "IMG_2000.HEIC")
            let lowerEdit = try dir.file(named: "IMG_2000.aae")

            #expect(upper.existingCompanionURLs == [upperEdit])
            #expect(lower.existingCompanionURLs == [lowerEdit])
        }

        @Test func anOriginalEditRecordBelongsToThePhotoOfItsNumber() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let heic = try dir.file(named: "IMG_1234.HEIC")
            let jpeg = try dir.file(named: "IMG_1234.JPG")
            let edited = try dir.file(named: "IMG_E1234.HEIC")
            let record = try dir.file(named: "IMG_O1234.aae")

            #expect(heic.existingCompanionURLs == [record])
            #expect(jpeg.existingCompanionURLs == [record])
            #expect(edited.existingCompanionURLs.isEmpty)
        }

        @Test func anEditedPhotoHasNoneOfItsOriginalsCompanions() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let original = try dir.file(named: "IMG_1234.HEIC")
            let edited = try dir.file(named: "IMG_E1234.HEIC")
            _ = try dir.file(named: "IMG_1234.aae")
            _ = try dir.file(named: "IMG_O1234.aae")

            #expect(original.existingCompanionURLs.count == 2)
            #expect(edited.existingCompanionURLs.isEmpty)
        }

        @Test func aSoundBesideASameNamedEditRecordHasNone() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let sound = try dir.file(named: "IMG_1234.wav")
            _ = try dir.file(named: "IMG_1234.aae")

            #expect(sound.existingCompanionURLs.isEmpty)
        }

        @Test func aRAWKeepsItsSidecarAndGainsItsEditRecord() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let raw = try dir.file(named: "DSCF3303.RAF")
            let sidecar = try dir.file(named: "DSCF3303.xmp")
            let record = try dir.file(named: "DSCF3303.aae")

            #expect(raw.existingCompanionURLs == [sidecar, record])
        }

        // MARK: - Rename

        @Test func renameGivesAnOriginalEditRecordTheNewName() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let photo = try dir.file(named: "IMG_1234.HEIC")
            _ = try dir.file(named: "IMG_O1234.aae", contents: "edits")

            try FileCommands.rename(photo, to: "Trip")

            #expect(try Set(dir.names()) == ["Trip.HEIC", "Trip.aae"])
            #expect(try String(contentsOf: dir.url.appendingPathComponent("Trip.aae"), encoding: .utf8) == "edits")
        }

        /// An edited Photos export holds both records; the original's takes `_O` so neither is lost.
        @Test func renameGivesBothEditRecordsTheirOwnNames() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let movie = try dir.file(named: "IMG_7172.MOV")
            _ = try dir.file(named: "IMG_7172.AAE", contents: "edit")
            _ = try dir.file(named: "IMG_O7172.AAE", contents: "original")

            try FileCommands.rename(movie, to: "flash-hand")

            #expect(try Set(dir.names()) == ["flash-hand.MOV", "flash-hand.AAE", "flash-hand_O.AAE"])
            #expect(try String(contentsOf: dir.url.appendingPathComponent("flash-hand_O.AAE"), encoding: .utf8) == "original")
        }

        @Test func duplicateGivesBothEditRecordsTheirOwnNames() async throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let photo = try dir.file(named: "IMG_1234.HEIC")
            _ = try dir.file(named: "IMG_1234.aae")
            _ = try dir.file(named: "IMG_O1234.aae")

            let result = try await FileCommands.duplicate(urls: [photo])

            #expect(result.skippedCompanions.isEmpty)
            #expect(Set(result.companions.values.map(\.lastPathComponent)) == ["IMG_1234 copy.aae", "IMG_1234 copy_O.aae"])
        }

        // MARK: - Duplicate and Trash

        @Test func duplicateCopiesTheEditRecordAndItsUndoRemovesIt() async throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let photo = try dir.file(named: "IMG_1234.HEIC")
            let record = try dir.file(named: "IMG_1234.aae", contents: "edits")

            let result = try await FileCommands.duplicate(urls: [photo])
            let copy = try #require(result.copies[photo])
            let copiedRecord = copy.deletingPathExtension().appendingPathExtension("aae")

            #expect(result.companions == [record: copiedRecord])
            #expect(try String(contentsOf: copiedRecord, encoding: .utf8) == "edits")

            let created = Array(result.copies.values) + Array(result.companions.values)
            #expect(FileCommands.delete(urls: created).isEmpty)
            #expect(try Set(dir.names()) == ["IMG_1234.HEIC", "IMG_1234.aae"])
        }

        @Test func trashMovesTheEditRecordsAndRestoreBringsThemBack() async throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let number = Int.random(in: 1000 ... 9999)
            let photo = try dir.file(named: "IMG_\(number).HEIC", contents: "photo")
            let record = try dir.file(named: "IMG_\(number).aae", contents: "edits")
            let original = try dir.file(named: "IMG_O\(number).aae", contents: "original edits")

            let trashed = try await FileCommands.moveToTrash(urls: [photo])

            #expect(Set(trashed.keys) == [photo, record, original])
            #expect(try dir.names().isEmpty)

            #expect(FileCommands.restoreFromTrash(trashed).isEmpty)
            #expect(try String(contentsOf: record, encoding: .utf8) == "edits")
            #expect(try String(contentsOf: original, encoding: .utf8) == "original edits")
        }
    }

#endif
