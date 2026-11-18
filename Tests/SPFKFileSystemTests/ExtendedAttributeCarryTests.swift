// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation
import SPFKBase
import SPFKTesting
import Testing

/// What `OriginalsStore` relies on: a custom attribute survives the swap a rendered save makes, and a copy.
@Suite(.tags(.file))
final class ExtendedAttributeCarryTests: BinTestCase {
    private let name = "com.spongefork.test.carry"
    private let value = Data("kept".utf8)

    private func file(_ filename: String, contents: String) throws -> URL {
        let url = bin.appendingPathComponent(filename)
        try Data(contents.utf8).write(to: url)
        return url
    }

    @Test func aReplaceWithDefaultOptionsCarriesTheReplacedFilesAttribute() throws {
        let original = try file("original.wav", contents: "original")
        let render = try file(".render.wav", contents: "render")
        try FileXattrs.set(name, value: value, on: original)

        _ = try FileManager.default.replaceItemAt(original, withItemAt: render)

        #expect(try String(contentsOf: original, encoding: .utf8) == "render")
        #expect(try FileXattrs.value(name, of: original) == value)
    }

    /// So a kept original must never carry the attribute: swapped back in, its value would win.
    @Test func aReplacementsOwnAttributeWinsOverTheReplacedFiles() throws {
        let original = try file("original.wav", contents: "original")
        let render = try file(".render.wav", contents: "render")
        let renderValue = Data("render".utf8)
        try FileXattrs.set(name, value: value, on: original)
        try FileXattrs.set(name, value: renderValue, on: render)

        _ = try FileManager.default.replaceItemAt(original, withItemAt: render)

        #expect(try FileXattrs.value(name, of: original) == renderValue)
    }

    @Test func aCopyCarriesTheAttribute() throws {
        let original = try file("original.wav", contents: "original")
        try FileXattrs.set(name, value: value, on: original)
        let copy = bin.appendingPathComponent("copy.wav")

        try FileManager.default.copyItem(at: original, to: copy)

        #expect(try FileXattrs.value(name, of: copy) == value)
    }

    @Test func aBackupKeptByAReplaceKeepsItsAttributeAndFileID() throws {
        let original = try file("original.wav", contents: "original")
        let replacement = try file(".replacement.wav", contents: "replacement")
        try FileXattrs.set(name, value: value, on: original)
        let originalID = try original.resourceValues(forKeys: [.fileIdentifierKey]).fileIdentifier

        _ = try FileManager.default.replaceItemAt(
            original,
            withItemAt: replacement,
            backupItemName: ".backup.wav",
            options: .withoutDeletingBackupItem
        )

        let backup = bin.appendingPathComponent(".backup.wav")
        #expect(try String(contentsOf: backup, encoding: .utf8) == "original")
        #expect(try FileXattrs.value(name, of: backup) == value)
        #expect(try backup.resourceValues(forKeys: [.fileIdentifierKey]).fileIdentifier == originalID)
    }
}
