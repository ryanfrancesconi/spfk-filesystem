// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation
import SPFKBase

/// Files that belong to another file and travel with it: today, a camera RAW's XMP sidecar.
extension URL {
    /// This file's companions that exist on disk. Empty without touching disk for any file that
    /// has none by type.
    public var existingCompanionURLs: [URL] {
        guard let sidecar = existingXMPSidecarURL else { return [] }
        return [sidecar]
    }

    /// Where `companion` goes when its owner becomes `owner`: the owner's base name with the
    /// companion's own extension.
    public func companionDestination(forOwner owner: URL) -> URL {
        owner.deletingLastPathComponent()
            .appendingPathComponent(owner.deletingPathExtension().lastPathComponent)
            .appendingPathExtension(pathExtension)
    }
}
