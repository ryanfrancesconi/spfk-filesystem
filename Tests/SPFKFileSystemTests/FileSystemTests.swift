import Foundation
import SPFKFileSystem
import SPFKTesting
import Testing

@Suite(.serialized)
class FileSystemTests: BinTestCase {
    // just prints values to the log
    @Test func fileSystemFreeSpace() throws {
        // returns list of Volumes - shouldn't be nil
        let volumes = try #require(
            URL(fileURLWithPath: "/Volumes").directoryContents
        )

        try volumes.forEach {
            // Free space on the volume - shouldn't be nil
            let freeSpace = try #require(
                // will also check getSystemFreeSizeInBytes
                FileSystem.getSystemFreeSizeDescription(forPath: $0.path)
            )

            let totalSpace = try #require(
                FileSystem.getSystemSizeDescription(forPath: $0.path)
            )

            Log.debug($0.path, "\(freeSpace)/\(totalSpace)")
        }

        let tmp = FileManager.default.temporaryDirectory.path

        let tmpFreeSpace = try #require(
            FileSystem.getSystemFreeSizeDescription(forPath: tmp)
        )

        Log.debug(tmp, tmpFreeSpace)
    }

    // seems to fail with [] - permissions?
    @Test func getFileURLs() throws {
        let directory = TestBundleResources.shared.resourcesDirectory

        let urls = FileSystem.getFileURLs(in: directory, recursive: true)

        Log.debug(urls)

        #expect(urls.count > 0)
    }

    @Test func getDirectories() throws {
        try FileManager.default.createDirectory(at: bin.appendingPathComponent("dir1", conformingTo: .folder), withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: bin.appendingPathComponent("dir2", conformingTo: .folder), withIntermediateDirectories: false)

        let allDirs = FileSystem.getDirectories(in: bin, recursive: true)

        Log.debug(allDirs.map(\.path))

        #expect(allDirs.count == 2)
    }

    @Test("nextAvailableURL", .serialized, arguments: [1, 2, 3, 4, 5])
    func nextAvailableURL(_ number: Int) async throws {
        deleteBinOnExit = number == 5 // delete bin on last run but not before

        let url1 = bin.appendingPathComponent("folder", conformingTo: .folder)

        if !url1.exists {
            try url1.createDirectory()
        }

        let next1 = FileSystem.nextAvailableURL(url1)

        if !next1.exists {
            try next1.createDirectory()
            #expect(next1.lastPathComponent == "folder_\(number)")
        }
    }

    @Test func fileURLStream() async throws {
        // Create some files in the bin directory
        for i in 0 ..< 5 {
            let url = bin.appendingPathComponent("file\(i).txt")
            try Data("test".utf8).write(to: url)
        }

        // Create a subdirectory with more files
        let subdir = bin.appendingPathComponent("subdir", conformingTo: .folder)
        try subdir.createDirectory()

        for i in 0 ..< 3 {
            let url = subdir.appendingPathComponent("nested\(i).txt")
            try Data("test".utf8).write(to: url)
        }

        // Collect async stream results
        var streamURLs = [URL]()
        for await url in FileSystem.fileURLStream(in: [bin]) {
            streamURLs.append(url)
        }

        // Compare with synchronous version
        let syncURLs = FileSystem.getFileURLs(in: [bin])

        #expect(Set(streamURLs) == syncURLs)
        #expect(streamURLs.count == 8)
    }
}
