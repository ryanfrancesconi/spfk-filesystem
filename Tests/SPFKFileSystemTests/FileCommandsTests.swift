// Copyright Ryan Francesconi. All Rights Reserved.

#if os(macOS)

    import Foundation
    import SPFKBase
    import SPFKTesting
    import Testing

    @testable import SPFKFileSystem

    /// The Finder file gestures behind Rename, Duplicate and Move to Trash.
    ///
    /// The trash cases reach the real `~/.Trash` — `NSWorkspace.recycle` has no sandbox to point
    /// elsewhere — so every one of them puts the file back or deletes it before returning.
    @Suite(.tags(.file))
    @MainActor
    struct FileCommandsTests {
        // MARK: - Rename validation

        @Test(arguments: ["", "   ", "\n", "a/b", "/", ".", ".."])
        func renameRefusesAnUnusableName(_ name: String) throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let file = try dir.file(named: "Source.wav")

            #expect(throws: FileCommandError.self) {
                try FileCommands.rename(file, to: name)
            }

            // Refused before touching disk.
            #expect(FileManager.default.fileExists(atPath: file.path))
        }

        @Test func renameKeepsTheExtensionWhenTheNewNameHasNone() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let file = try dir.file(named: "Source.wav")
            let renamed = try FileCommands.rename(file, to: "Renamed")

            #expect(renamed.lastPathComponent == "Renamed.wav")
            #expect(FileManager.default.fileExists(atPath: renamed.path))
            #expect(!FileManager.default.fileExists(atPath: file.path))
        }

        @Test func renameHonorsAnExtensionTheUserTyped() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let file = try dir.file(named: "Source.wav")
            let renamed = try FileCommands.rename(file, to: "Renamed.aiff")

            #expect(renamed.lastPathComponent == "Renamed.aiff")
        }

        @Test func renameOntoAnExistingNameReportsItAndLeavesBothFiles() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let source = try dir.file(named: "Source.wav", contents: "source")
            let occupied = try dir.file(named: "Taken.wav", contents: "taken")

            #expect(throws: FileCommandError.nameInUse(occupied)) {
                try FileCommands.rename(source, to: "Taken.wav")
            }

            #expect(try String(contentsOf: source, encoding: .utf8) == "source")
            #expect(try String(contentsOf: occupied, encoding: .utf8) == "taken")
        }

        /// Case-insensitive APFS moves a file onto its own differently-cased name, so nothing here
        /// may pre-check the destination for existence — that check would refuse a valid rename.
        @Test func aCaseOnlyRenameSucceeds() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let file = try dir.file(named: "Source.wav")
            let renamed = try FileCommands.rename(file, to: "source.wav")

            #expect(renamed.lastPathComponent == "source.wav")
            #expect(try dir.names().contains("source.wav"))
        }

        @Test func renamingToTheSameNameIsANoOp() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let file = try dir.file(named: "Source.wav")

            #expect(try FileCommands.rename(file, to: "Source.wav") == file)
            #expect(FileManager.default.fileExists(atPath: file.path))
        }

        // MARK: - Locked files

        @Test func renameRefusesALockedFileAndLeavesItInPlace() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let file = try dir.file(named: "Locked.wav")
            try file.lock()
            defer { try? file.unlock() }

            #expect(throws: FileCommandError.locked(file)) {
                try FileCommands.rename(file, to: "Renamed.wav")
            }

            #expect(FileManager.default.fileExists(atPath: file.path))
        }

        /// The batch convention: a file that cannot be trashed is absent from the map and costs the
        /// rest of the selection nothing.
        ///
        /// Also the guard on the completion-handler spelling — `NSWorkspace`'s `async` overload
        /// throws here and hands back no map at all, having trashed the other two.
        @Test func moveToTrashSkipsALockedFileAndTrashesTheOthers() async throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let locked = try dir.file(named: "BatchLocked-\(UUID().uuidString).wav")
            let first = try dir.file(named: "BatchOne-\(UUID().uuidString).wav")
            let second = try dir.file(named: "BatchTwo-\(UUID().uuidString).wav")

            try locked.lock()
            defer { try? locked.unlock() }

            let trashed = try await FileCommands.moveToTrash(urls: [locked, first, second])
            defer { _ = FileCommands.restoreFromTrash(trashed) }

            #expect(trashed[locked] == nil)
            #expect(trashed[first] != nil)
            #expect(trashed[second] != nil)
            #expect(FileManager.default.fileExists(atPath: locked.path))
        }

        /// The one place a lock is cleared rather than refused. Without it, undoing a Duplicate of a
        /// locked file fails — the copy inherits `uchg`, and `removeItem` refuses it.
        @Test func deleteClearsTheLockAndRemovesTheFile() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let file = try dir.file(named: "Locked.wav")
            try file.lock()

            let failures = FileCommands.delete(urls: [file])

            #expect(failures.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: file.path))
        }

        // MARK: - Trash round trip

        @Test func trashAndRestoreBringBackContentAndFinderTags() async throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let file = try dir.file(named: "Tagged-\(UUID().uuidString).wav", contents: "payload")
            try file.set(tagNames: ["Red"])

            let trashed = try await FileCommands.moveToTrash(urls: [file])

            let trashURL = try #require(trashed[file])
            #expect(trashURL.pathComponents.contains(".Trash"))
            #expect(!FileManager.default.fileExists(atPath: file.path))

            let failures = FileCommands.restoreFromTrash(trashed)

            #expect(failures.isEmpty)
            #expect(try String(contentsOf: file, encoding: .utf8) == "payload")
            #expect(file.tagNames.contains("Red"))
        }

        // MARK: - Duplicate

        @Test func duplicateNamesCopiesTheWayFinderDoes() async throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let file = try dir.file(named: "Song.txt", contents: "payload")

            let first = try await FileCommands.duplicate(urls: [file])
            #expect(first[file]?.lastPathComponent == "Song copy.txt")

            let second = try await FileCommands.duplicate(urls: [file])
            #expect(second[file]?.lastPathComponent == "Song copy 2.txt")

            let copy = try #require(first[file])
            #expect(try String(contentsOf: copy, encoding: .utf8) == "payload")
        }

        @Test func duplicateCarriesFinderTagsToTheCopy() async throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let file = try dir.file(named: "Tagged.wav")
            try file.set(tagNames: ["Blue"])

            let copies = try await FileCommands.duplicate(urls: [file])
            let copy = try #require(copies[file])

            #expect(copy.tagNames.contains("Blue"))
        }

        @Test func anEmptyBatchIsNotAnError() async throws {
            #expect(try await FileCommands.duplicate(urls: []).isEmpty)
            #expect(try await FileCommands.moveToTrash(urls: []).isEmpty)
            #expect(FileCommands.delete(urls: []).isEmpty)
            #expect(FileCommands.restoreFromTrash([:]).isEmpty)
        }

        // MARK: - Harness

        /// A throwaway directory. Removal unlocks anything still carrying `uchg`, which would
        /// otherwise make the directory itself undeletable.
        struct Sandbox {
            let url: URL

            init() throws {
                url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("file-commands-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            }

            func file(named name: String, contents: String = "spfk") throws -> URL {
                let fileURL = url.appendingPathComponent(name)
                try Data(contents.utf8).write(to: fileURL)
                return fileURL
            }

            func names() throws -> [String] {
                try FileManager.default.contentsOfDirectory(atPath: url.path)
            }

            func remove() {
                let contents = (try? FileManager.default.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: nil
                )) ?? []

                for item in contents where item.isLocked {
                    try? item.unlock()
                }

                try? FileManager.default.removeItem(at: url)
            }
        }
    }

#endif
