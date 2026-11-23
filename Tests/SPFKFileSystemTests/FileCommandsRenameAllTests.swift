// Copyright Ryan Francesconi. All Rights Reserved.

#if os(macOS)

    import Foundation
    import SPFKBase
    import SPFKTesting
    import Testing

    @testable import SPFKFileSystem

    /// A rename set that reuses its own names, with a RAW's sidecar travelling beside each file.
    @Suite(.tags(.file, .xmpSidecar, .renameOrganize))
    @MainActor
    struct FileCommandsRenameAllTests {
        typealias Sandbox = FileCommandsTests.Sandbox

        /// A RAW named `base` whose content and sidecar's content are both `base`.
        private func photo(_ base: String, in dir: Sandbox) throws -> URL {
            _ = try dir.file(named: "\(base).xmp", contents: "\(base) sidecar")
            return try dir.file(named: "\(base).RAF", contents: base)
        }

        private func contents(_ name: String, in dir: Sandbox) throws -> String {
            try String(contentsOf: dir.url.appendingPathComponent(name), encoding: .utf8)
        }

        private func url(_ name: String, in dir: Sandbox) -> URL {
            dir.url.appendingPathComponent(name)
        }

        // MARK: - Reusing names

        @Test func aSwapExchangesBothFilesAndTheirSidecars() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let a = try photo("A", in: dir)
            let b = try photo("B", in: dir)

            let result = try FileCommands.renameAll([a: b, b: a], rollingBackOnFailure: true)

            #expect(result.renamed == [a: b, b: a])
            #expect(try contents("A.RAF", in: dir) == "B")
            #expect(try contents("A.xmp", in: dir) == "B sidecar")
            #expect(try contents("B.RAF", in: dir) == "A")
            #expect(try contents("B.xmp", in: dir) == "A sidecar")
            #expect(try dir.names().count == 4)
        }

        @Test func aChainMovesEachFileOntoTheNameTheNextVacates() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let b = try photo("B", in: dir)
            let c = try photo("C", in: dir)
            let a = url("A.RAF", in: dir)

            try FileCommands.renameAll([b: a, c: b], rollingBackOnFailure: true)

            #expect(try Set(dir.names()) == ["A.RAF", "A.xmp", "B.RAF", "B.xmp"])
            #expect(try contents("A.RAF", in: dir) == "B")
            #expect(try contents("A.xmp", in: dir) == "B sidecar")
            #expect(try contents("B.RAF", in: dir) == "C")
            #expect(try contents("B.xmp", in: dir) == "C sidecar")
        }

        @Test func aShiftByOneRenumbersEveryFile() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            var mapping: [URL: URL] = [:]
            for number in 1 ... 5 {
                mapping[try photo("IMG_\(number)", in: dir)] = url("IMG_\(number + 1).RAF", in: dir)
            }

            let result = try FileCommands.renameAll(mapping, rollingBackOnFailure: true)

            #expect(result.renamed == mapping)
            #expect(try dir.names().count == 10)
            for number in 2 ... 6 {
                #expect(try contents("IMG_\(number).RAF", in: dir) == "IMG_\(number - 1)")
                #expect(try contents("IMG_\(number).xmp", in: dir) == "IMG_\(number - 1) sidecar")
            }
        }

        // MARK: - Refusals

        @Test func aNameHeldOutsideTheSetThrowsBeforeAnythingMoves() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let a = try photo("A", in: dir)
            let b = try photo("B", in: dir)
            let held = try dir.file(named: "Z.RAF", contents: "held")

            #expect(throws: FileCommandError.nameInUse(held)) {
                try FileCommands.renameAll([a: b, b: held], rollingBackOnFailure: false)
            }

            #expect(try Set(dir.names()) == ["A.RAF", "A.xmp", "B.RAF", "B.xmp", "Z.RAF"])
            #expect(try contents("A.RAF", in: dir) == "A")
            #expect(try contents("Z.RAF", in: dir) == "held")
        }

        @Test func aDestinationInAnotherFolderIsRefused() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let a = try dir.file(named: "A.wav")
            let elsewhere = FileManager.default.temporaryDirectory.appendingPathComponent("A.wav")

            #expect(throws: FileCommandError.invalidName("A.wav")) {
                try FileCommands.renameAll([a: elsewhere], rollingBackOnFailure: true)
            }
            #expect(try dir.names() == ["A.wav"])
        }

        @Test func twoFilesOntoOneNameAreRefused() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let a = try dir.file(named: "A.wav")
            let b = try dir.file(named: "B.wav")
            let c = url("C.wav", in: dir)

            #expect(throws: FileCommandError.nameInUse(c)) {
                try FileCommands.renameAll([a: c, b: c], rollingBackOnFailure: true)
            }
            #expect(try Set(dir.names()) == ["A.wav", "B.wav"])
        }

        // MARK: - Failure partway

        /// A locked sidecar refuses its move once its owner and the files before it have moved.
        @Test(arguments: [true, false])
        func aFailurePartwayLeavesNoTemporaryNames(rollingBack: Bool) throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            var mapping: [URL: URL] = [:]
            for number in 1 ... 5 {
                mapping[try photo("IMG_\(number)", in: dir)] = url("IMG_\(number + 1).RAF", in: dir)
            }
            try url("IMG_3.xmp", in: dir).lock()

            var result: FileRenames?
            if rollingBack {
                #expect(throws: (any Error).self) {
                    try FileCommands.renameAll(mapping, rollingBackOnFailure: true)
                }
            } else {
                result = try FileCommands.renameAll(mapping, rollingBackOnFailure: false)
                #expect(result?.failure != nil)
            }

            let names = try dir.names()
            #expect(!names.contains { $0.hasPrefix(".") })
            #expect(names.count == 10)

            // Each RAW sits beside its own sidecar under the name it ended with.
            for name in names where name.hasSuffix(".RAF") {
                let base = (name as NSString).deletingPathExtension
                #expect(try contents("\(base).xmp", in: dir) == "\(try contents(name, in: dir)) sidecar")
            }

            let renamed = result?.renamed ?? [:]
            for (source, destination) in mapping {
                let expected = renamed[source] ?? source
                #expect(try String(contentsOf: expected, encoding: .utf8) == source.deletingPathExtension().lastPathComponent)
                #expect(renamed[source] == nil || renamed[source] == destination)
            }

            if rollingBack {
                #expect(try contents("IMG_1.RAF", in: dir) == "IMG_1")
                #expect(!names.contains("IMG_6.RAF"))
            }
        }

        // MARK: - Temporary names

        @Test func aStagingNameSurvivesTheRenderSiblingSweep() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let staged = FileCommands.renameStagingURL(for: url("IMG_1.RAF", in: dir))
            try Data("parked".utf8).write(to: staged)
            try FileManager.default.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: staged.path)

            URL.removeStaleRenderSiblings(in: dir.url, olderThan: .distantFuture)

            #expect(FileManager.default.fileExists(atPath: staged.path))
        }
    }

#endif
