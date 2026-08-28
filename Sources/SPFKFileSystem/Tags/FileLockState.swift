// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation

/// Why a file refuses a write, or that it does not.
///
/// Not a `Bool`, because `isWritable` cannot say *why*: a file the owner has made read-only and a
/// file carrying the `uchg` flag both report `false`, and only the second is something an app can
/// offer to clear. Anything deciding whether to show an Unlock control has to read ``locked``
/// rather than "not writable".
public enum FileLockState: String, Codable, Hashable, Sendable, CaseIterable {
    /// Writable. Nothing is in the way.
    case writable

    /// The `uchg` user-immutable flag -- Finder's Get Info "Locked" checkbox. The only state
    /// ``URL/unlock()`` can clear.
    case locked

    /// The volume itself is mounted read-only. Unlocking cannot help.
    case readOnlyVolume

    /// POSIX permissions deny the write, or the `schg` system-immutable flag is set (root only).
    /// Folded together because neither is fixable from here and the user's next step is the same.
    case notPermitted

    public var isWritable: Bool { self == .writable }

    /// Whether ``URL/unlock()`` can clear this.
    public var canUnlock: Bool { self == .locked }

    /// - Note: Unlocalized. This package carries no string catalog; a product surfacing this to
    ///   the user localizes at its own layer.
    public var localizedDescription: String {
        switch self {
        case .writable: "Writable"
        case .locked: "Locked"
        case .readOnlyVolume: "On a read-only volume"
        case .notPermitted: "Not writable"
        }
    }

    /// What a failed write should tell the user, given the file it failed on.
    public func failureDescription(for url: URL) -> String {
        let name = url.lastPathComponent

        return switch self {
        case .writable: "\(name) could not be written"
        case .locked: "\(name) is locked. Unlock it to save changes."
        case .readOnlyVolume: "\(name) is on a read-only volume and cannot be changed."
        case .notPermitted: "\(name) is not writable. Check its permissions."
        }
    }
}

/// A write refused before it was attempted, carrying the state that refused it.
///
/// A dedicated type rather than `NSError(description:)` so an Unlock affordance can ask *which*
/// failure this is by type rather than by matching a message.
public struct FileLockError: LocalizedError, Hashable, Sendable {
    public let url: URL
    public let state: FileLockState

    public init(url: URL, state: FileLockState) {
        self.url = url
        self.state = state
    }

    public var canUnlock: Bool { state.canUnlock }

    public var errorDescription: String? { state.failureDescription(for: url) }
}
