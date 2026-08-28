// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation

/// Reading and clearing the flags that make a file refuse a write.
///
/// A locked file reads perfectly -- it parses, displays and accepts an edit in the UI, and only
/// the save is refused. Libraries make that worse by falling back to a read-only handle when
/// `fopen(path, "rb+")` returns `EPERM`, so the failure surfaces far from its cause with no reason
/// attached. ``requireWritable()`` is the guard that turns it back into one error at the entry
/// point.
extension URL {
    /// The file's current lock state, read fresh. One `resourceValues` call.
    ///
    /// A file that does not exist is ``FileLockState/writable``: nothing is in the way that this
    /// type is about, and callers already have their own missing-file state.
    public var lockState: FileLockState {
        guard let values = try? resourceValues(forKeys: [
            .volumeIsReadOnlyKey, .isUserImmutableKey, .isSystemImmutableKey, .isWritableKey,
        ]) else {
            return .writable
        }

        // Volume before file: unlocking a file on a read-only mount changes nothing, so reporting
        // "Locked" there would send the user to a control that cannot help.
        if values.volumeIsReadOnly == true { return .readOnlyVolume }
        if values.isUserImmutable == true { return .locked }
        if values.isSystemImmutable == true { return .notPermitted }
        if values.isWritable == false { return .notPermitted }

        return .writable
    }

    /// Whether ``lockState`` is ``FileLockState/locked``.
    public var isLocked: Bool { lockState == .locked }

    /// Sets the `uchg` flag -- what Finder's Get Info "Locked" checkbox does.
    public func lock() throws {
        try setUserImmutable(true)
    }

    /// Clears the `uchg` flag.
    ///
    /// Moves the file's attribute modification date and leaves its content date alone, so an
    /// observer classifies this as ``FileModificationKind/attributes``. Callers watching the file
    /// must wrap it in ``FileModificationObserver/suppress()`` / ``FileModificationObserver/unsuppress()``
    /// or it comes straight back as an external change.
    public func unlock() throws {
        try setUserImmutable(false)
    }

    /// Throws a ``FileLockError`` unless the file will accept a write.
    ///
    /// Belongs at a save's entry point rather than at each write it performs: the flag refuses the
    /// tag write, the Finder-tag write and the modification-date bump alike, so checking once is
    /// what keeps a locked file from being half-saved.
    public func requireWritable() throws {
        let state = lockState

        guard state.isWritable else {
            throw FileLockError(url: self, state: state)
        }
    }

    private func setUserImmutable(_ immutable: Bool) throws {
        var url = self
        var values = URLResourceValues()
        values.isUserImmutable = immutable
        try url.setResourceValues(values)
    }
}
