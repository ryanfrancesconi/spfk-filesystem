import Foundation
import SPFKBase
import SPFKFileSystem
import SPFKTesting
import Testing

@Suite
class FileSystemTests: BinTestCase {
    // just prints values to the log
    @Test func fileSystemFreeSpace() throws {
        // returns list of Volumes - shouldn't be nil
        let volumes = try #require(
            URL(fileURLWithPath: "/Volumes").directoryContents
        )

        try volumes.forEach {
            // Free space on the volume - shouldn't be nil
            _ = try #require(
                FileSystem.freeSpaceDescription(forPath: $0.path)
            )

            _ = try #require(
                FileSystem.totalSpaceDescription(forPath: $0.path)
            )
        }

        let tmp = FileManager.default.temporaryDirectory.path

        _ = try #require(
            FileSystem.freeSpaceDescription(forPath: tmp)
        )
    }

    @Test func scanFiles() async throws {
        let directory = TestBundleResources.shared.resourcesDirectory

        let result = await FileSystem.scanFiles(in: [directory])

        #expect(result.files.count > 0)
        #expect(!result.wasStopped)
    }

    @Test func enumerateDirectories() throws {
        try FileManager.default.createDirectory(at: bin.appendingPathComponent("dir1", conformingTo: .folder), withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: bin.appendingPathComponent("dir2", conformingTo: .folder), withIntermediateDirectories: false)

        let allDirs = FileSystem.enumerateDirectories(in: bin, recursive: true)

        #expect(allDirs.count == 2)
    }

    @Test func nextAvailableURL() async throws {
        let url1 = bin.appendingPathComponent("folder", conformingTo: .folder)
        try url1.createDirectory()

        for number in 1 ... 5 {
            let next = FileSystem.nextAvailableURL(url1)
            try next.createDirectory()
            #expect(next.lastPathComponent == "folder_\(number)")
        }
    }
}
