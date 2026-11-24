// Copyright Ryan Francesconi. All Rights Reserved.

#if os(macOS)

    import AVFoundation
    import Foundation
    import ImageIO
    import SPFKBase
    import SPFKTesting
    import Testing
    import UniformTypeIdentifiers

    @testable import SPFKFileSystem

    @Suite(.tags(.file, .renameOrganize))
    @MainActor
    struct LivePhotoIdentifierTests {
        typealias Sandbox = FileCommandsTests.Sandbox

        @Test func makerAppleTag17IsTheIdentifier() {
            let live: [CFString: Any] = [kCGImagePropertyMakerAppleDictionary: ["17": "6A1E0C7B-0000"]]
            let empty: [CFString: Any] = [kCGImagePropertyMakerAppleDictionary: ["17": ""]]
            let other: [CFString: Any] = [kCGImagePropertyMakerAppleDictionary: ["11": "burst"]]

            #expect(LivePhotoIdentifier.value(inImageProperties: live) == "6A1E0C7B-0000")
            #expect(LivePhotoIdentifier.value(inImageProperties: empty) == nil)
            #expect(LivePhotoIdentifier.value(inImageProperties: other) == nil)
            #expect(LivePhotoIdentifier.value(inImageProperties: [:]) == nil)
        }

        @Test(arguments: [UTType.jpeg, .heic])
        func aStillReadsTheIdentifierItWasWrittenWith(type: UTType) throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let identifier = UUID().uuidString
            let still = try LivePhotoFixtures.still(type, identifier: identifier, in: dir.url)

            #expect(LivePhotoIdentifier.still(at: still) == identifier)
        }

        @Test func aStillWithoutTheTagHasNone() throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let still = try LivePhotoFixtures.still(.jpeg, identifier: nil, in: dir.url)

            #expect(LivePhotoIdentifier.still(at: still) == nil)
        }

        @Test func aMovieReadsTheIdentifierItWasWrittenWith() async throws {
            let dir = try Sandbox()
            defer { dir.remove() }

            let identifier = UUID().uuidString
            let movie = try await LivePhotoFixtures.movie(identifier: identifier, in: dir.url)

            #expect(await LivePhotoIdentifier.movie(at: movie) == identifier)
        }

        @Test func aMovieWithoutTheItemHasNone() async {
            #expect(await LivePhotoIdentifier.movie(at: TestBundleResources.shared.sample_mov) == nil)
        }
    }

    /// A Live Photo's still and movie, written with the identifier they share.
    enum LivePhotoFixtures {
        static func still(_ type: UTType, identifier: String?, named name: String = "IMG_1234", in folder: URL) throws -> URL {
            let url = folder.appendingPathComponent(name).appendingPathExtension(type.preferredFilenameExtension ?? "jpg")

            guard let context = CGContext(
                data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ),
                let image = context.makeImage(),
                let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
            else { throw FixtureError() }

            let properties: [CFString: Any] = identifier.map { [kCGImagePropertyMakerAppleDictionary: ["17": $0]] } ?? [:]
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)

            guard CGImageDestinationFinalize(destination) else { throw FixtureError() }

            return url
        }

        static func movie(identifier: String, named name: String = "IMG_1234", in folder: URL) async throws -> URL {
            let url = folder.appendingPathComponent(name).appendingPathExtension("MOV")
            let item = AVMutableMetadataItem()
            item.identifier = .quickTimeMetadataContentIdentifier
            item.value = identifier as NSString
            item.dataType = kCMMetadataBaseDataType_UTF8 as String

            guard let session = AVAssetExportSession(
                asset: AVURLAsset(url: TestBundleResources.shared.sample_mov),
                presetName: AVAssetExportPresetPassthrough
            ) else { throw FixtureError() }

            session.metadata = [item]

            guard #available(macOS 15, iOS 18, *) else { throw FixtureError() }
            try await session.export(to: url, as: .mov)

            return url
        }

        struct FixtureError: Error {}
    }

#endif
