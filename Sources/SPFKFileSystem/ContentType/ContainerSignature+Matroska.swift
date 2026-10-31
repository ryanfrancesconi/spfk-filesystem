// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation
import UniformTypeIdentifiers

extension ContainerSignature {
    /// How far into a Matroska file to look for its Tracks element.
    static let matroskaScanLength = 64 * 1024

    /// WebM by DocType; otherwise `.mka` when the Tracks element holds no video track, `.mkv` when it
    /// does or when Tracks is not found before the first Cluster within `matroskaScanLength`.
    static func matroskaType(url: URL, offset: UInt64) throws -> UTType? {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        try handle.seek(toOffset: offset)
        let bytes = [UInt8](try handle.read(upToCount: matroskaScanLength) ?? Data())
        var reader = EBMLReader(bytes: bytes)

        guard let header = reader.element(), header.id == EBMLReader.ebmlHeader else { return UTType.matroskaVideo }

        if reader.docType(in: header) == "webm" { return UTType.webM }

        reader.position = header.end

        guard let segment = reader.element(), segment.id == EBMLReader.segment else { return UTType.matroskaVideo }

        reader.position = segment.dataStart

        while let child = reader.element(), child.id != EBMLReader.cluster {
            if child.id == EBMLReader.tracks {
                return reader.hasVideoTrack(in: child) ? UTType.matroskaVideo : UTType.matroskaAudio
            }
            guard !child.isUnknownSize else { break }
            reader.position = child.end
        }

        return UTType.matroskaVideo
    }
}

/// A bounded walk over EBML elements in a byte buffer. IDs keep their length marker, as the
/// Matroska specification writes them.
struct EBMLReader {
    static let ebmlHeader: UInt64 = 0x1A45_DFA3
    static let docType: UInt64 = 0x4282
    static let segment: UInt64 = 0x1853_8067
    static let tracks: UInt64 = 0x1654_AE6B
    static let trackEntry: UInt64 = 0xAE
    static let trackType: UInt64 = 0x83
    static let cluster: UInt64 = 0x1F43_B675

    /// TrackType value for a video track.
    static let videoTrackType: UInt64 = 1

    struct Element {
        let id: UInt64
        let dataStart: Int
        let size: UInt64?

        var isUnknownSize: Bool { size == nil }

        var end: Int { dataStart + Int(clamping: size ?? 0) }
    }

    let bytes: [UInt8]
    var position = 0

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    /// The element at `position`, which moves to its data; nil past the buffer.
    mutating func element() -> Element? {
        guard let id = variableInteger(keepingMarker: true),
              let size = variableInteger(keepingMarker: false) else { return nil }

        return Element(id: id.value, dataStart: position, size: size.isAllOnes ? nil : size.value)
    }

    func docType(in header: Element) -> String? {
        var reader = self
        reader.position = header.dataStart

        while reader.position < min(header.end, bytes.count), let child = reader.element() {
            if child.id == Self.docType, child.end <= bytes.count {
                return String(decoding: bytes[child.dataStart ..< child.end], as: UTF8.self)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
            }
            guard !child.isUnknownSize else { return nil }
            reader.position = child.end
        }
        return nil
    }

    func hasVideoTrack(in tracks: Element) -> Bool {
        var reader = self
        reader.position = tracks.dataStart
        let tracksEnd = min(tracks.end, bytes.count)

        while reader.position < tracksEnd, let entry = reader.element(), !entry.isUnknownSize {
            if entry.id == Self.trackEntry {
                var inner = reader
                while inner.position < min(entry.end, bytes.count), let field = inner.element(), !field.isUnknownSize {
                    if field.id == Self.trackType, inner.unsignedValue(of: field) == Self.videoTrackType {
                        return true
                    }
                    inner.position = field.end
                }
            }
            reader.position = entry.end
        }
        return false
    }

    private func unsignedValue(of element: Element) -> UInt64? {
        guard element.end <= bytes.count, let size = element.size, size <= 8 else { return nil }
        return bytes[element.dataStart ..< element.end].reduce(0) { $0 << 8 | UInt64($1) }
    }

    private mutating func variableInteger(keepingMarker: Bool) -> (value: UInt64, isAllOnes: Bool)? {
        guard position < bytes.count else { return nil }

        let first = bytes[position]
        guard first != 0 else { return nil }

        let length = first.leadingZeroBitCount + 1
        guard position + length <= bytes.count else { return nil }

        let marker = UInt8(0x80) >> (length - 1)
        var value = UInt64(keepingMarker ? first : first & ~marker)
        var isAllOnes = first & ~marker == marker - 1

        for byte in bytes[position + 1 ..< position + length] {
            value = value << 8 | UInt64(byte)
            isAllOnes = isAllOnes && byte == 0xFF
        }

        position += length
        return (value, isAllOnes)
    }
}
