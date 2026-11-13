import Foundation
import SPFKBase
import SPFKFileSystem
import SPFKTesting
import Testing

@Suite(.tags(.file, .importScan))
final class FileScanTests: BinTestCase {
    private func scan(_ roots: [URL]) async -> Set<URL> {
        await FileSystem.scanFiles(in: roots).files
    }

    private func makeFile(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: url)
    }

    private func names(_ urls: Set<URL>) -> [String] {
        urls.map(\.lastPathComponent).sorted()
    }

    // MARK: - Characterization

    @Test func hiddenFilesAndFoldersAreSkipped() async throws {
        let root = bin.appendingPathComponent("root")
        try makeFile(root.appendingPathComponent("visible.txt"))
        try makeFile(root.appendingPathComponent(".hidden.txt"))
        try makeFile(root.appendingPathComponent(".hiddenDir/inside.txt"))

        #expect(await names(scan([root])) == ["visible.txt"])
    }

    @Test func packageContentsAndThePackageAreSkipped() async throws {
        let root = bin.appendingPathComponent("root")
        try makeFile(root.appendingPathComponent("visible.txt"))
        try makeFile(root.appendingPathComponent("Thing.app/Contents/inside.txt"))

        #expect(await names(scan([root])) == ["visible.txt"])
    }

    @Test func finderAliasToFolderIsFollowed() async throws {
        let root = bin.appendingPathComponent("root")
        let target = bin.appendingPathComponent("target")
        try makeFile(root.appendingPathComponent("visible.txt"))
        try makeFile(target.appendingPathComponent("aliased.txt"))

        let bookmark = try target.bookmarkData(options: .suitableForBookmarkFile)
        try URL.writeBookmarkData(bookmark, to: root.appendingPathComponent("alias"))

        #expect(await names(scan([root])) == ["aliased.txt", "visible.txt"])
    }

    @Test func symlinkToFolderIsFollowed() async throws {
        let root = bin.appendingPathComponent("root")
        let target = bin.appendingPathComponent("target")
        try makeFile(root.appendingPathComponent("visible.txt"))
        try makeFile(target.appendingPathComponent("linked.txt"))

        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: target)

        #expect(await names(scan([root])) == ["linked.txt", "visible.txt"])
    }

    @Test func namedFileIsReturnedWithFolderContents() async throws {
        let root = bin.appendingPathComponent("root")
        let loose = bin.appendingPathComponent("loose.txt")
        try makeFile(root.appendingPathComponent("nested/deep.txt"))
        try makeFile(loose)

        #expect(await names(scan([root, loose])) == ["deep.txt", "loose.txt"])
    }

    // MARK: - Stopping

    @Test func stopAlreadySetReturnsAtOnce() async throws {
        let root = bin.appendingPathComponent("root")
        try makeFile(root.appendingPathComponent("a.txt"))

        let result = await FileSystem.scanFiles(in: [root], shouldStop: { true })

        #expect(result.wasStopped)
        #expect(result.files.isEmpty)
    }

    @Test func stopFromTheFirstReportEndsTheWalk() async throws {
        let root = bin.appendingPathComponent("root")
        for folder in 0 ..< 10 {
            for file in 0 ..< 30 {
                try makeFile(root.appendingPathComponent("f\(folder)/n\(folder)/\(file).txt"))
            }
        }

        let signal = ParseStopSignal()
        let result = await FileSystem.scanFiles(
            in: [root],
            shouldStop: { signal.isStopped },
            onFound: { _ in signal.stop() }
        )

        #expect(result.wasStopped)
        #expect(result.files.count < 300)
        #expect(await !FileSystem.scanFiles(in: [root]).wasStopped)
    }

    // MARK: - Aliases and cycles

    @Test func symlinkToAncestorTerminates() async throws {
        let root = bin.appendingPathComponent("root")
        try makeFile(root.appendingPathComponent("one.txt"))
        let b = root.appendingPathComponent("a/b")
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: b.appendingPathComponent("up").path, withDestinationPath: "../..")

        #expect(await names(scan([root])) == ["one.txt"])
        #expect(FileSystem.enumerateDirectories(in: root, recursive: true).map(\.lastPathComponent).sorted() == ["a", "b"])
    }

    @Test func symlinkToVolumeRootIsNotWalked() async throws {
        let root = bin.appendingPathComponent("root")
        try makeFile(root.appendingPathComponent("one.txt"))
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("disk").path, withDestinationPath: "/")

        // Bounded, so a regression fails rather than walking the disk.
        let deadline = Date().addingTimeInterval(5)
        let result = await FileSystem.scanFiles(in: [root], shouldStop: { Date() > deadline })

        #expect(!result.wasStopped)
        #expect(names(result.files) == ["one.txt"])
    }

    @Test func aliasToFolderAlsoReachedDirectlyYieldsEachFileOnce() async throws {
        let root = bin.appendingPathComponent("root")
        let sub = root.appendingPathComponent("sub")
        try makeFile(sub.appendingPathComponent("one.txt"))

        let bookmark = try sub.bookmarkData(options: .suitableForBookmarkFile)
        try URL.writeBookmarkData(bookmark, to: root.appendingPathComponent("alias"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: sub)

        #expect(await names(scan([root])) == ["one.txt"])
    }

    @Test func twoLinksToOneFolderWalkItOnce() async throws {
        let root = bin.appendingPathComponent("root")
        let target = bin.appendingPathComponent("target")
        try makeFile(target.appendingPathComponent("one.txt"))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link1"), withDestinationURL: target)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link2"), withDestinationURL: target)

        #expect(await names(scan([root])) == ["one.txt"])
    }

    // MARK: - Filtering

    @Test func includesFiltersFilesButNeverFolders() async throws {
        let root = bin.appendingPathComponent("root")
        try makeFile(root.appendingPathComponent("a.txt"))
        try makeFile(root.appendingPathComponent("nested.txt/deeper/b.jpg"))

        let result = await FileSystem.scanFiles(in: [root], includes: { $0.pathExtension == "jpg" })

        #expect(names(result.files) == ["b.jpg"])
    }

    @Test func nonRecursiveListsImmediateFilesOnly() async throws {
        let root = bin.appendingPathComponent("root")
        try makeFile(root.appendingPathComponent("top.txt"))
        try makeFile(root.appendingPathComponent("nested/deep.txt"))

        let result = await FileSystem.scanFiles(in: [root], recursive: false)

        #expect(names(result.files) == ["top.txt"])
    }
}
