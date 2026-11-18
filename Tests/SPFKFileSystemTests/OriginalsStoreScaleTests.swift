// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation
import SPFKBase
@testable import SPFKFileSystem
import SPFKTesting
import Testing

/// Save keeps originals as a batch, and asks what keeping would cost on the main actor before it.
@Suite(.tags(.file, .slow), .serialized)
final class OriginalsStoreScaleTests: BinTestCase {
    private lazy var store = OriginalsStore(root: bin.appendingPathComponent("Originals"), product: "test")

    /// `count` clones of one file of `bytes`, so the fixture costs no disk.
    private func files(_ count: Int, bytes: Int) throws -> [URL] {
        let folder = bin.appendingPathComponent("Files", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let seed = folder.appendingPathComponent("seed.jpg")
        try Data((0 ..< bytes).map { UInt8(truncatingIfNeeded: $0 &* 31) }).write(to: seed)

        return try (0 ..< count).map { index in
            let url = folder.appendingPathComponent("photo-\(index).jpg")
            try FileManager.default.copyItem(at: seed, to: url)
            return url
        }
    }

    @Test func keepingABatchOfPhotosRetainsNothingPerFile() async throws {
        let urls = try files(320, bytes: 6_000_000)
        let store = store

        let grown = try await retainedMemoryMB(warmUp: 20, measured: 300, width: 8) { index in
            _ = try store.keep(urls[index])
        }

        #expect(store.total().count == 320)
        #expect(grown < 40, "grew \(Int(grown)) MB over 300 originals")
    }

    /// Too slow for the main actor (537 ms in Debug), so callers assess it off the main actor. A regression bound.
    @Test func theCostOfTenThousandFilesStaysBounded() throws {
        let urls = try files(10_000, bytes: 1024)
        for url in urls.prefix(5000) {
            _ = try store.keep(url)
        }

        let start = Date()
        let cost = store.cost(toKeep: urls)
        let elapsed = Date().timeIntervalSince(start)

        print("ORIGINALS-COST 10000 files: \(Int(elapsed * 1000)) ms")
        #expect(cost.count == 5000)
        #expect(elapsed < 2)
    }
}
