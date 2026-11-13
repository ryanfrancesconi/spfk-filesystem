// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation

/// The files found by ``FileSystem/scanFiles(in:recursive:width:includes:shouldStop:onFound:)``.
public struct FileScanResult: Sendable {
    public let files: Set<URL>

    /// The scan ended early on a stop or task cancellation, so `files` is incomplete.
    public let wasStopped: Bool

    public init(files: Set<URL>, wasStopped: Bool) {
        self.files = files
        self.wasStopped = wasStopped
    }
}
