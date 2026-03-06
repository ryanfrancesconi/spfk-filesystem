// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation
import XAttr

/// Extended attribute (xattr) helpers for file URLs.
///
/// **Available on all Apple platforms** (macOS, iOS, tvOS, watchOS).
///
/// These methods wrap the POSIX `getxattr` / `setxattr` system calls and the `XAttr` library
/// for reading and writing file-level metadata. On macOS, the Finder tag system
/// (``URL/tagNames``, ``URL/tagColors``) builds on top of these xattr primitives.
extension URL {
    /// Whether the file has the macOS quarantine extended attribute (`com.apple.quarantine`).
    ///
    /// Files downloaded from the internet are typically quarantined by macOS. This property
    /// checks for the attribute's presence using `getxattr`.
    public var isQuarantined: Bool {
        getxattr(path, "com.apple.quarantine", nil, 0, 0, 0) >= 0
    }

    /// Sets an extended attribute and updates the file's modification date.
    ///
    /// This is the primitive used by the Finder tag system to write tag data to the
    /// `com.apple.metadata:_kMDItemUserTags` attribute while also bumping the modification
    /// date so that Spotlight and other watchers pick up the change.
    ///
    /// - Parameters:
    ///   - name: The xattr name (e.g., `"com.apple.metadata:_kMDItemUserTags"`).
    ///   - value: The binary data to store.
    ///   - options: Optional xattr write options.
    public func setExtendedAttributeAndModify(name: String, value: Data, options: XAttrOptions = []) throws {
        try setExtendedAttribute(
            name: name,
            value: value,
            options: options
        )

        try updateModificationDate()
    }

    /// Updates the file's modification date attribute.
    /// - Parameter now: The date to set. Defaults to the current date/time.
    public func updateModificationDate(_ now: Date = .init()) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: now],
            ofItemAtPath: path
        )
    }
}
