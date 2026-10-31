// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation
import UniformTypeIdentifiers

extension ContainerSignature {
    /// The first bytes of a file after any ID3v2 tag, where TagLib's content detection looks.
    struct Header {
        /// Enough for an Ogg page header and the start of its first packet.
        static let length = 64

        let bytes: [UInt8]

        /// Where `bytes` start in the file.
        let offset: UInt64

        init(url: URL) throws {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }

            var bytes = [UInt8](try handle.read(upToCount: Self.length) ?? Data())
            var offset: UInt64 = 0

            if bytes.count >= 10, bytes.starts(with: Array("ID3".utf8)) {
                let size = bytes[6 ... 9].reduce(0) { $0 << 7 | UInt64($1 & 0x7F) }
                let footer: UInt64 = bytes[5] & 0x10 != 0 ? 10 : 0
                offset = 10 + size + footer
                try handle.seek(toOffset: offset)
                bytes = [UInt8](try handle.read(upToCount: Self.length) ?? Data())
            }

            self.bytes = bytes
            self.offset = offset
        }
    }

    /// `header` is the first bytes of a file after any ID3v2 tag; `followsID3` when there was one.
    init?(header bytes: [UInt8], followsID3: Bool = false) {
        let text = { (offset: Int) -> String in
            guard bytes.count >= offset + 4 else { return "" }
            return String(decoding: bytes[offset ..< offset + 4], as: UTF8.self)
        }

        switch (text(0), text(8)) {
        case ("RIFF", "WAVE"), ("RF64", "WAVE"), ("BW64", "WAVE"): self = .wave
        case ("RIFF", "WEBP"): self = .webP
        case ("FORM", "AIFF"), ("FORM", "AIFC"): self = .aiff
        case (_, _) where text(4) == "ftyp":
            self = Self.isoImageBrands.contains(text(8)) ? .isoImage : .isoMedia
        case ("fLaC", _): self = .flac
        case ("OggS", _): self = .ogg
        default:
            if let signature = Self.byteSignature(bytes) {
                self = signature
            } else if followsID3, let frame = MPEGFrameHeader(bytes) {
                self = frame.isADTS ? .adts : .mpeg
            } else {
                return nil
            }
        }
    }

    private static let isoImageBrands: Set<String> = ["heic", "heix", "hevc", "mif1", "msf1", "avif", "avis"]

    private static func byteSignature(_ bytes: [UInt8]) -> ContainerSignature? {
        let jpegXLBox: [UInt8] = [0x00, 0x00, 0x00, 0x0C, 0x4A, 0x58, 0x4C, 0x20, 0x0D, 0x0A, 0x87, 0x0A]

        if bytes.starts(with: [0x1A, 0x45, 0xDF, 0xA3]) { return .matroska }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return .jpeg }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .png }
        if bytes.starts(with: Array("GIF87a".utf8)) || bytes.starts(with: Array("GIF89a".utf8)) { return .gif }
        if bytes.starts(with: [0x49, 0x49, 0x2A, 0x00]) || bytes.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) { return .tiff }
        if bytes.starts(with: [0xFF, 0x0A]) || bytes.starts(with: jpegXLBox) { return .jpegXL }

        // "BM" alone is too weak; the four reserved bytes after the file size are zero.
        if bytes.count >= 10, bytes.starts(with: Array("BM".utf8)), bytes[6 ..< 10].allSatisfy({ $0 == 0 }) {
            return .bmp
        }

        return nil
    }

    /// Whether `header` is a WAVE whose format tag is MPEG (0x0050) or MPEG Layer 3 (0x0055).
    static func holdsMPEGAudio(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 22, String(decoding: bytes[12 ..< 16], as: UTF8.self) == "fmt " else { return false }

        let format = UInt16(bytes[20]) | UInt16(bytes[21]) << 8
        return format == 0x0050 || format == 0x0055
    }

    static func content(_ signature: ContainerSignature, header: Header, url: URL) throws -> Content? {
        let bytes = header.bytes
        let text = { (offset: Int) in String(decoding: bytes[offset ..< min(offset + 4, bytes.count)], as: UTF8.self) }
        let type: UTType?

        switch signature {
        case .wave: type = .wav
        case .aiff: type = text(8) == "AIFC" ? UTType.aifc : .aiff
        case .isoMedia, .isoImage: type = isoType(brand: text(8))
        case .flac: type = UTType.flacAudio
        case .ogg:
            guard let ogg = UTType.oggAudio else { return nil }
            return Content(.ogg, ogg, pathExtension: holdsOpus(bytes) ? "opus" : nil)
        case .matroska: type = try matroskaType(url: url, offset: header.offset)
        case .mpeg: type = MPEGFrameHeader(bytes)?.layer == 3 ? .mp3 : UTType.mp2
        case .adts: type = UTType.aacAudio
        case .jpeg: type = .jpeg
        case .png: type = .png
        case .gif: type = .gif
        case .webP: type = .webP
        case .tiff: type = .tiff
        case .bmp: type = .bmp
        case .jpegXL: type = UTType.jpegXL
        }

        return type.map { Content(signature, $0) }
    }

    /// The ISO base media major brand at offset 8 picks the type.
    private static func isoType(brand: String) -> UTType? {
        switch brand {
        case "M4A ": UTType.m4aAudio
        case "M4B ": UTType.m4bAudio
        case "M4V ", "M4VH", "M4VP": UTType.m4vVideo
        case "qt  ": .quickTimeMovie
        case "crx ": UTType.cr3Raw
        case "heic", "heix": .heic
        case "hevc", "msf1": UTType.heics
        case "mif1": .heif
        case "avif", "avis": UTType.avif
        case let brand where brand.hasPrefix("3gp"): UTType.threeGPP
        case let brand where brand.hasPrefix("3g2"): UTType.threeGPP2
        default: .mpeg4Movie
        }
    }

    /// Whether the first Ogg page's packet is an Opus identification header.
    private static func holdsOpus(_ bytes: [UInt8]) -> Bool {
        guard bytes.count > 26 else { return false }
        let start = 27 + Int(bytes[26])
        guard bytes.count >= start + 8 else { return false }
        return bytes[start ..< start + 8].elementsEqual("OpusHead".utf8)
    }
}
