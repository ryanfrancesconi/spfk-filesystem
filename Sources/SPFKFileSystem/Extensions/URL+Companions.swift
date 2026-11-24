// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation
import SPFKBase
import UniformTypeIdentifiers

/// Files that belong to another file and travel with it: a camera RAW's XMP sidecar, and a photo's
/// or movie's `.aae` edit record.
extension URL {
    /// This file's companions that exist on disk. Empty without touching disk for any file that
    /// has none by type.
    public var existingCompanionURLs: [URL] {
        var companions: [URL] = []

        if let sidecar = existingXMPSidecarURL {
            companions.append(sidecar)
        }

        guard mayHaveEditRecord else { return companions }

        for base in editRecordBaseNames {
            guard let record = existingSibling(named: base, extensions: ["aae", "AAE"]),
                  !companions.contains(record)
            else { continue }

            companions.append(record)
        }

        return companions
    }

    /// Where `companion` goes when its owner becomes `owner`: the owner's base name with the
    /// companion's own extension.
    public func companionDestination(forOwner owner: URL) -> URL {
        owner.deletingLastPathComponent()
            .appendingPathComponent(owner.deletingPathExtension().lastPathComponent)
            .appendingPathExtension(pathExtension)
    }

    /// Where each of `companions` goes when their owner becomes `owner`, in order. An original's
    /// edit record takes `<base>_O` when the owner's own record already takes `<base>`, so
    /// `IMG_1234.aae` and `IMG_O1234.aae` become `Trip.aae` and `Trip_O.aae`.
    public static func companionDestinations(_ companions: [URL], forOwner owner: URL) -> [URL] {
        let plain = companions.map { $0.companionDestination(forOwner: owner) }
        let names = plain.map { $0.lastPathComponent.lowercased() }

        return companions.indices.map { index in
            guard companions[index].isOriginalEditRecord,
                  names.indices.contains(where: { $0 != index && names[$0] == names[index] })
            else { return plain[index] }

            return owner.deletingLastPathComponent()
                .appendingPathComponent(owner.deletingPathExtension().lastPathComponent + "_O")
                .appendingPathExtension(companions[index].pathExtension)
        }
    }

    // MARK: - Edit records

    /// `IMG_Onnnn.aae`: Photos' record of the original's edits.
    private var isOriginalEditRecord: Bool {
        let base = deletingPathExtension().lastPathComponent
        let prefix = "IMG_O"

        guard pathExtension.lowercased() == "aae", base.hasPrefix(prefix) else { return false }

        let number = base.dropFirst(prefix.count)
        return number.isNotEmpty && number.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// Photos writes an `.aae` beside an edited image or movie it exports.
    private var mayHaveEditRecord: Bool {
        guard let type = UTType(filenameExtension: pathExtension) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .movie)
    }

    /// The file's own base name, and for `IMG_nnnn` also `IMG_Onnnn`, the record of the original
    /// Photos keeps beside an edited export. `IMG_Ennnn` is a file of its own and takes neither.
    private var editRecordBaseNames: [String] {
        let base = deletingPathExtension().lastPathComponent
        let prefix = "IMG_"

        guard base.hasPrefix(prefix) else { return [base] }

        let number = base.dropFirst(prefix.count)

        guard number.isNotEmpty, number.allSatisfy({ $0.isASCII && $0.isNumber }) else { return [base] }

        return [base, "IMG_O" + number]
    }

    /// A sibling `<base>.<extension>` in any of `extensions`, named as it is on disk.
    private func existingSibling(named base: String, extensions: [String]) -> URL? {
        let folder = deletingLastPathComponent()

        for pathExtension in extensions {
            let candidate = folder.appendingPathComponent(base).appendingPathExtension(pathExtension)
            guard FileManager.default.fileExists(atPath: candidate.path) else { continue }

            // A case-insensitive volume finds either spelling; the name on disk is the one to use.
            guard let name = try? candidate.resourceValues(forKeys: [.nameKey]).name else { return candidate }
            return folder.appendingPathComponent(name)
        }

        return nil
    }
}
