// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation
@testable import SPFKFileSystem
import Testing

@Suite
struct FileSystemVolumeURLTests {
    private let root = URL(fileURLWithPath: "/", isDirectory: true)
    private let add = URL(fileURLWithPath: "/Volumes/ADD", isDirectory: true)
    private let add2 = URL(fileURLWithPath: "/Volumes/ADD2", isDirectory: true)

    @Test func volumeWhoseNameExtendsAMountedOneIsNotClaimedByIt() {
        let file = URL(fileURLWithPath: "/Volumes/ADD2/Pro Sound Effects/a.wav")

        #expect(FileSystem.volumeURL(forFileURL: file, among: [root, add]) == nil)
    }

    @Test func fileResolvesToItsOwnVolumeWhicheverIsListedFirst() {
        let file = URL(fileURLWithPath: "/Volumes/ADD2/a.wav")

        #expect(FileSystem.volumeURL(forFileURL: file, among: [root, add, add2]) == add2)
        #expect(FileSystem.volumeURL(forFileURL: file, among: [root, add2, add]) == add2)
    }

    @Test func volumeResolvesToItself() {
        #expect(FileSystem.volumeURL(forFileURL: add2, among: [root, add, add2]) == add2)
    }

    @Test func internalFileResolvesToTheRootVolume() {
        let file = URL(fileURLWithPath: "/Users/someone/a.wav")

        #expect(FileSystem.volumeURL(forFileURL: file, among: [root, add]) == root)
    }
}
