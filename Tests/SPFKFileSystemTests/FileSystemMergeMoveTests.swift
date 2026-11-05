// Copyright Ryan Francesconi. All Rights Reserved.

import Darwin
import Foundation
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKFileSystem

@Suite(.tags(.file, .cacheLocation))
final class FileSystemMergeMoveTests: BinTestCase {
    private let fm = FileManager.default

    private func write(_ string: String, to url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(string.utf8).write(to: url)
    }

    private func inode(of url: URL) throws -> ino_t {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { throw POSIXError(.ENOENT) }
        return info.st_ino
    }

    private func regularFiles(under directory: URL) -> [URL] {
        let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
        return (enumerator?.allObjects as? [URL] ?? []).filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }

    private func inodeCount(under directory: URL) throws -> Int {
        try Set(regularFiles(under: directory).map(inode(of:))).count
    }

    /// Four paths over two inodes, in two subfolders, the shape `ImageDataStore` leaves.
    private func makeLinkedTree(at source: URL) throws {
        let a = source.appendingPathComponent("Image/aa/one.png")
        let b = source.appendingPathComponent("Image/bb/other.png")
        try write("shared pixels", to: a)
        try write("unique pixels", to: b)
        try fm.createDirectory(at: source.appendingPathComponent("Image/cc"), withIntermediateDirectories: true)
        try fm.linkItem(at: a, to: source.appendingPathComponent("Image/cc/two.png"))
        try fm.linkItem(at: a, to: source.appendingPathComponent("Image/aa/three.png"))
        try write("waveform", to: source.appendingPathComponent("Waveform/0a/key.wfcache"))
    }

    private func assertMovedLinkedTree(from source: URL, to destination: URL) throws {
        #expect(regularFiles(under: destination).count == 5)
        #expect(try inodeCount(under: destination) == 3)
        #expect(try inode(of: destination.appendingPathComponent("Image/aa/one.png"))
            == inode(of: destination.appendingPathComponent("Image/cc/two.png")))
        #expect(try String(contentsOf: destination.appendingPathComponent("Image/aa/three.png"), encoding: .utf8) == "shared pixels")
        #expect(source.isDirectory)
        #expect(try fm.contentsOfDirectory(atPath: source.path).isEmpty)
    }

    @Test func diskUsageCountsEachInodeOnce() throws {
        let source = bin.appendingPathComponent("Source")
        try makeLinkedTree(at: source)

        let usage = FileSystem.diskUsage(of: source)

        #expect(usage.fileCount == 5)
        #expect(usage.logicalBytes == Int64("shared pixels".utf8.count + "unique pixels".utf8.count + "waveform".utf8.count))
    }

    @Test func aMoveOnOneVolumeRenames() throws {
        let source = bin.appendingPathComponent("Source")
        let destination = bin.appendingPathComponent("Destination")
        try makeLinkedTree(at: source)
        let before = try inode(of: source.appendingPathComponent("Image/bb/other.png"))

        try FileSystem.mergeMove(contentsOf: source, into: destination)

        try assertMovedLinkedTree(from: source, to: destination)
        #expect(try inode(of: destination.appendingPathComponent("Image/bb/other.png")) == before)
    }

    @Test func aCopyKeepsHardlinksLinked() throws {
        let source = bin.appendingPathComponent("Source")
        let destination = bin.appendingPathComponent("Destination")
        try makeLinkedTree(at: source)
        var reported = [Double]()

        try FileSystem.mergeMove(contentsOf: source, into: destination, forceCopy: true) { reported.append($0) }

        try assertMovedLinkedTree(from: source, to: destination)
        #expect(reported.last == 1)
    }

    @Test(arguments: [false, true])
    func aMergeKeepsTheDestinationsEntry(forceCopy: Bool) throws {
        let source = bin.appendingPathComponent("Source")
        let destination = bin.appendingPathComponent("Destination")
        try write("old", to: source.appendingPathComponent("Image/aa/key.png"))
        try write("only in source", to: source.appendingPathComponent("Image/aa/new.png"))
        try write("kept", to: destination.appendingPathComponent("Image/aa/key.png"))

        try FileSystem.mergeMove(contentsOf: source, into: destination, forceCopy: forceCopy, progress: nil)

        #expect(try String(contentsOf: destination.appendingPathComponent("Image/aa/key.png"), encoding: .utf8) == "kept")
        #expect(try String(contentsOf: destination.appendingPathComponent("Image/aa/new.png"), encoding: .utf8) == "only in source")
        #expect(try fm.contentsOfDirectory(atPath: source.path).isEmpty)
    }

    @Test func aCancelledCopyLeavesTheSourceAndNoDestination() async throws {
        let source = bin.appendingPathComponent("Source")
        let destination = bin.appendingPathComponent("Destination")
        try makeLinkedTree(at: source)

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try FileSystem.mergeMove(contentsOf: source, into: destination, forceCopy: true, progress: nil)
        }

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(regularFiles(under: source).count == 5)
        #expect(!fm.fileExists(atPath: destination.path))
    }

    @Test func aCancelledMergeRemovesOnlyWhatItWrote() async throws {
        let source = bin.appendingPathComponent("Source")
        let destination = bin.appendingPathComponent("Destination")
        try makeLinkedTree(at: source)
        try write("kept", to: destination.appendingPathComponent("Image/aa/existing.png"))

        let task = Task {
            var calls = 0
            try FileSystem.mergeMove(contentsOf: source, into: destination, forceCopy: true) { _ in
                calls += 1
                if calls == 1 { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(regularFiles(under: source).count == 5)
        #expect(regularFiles(under: destination).map(\.lastPathComponent) == ["existing.png"])
    }

    #if os(macOS)
    // MARK: - Across volumes

    private func run(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw POSIXError(.EIO) }
    }

    @Test func aMoveAcrossVolumesKeepsHardlinksLinked() throws {
        let image = bin.appendingPathComponent("volume.dmg")
        let mountPoint = bin.appendingPathComponent("Mount")
        try run(["create", "-size", "20m", "-fs", "APFS", "-volname", "MergeMoveTest", "-o", image.path, "-quiet"])
        try run(["attach", image.path, "-nobrowse", "-mountpoint", mountPoint.path, "-quiet"])
        defer { try? run(["detach", mountPoint.path, "-force", "-quiet"]) }

        let source = bin.appendingPathComponent("Source")
        let destination = mountPoint.appendingPathComponent("Destination")
        try makeLinkedTree(at: source)

        var info = stat()
        lstat(bin.path, &info)
        let binDevice = info.st_dev
        lstat(mountPoint.path, &info)
        #expect(info.st_dev != binDevice)

        try FileSystem.mergeMove(contentsOf: source, into: destination)

        try assertMovedLinkedTree(from: source, to: destination)
    }
    #endif
}
