// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation
import os
import UniformTypeIdentifiers

/// The format a file's first bytes prove it to be, for formats with an unambiguous signature.
///
/// MPEG audio and ADTS have no signature of their own: they are proven only by an ID3v2 tag
/// followed directly by a valid frame header, since a bare frame sync turns up inside other data.
public enum ContainerSignature: Sendable, Equatable {
    case wave, aiff, isoMedia, isoImage, flac, ogg, matroska, mpeg, adts
    case jpeg, png, gif, webP, tiff, bmp, jpegXL

    /// What a file's first bytes say about its extension.
    public enum Verdict: Sendable, Equatable {
        /// The content was identified, and the extension names a type it may carry.
        case matches

        /// The content was identified as another format than the extension names.
        case mismatched(Content)

        /// No signature was recognized, or the extension is not one this judges.
        case unidentified
    }

    /// What a file holds and the extension to name it with.
    public struct Content: Sendable, Equatable {
        public let signature: ContainerSignature

        /// The specific type: `com.apple.m4a-audio` for an `M4A ` brand, not `public.mpeg-4`.
        public let type: UTType

        /// The system's preferred extension for `type`, except `opus` for Opus in Ogg.
        public let pathExtension: String

        init(_ signature: ContainerSignature, _ type: UTType, pathExtension: String? = nil) {
            self.signature = signature
            self.type = type
            self.pathExtension = pathExtension ?? type.preferredFilenameExtension ?? ""
        }
    }

    /// What a file's content proves it to be when its extension names a type that content may not
    /// carry; nil when they agree, or when the extension or the content is not one this judges.
    public static func mismatchedContent(of url: URL) throws -> Content? {
        guard case let .mismatched(content) = try verdict(of: url) else { return nil }
        return content
    }

    /// Whether a file's extension matches its content, or what the content is instead.
    public static func verdict(of url: URL) throws -> Verdict {
        guard let named = NamedType(pathExtension: url.pathExtension) else { return .unidentified }

        let header = try Header(url: url)

        guard let signature = ContainerSignature(header: header.bytes, followsID3: header.offset > 0) else {
            return .unidentified
        }

        if named.accepting.contains(signature) { return .matches }

        // TagLib reads a WAVE holding MPEG audio as MPEG when it is named so.
        if signature == .wave, named.isMPEGAudio, holdsMPEGAudio(header.bytes) {
            return .matches
        }

        return try content(signature, header: header, url: url).map(Verdict.mismatched) ?? .unidentified
    }

    /// Types whose extensions may name this content.
    var acceptedTypes: [UTType] {
        switch self {
        case .wave: [.wav]
        case .aiff: [.aiff, UTType.aifc].compactMap(\.self)
        case .isoMedia: UTType.isoMedia
        case .isoImage: [UTType.heifStandard].compactMap(\.self)
        case .flac: [UTType.flacAudio].compactMap(\.self)
        case .ogg: [UTType.oggAudio, UTType.oggVideo].compactMap(\.self)
        case .matroska: [UTType.matroskaVideo, UTType.matroskaAudio, UTType.webM].compactMap(\.self)
        case .mpeg: [.mp3, UTType.mp2].compactMap(\.self)
        case .adts: [UTType.aacAudio].compactMap(\.self)
        case .jpeg: [.jpeg, UTType.mpoImage].compactMap(\.self)
        case .png: [.png]
        case .gif: [.gif]
        case .webP: [.webP]
        case .tiff: [.tiff, .rawImage]
        case .bmp: [.bmp]
        case .jpegXL: [UTType.jpegXL].compactMap(\.self)
        }
    }

    func accepts(_ type: UTType) -> Bool {
        type.conforms(toAny: acceptedTypes)
    }

    static let all: [ContainerSignature] = [
        .wave, .aiff, .isoMedia, .isoImage, .flac, .ogg, .matroska, .mpeg, .adts,
        .jpeg, .png, .gif, .webP, .tiff, .bmp, .jpegXL,
    ]
}

/// What an extension's type may hold, cached per extension: conformance costs more than the read.
struct NamedType: Sendable {
    let accepting: Set<ContainerSignature>
    let isMPEGAudio: Bool

    private static let cache = OSAllocatedUnfairLock(initialState: [String: NamedType?]())

    /// Nil for an extension outside every format this recognizes, so a name it knows nothing about
    /// is never called wrong.
    init?(pathExtension: String) {
        let key = pathExtension.lowercased()

        if let cached = Self.cache.withLock({ $0[key] }) {
            guard let cached else { return nil }
            self = cached
            return
        }

        let judged = Self.judge(key)
        Self.cache.withLock { $0[key] = judged }

        guard let judged else { return nil }
        self = judged
    }

    private init(accepting: Set<ContainerSignature>, isMPEGAudio: Bool) {
        self.accepting = accepting
        self.isMPEGAudio = isMPEGAudio
    }

    private static func judge(_ pathExtension: String) -> NamedType? {
        guard let type = UTType(filenameExtension: pathExtension) else { return nil }

        let accepting = Set(ContainerSignature.all.filter { $0.accepts(type) })
        let isMPEGAudio = type.conforms(toAny: UTType.mpegAudio)

        guard !accepting.isEmpty || isMPEGAudio else { return nil }
        return NamedType(accepting: accepting, isMPEGAudio: isMPEGAudio)
    }
}

extension UTType {
    static let aifc = UTType("public.aifc-audio")
    static let mp2 = UTType("public.mp2")
    static let aacAudio = UTType("public.aac-audio")
    static let flacAudio = UTType("org.xiph.flac")
    static let oggAudio = UTType("org.xiph.ogg-audio")
    static let oggVideo = UTType("org.xiph.ogg-video")
    static let matroskaVideo = UTType("org.matroska.mkv")
    static let matroskaAudio = UTType("org.matroska.mka")
    static let webM = UTType("org.webmproject.webm")
    static let heifStandard = UTType("public.heif-standard")
    static let heics = UTType("public.heics")
    static let avif = UTType("public.avif")
    static let mpoImage = UTType("public.mpo-image")
    static let jpegXL = UTType("public.jpeg-xl")
    static let m4aAudio = UTType("com.apple.m4a-audio")
    static let m4bAudio = UTType("com.apple.protected-mpeg-4-audio-b")
    static let m4vVideo = UTType("com.apple.m4v-video")
    static let cr3Raw = UTType("com.canon.cr3-raw-image")
    static let threeGPP = UTType("public.3gpp")
    static let threeGPP2 = UTType("public.3gpp2")

    /// ISO base media names. A raw extension is included because CR3 is ISO base media.
    static let isoMedia: [UTType] = [
        .mpeg4Movie, .mpeg4Audio, .quickTimeMovie, UTType("com.apple.protected-mpeg-4-audio"),
        threeGPP, threeGPP2, .rawImage,
    ].compactMap(\.self)

    static let mpegAudio: [UTType] = [.mp3, mp2, aacAudio].compactMap(\.self)

    func conforms(toAny types: [UTType]) -> Bool {
        types.contains { conforms(to: $0) }
    }
}
