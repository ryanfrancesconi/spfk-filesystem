// Copyright Ryan Francesconi. All Rights Reserved.

import Foundation
import SPFKBase
import SPFKTesting
import Testing
import UniformTypeIdentifiers

@testable import SPFKFileSystem

/// A file's extension is judged against the format its first bytes prove, and a misnamed file is
/// given the system's extension for what it holds.
@Suite(.tags(.file))
final class ContainerSignatureTests: BinTestCase {
    private static let resources = TestBundleResources.shared

    private func named(_ source: URL, _ pathExtension: String) throws -> URL {
        let copy = bin.appendingPathComponent("copy-\(UUID().uuidString).\(pathExtension)")
        try FileManager.default.copyItem(at: source, to: copy)
        return copy
    }

    private func write(_ bytes: [UInt8], as pathExtension: String) throws -> URL {
        let url = bin.appendingPathComponent("bytes-\(UUID().uuidString).\(pathExtension)")
        try Data(bytes).write(to: url)
        return url
    }

    @Test(arguments: resources.oneFilePerContainer + [
        resources.sharksandwich, resources.sharksandwich_heic, resources.sharksandwich_webp,
        resources.sample_mka, resources.tabla_cprt_m4a,
    ])
    func aCorrectlyNamedFileIsNoMismatch(_ url: URL) throws {
        #expect(try ContainerSignature.mismatchedContent(of: url) == nil)
    }

    @Test(arguments: [
        (resources.tabla_m4a, "mp3", "m4a"),
        (resources.tabla_wav, "mp3", "wav"),
        (resources.tabla_flac, "mp3", "flac"),
        (resources.tabla_aif, "wav", "aiff"),
        (resources.sine_aifc, "mp3", "aifc"),
        (resources.tabla_ogg, "mp3", "ogg"),
        (resources.sine_opus, "mp3", "opus"),
        (resources.tabla_mka, "mp3", "mka"),
        (resources.sample_mkv, "mp3", "mkv"),
        (resources.sample_webm, "mp3", "webm"),
        (resources.sample_mov, "mp3", "mov"),
        (resources.tabla_mp4, "wav", "mp4"),
        (resources.tabla_cprt_m4a, "flac", "3gp"),
        (resources.sharksandwich_heic, "m4a", "heic"),
        (resources.sharksandwich_heic, "jpg", "heic"),
        (resources.sharksandwich, "heic", "jpeg"),
        (resources.sharksandwich_webp, "jpg", "webp"),
    ])
    func aMisnamedFileGetsTheExtensionOfItsContent(source: URL, named: String, expected: String) throws {
        let content = try ContainerSignature.mismatchedContent(of: try self.named(source, named))

        #expect(content?.pathExtension == expected)
        #expect(content.map { UTType(filenameExtension: expected)?.conforms(to: $0.type) == true } == true)
    }

    /// Names that share a family are each correct for the content: no rename among them.
    @Test(arguments: [
        (resources.tabla_m4a, "mp4"), (resources.tabla_mp4, "mov"), (resources.sample_mov, "m4v"),
        (resources.tabla_m4a, "m4b"), (resources.sharksandwich_heic, "heif"), (resources.tabla_aif, "aifc"),
        (resources.sine_aifc, "aif"), (resources.sample_mkv, "mka"), (resources.tabla_mka, "webm"),
        (resources.tabla_ogg, "opus"), (resources.tabla_wav, "bwf"), (resources.sharksandwich, "jpeg"),
        (resources.sharksandwich, "mpo"),
    ])
    func aNameInTheContentsFamilyIsNoMismatch(source: URL, named: String) throws {
        #expect(try ContainerSignature.mismatchedContent(of: try self.named(source, named)) == nil)
    }

    /// TIFF is the container of most raw formats, and ISO base media of CR3; neither is renamed.
    @Test(arguments: [
        ([0x49, 0x49, 0x2A, 0x00] + [UInt8](repeating: 0, count: 8), "dng"),
        ([0x4D, 0x4D, 0x00, 0x2A] + [UInt8](repeating: 0, count: 8), "nef"),
        ([0, 0, 0, 0x18] + Array("ftypcrx ".utf8) + [UInt8](repeating: 0, count: 12), "cr3"),
    ] as [([UInt8], String)])
    func aRawImageIsNotRenamed(bytes: [UInt8], named: String) throws {
        #expect(try ContainerSignature.mismatchedContent(of: try write(bytes, as: named)) == nil)
    }

    @Test(arguments: [
        ([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0x0D], "jpg", "png"),
        (Array("GIF89a".utf8) + [UInt8](repeating: 0, count: 6), "png", "gif"),
        ([0x49, 0x49, 0x2A, 0x00] + [UInt8](repeating: 0, count: 8), "jpg", "tiff"),
        (Array("BM".utf8) + [0x46, 0, 0, 0, 0, 0, 0, 0, 0x36, 0], "jpg", "bmp"),
        ([0xFF, 0x0A, 0xFA, 0x7F, 0, 0, 0, 0, 0, 0, 0, 0], "jpg", "jxl"),
        ([0, 0, 0, 0x0C, 0x4A, 0x58, 0x4C, 0x20, 0x0D, 0x0A, 0x87, 0x0A], "png", "jxl"),
        ([0, 0, 0, 0x18] + Array("ftypavif".utf8) + [UInt8](repeating: 0, count: 12), "jpg", "avif"),
        ([0, 0, 0, 0x18] + Array("ftypM4B ".utf8) + [UInt8](repeating: 0, count: 12), "mp3", "m4b"),
        ([0, 0, 0, 0x18] + Array("ftypisom".utf8) + [UInt8](repeating: 0, count: 12), "heic", "mp4"),
    ] as [([UInt8], String, String)])
    func aSignatureNamesItsType(bytes: [UInt8], named: String, expected: String) throws {
        let content = try ContainerSignature.mismatchedContent(of: try write(bytes, as: named))

        #expect(content?.pathExtension == expected)
    }

    /// "BM" opens plenty of text; only a BMP header with zero reserved bytes is taken as one.
    @Test func aWeakSignatureIsNotEnough() throws {
        let url = try write(Array("BMW owners club, chapter 7".utf8), as: "jpg")

        #expect(try ContainerSignature.mismatchedContent(of: url) == nil)
    }

    @Test(arguments: ["txt", "xyz", "pdf", ""])
    func anExtensionOutsideTheKnownFormatsIsNotJudged(named: String) throws {
        let url = try self.named(Self.resources.tabla_wav, named)

        #expect(try ContainerSignature.mismatchedContent(of: url) == nil)
    }

    @Test func anID3v2TagBeforeTheContainerIsSkipped() throws {
        // Version 4, no flags, a synchsafe size of 16, then 16 bytes of padding.
        let tag: [UInt8] = [0x49, 0x44, 0x33, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10] + [UInt8](repeating: 0, count: 16)
        let flac = try [UInt8](Data(contentsOf: Self.resources.tabla_flac))

        #expect(try ContainerSignature.mismatchedContent(of: try write(tag + flac, as: "mp3"))?.pathExtension == "flac")
    }

    /// A WAVE holding MPEG audio is MP3 to TagLib when named so, and a WAVE under any other name.
    @Test(arguments: [("mp3", nil), ("mp2", nil), ("m4a", "wav"), ("wav", nil)] as [(String, String?)])
    func aWaveHoldingMPEGAudio(named: String, expected: String?) throws {
        var header = Array("RIFF".utf8) + [0x00, 0x10, 0x00, 0x00] + Array("WAVEfmt ".utf8)
        header += [0x1E, 0x00, 0x00, 0x00, 0x55, 0x00, 0x02, 0x00] + [UInt8](repeating: 0, count: 32)

        #expect(try ContainerSignature.mismatchedContent(of: try write(header, as: named))?.pathExtension == expected)
    }

    /// An audio-only Tracks element past the scanned range is not seen, so a video track cannot be ruled out.
    @Test func matroskaWithoutTracksInRangeIsMKV() throws {
        let header: [UInt8] = [0x1A, 0x45, 0xDF, 0xA3, 0x84, 0x42, 0x82, 0x81, 0x6D]
        let segment: [UInt8] = [0x18, 0x53, 0x80, 0x67, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]
        let padding = [UInt8](repeating: 0, count: 70000)
        let void: [UInt8] = [0xEC, 0x10, 0x01, 0x11, 0x70] // 70000 bytes
        let audioTracks: [UInt8] = [0x16, 0x54, 0xAE, 0x6B, 0x85, 0xAE, 0x83, 0x83, 0x81, 0x02]

        let url = try write(header + segment + void + padding + audioTracks, as: "mp3")

        #expect(try ContainerSignature.mismatchedContent(of: url)?.pathExtension == "mkv")
    }

    @Test func aMissingFileThrows() {
        #expect(throws: (any Error).self) {
            try ContainerSignature.mismatchedContent(of: URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).mp3"))
        }
    }

    // MARK: - MPEG after an ID3v2 tag

    /// Version 4, no flags, a synchsafe size of 16, then 16 bytes of padding.
    private static let id3: [UInt8] = [0x49, 0x44, 0x33, 0x04, 0, 0, 0, 0, 0, 0x10] + [UInt8](repeating: 0, count: 16)

    /// MPEG-1 Layer III, 128 kbps, 44.1 kHz.
    private static let layer3: [UInt8] = [0xFF, 0xFB, 0x90, 0x64] + [UInt8](repeating: 0, count: 60)

    /// ADTS, 44.1 kHz.
    private static let adts: [UInt8] = [0xFF, 0xF1, 0x50, 0x80] + [UInt8](repeating: 0, count: 60)

    @Test(arguments: [
        (id3 + layer3, "aiff", "mp3"), (id3 + layer3, "wav", "mp3"), (id3 + layer3, "m4a", "mp3"),
        (id3 + adts, "mp3", "aac"), (id3 + layer3, "aac", "mp3"),
    ] as [([UInt8], String, String)])
    func anID3TagFollowedByAFrameProvesMPEG(bytes: [UInt8], named: String, expected: String) throws {
        #expect(try ContainerSignature.mismatchedContent(of: try write(bytes, as: named))?.pathExtension == expected)
    }

    @Test func anMP3NamedAsAIFFIsRenamedToMP3() throws {
        let url = try named(Self.resources.tabla_mp3, "aiff")

        #expect(try ContainerSignature.mismatchedContent(of: url)?.pathExtension == "mp3")
    }

    /// A bare frame sync turns up inside PCM, so without the tag nothing is proven.
    @Test(arguments: [
        (layer3, "aiff"),
        (id3 + [0xFF, 0xFB, 0xF0, 0x64] + [UInt8](repeating: 0, count: 60), "aiff"), // bitrate index 15
        (id3 + [0xFF, 0xEB, 0x90, 0x64] + [UInt8](repeating: 0, count: 60), "aiff"), // version bits 01
        (id3 + [UInt8](repeating: 0, count: 64), "aiff"),
    ] as [([UInt8], String)])
    func withoutATagAndAValidFrameNothingIsProven(bytes: [UInt8], named: String) throws {
        #expect(try ContainerSignature.verdict(of: try write(bytes, as: named)) == .unidentified)
    }

    // MARK: - Verdict

    @Test func aVerdictSaysWhetherAnythingWasIdentified() throws {
        #expect(try ContainerSignature.verdict(of: Self.resources.tabla_wav) == .matches)
        #expect(try ContainerSignature.verdict(of: Self.resources.tabla_mp3) == .matches)
        #expect(try ContainerSignature.verdict(of: try write(Array("plain text".utf8), as: "mp3")) == .unidentified)
        #expect(try ContainerSignature.verdict(of: Self.resources.tabla_aac) == .unidentified)
        #expect(try ContainerSignature.verdict(of: try named(Self.resources.tabla_wav, "txt")) == .unidentified)

        guard case let .mismatched(content) = try ContainerSignature.verdict(of: try named(Self.resources.tabla_wav, "mp3")) else {
            Issue.record("expected a mismatch")
            return
        }
        #expect(content.pathExtension == "wav")
    }
}
