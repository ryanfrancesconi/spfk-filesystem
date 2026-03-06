// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation
import XAttr

extension URL {
    /// Attempt to read the quarantine attribute
    /// If result is >= 0, the attribute exists (quarantined)
    /// If result is -1, it is not present or an error occurred
    public var isQuarantined: Bool {
        getxattr(path, "com.apple.quarantine", nil, 0, 0, 0) >= 0
    }

    public func setExtendedAttributeAndModify(name: String, value: Data, options: XAttrOptions = []) throws {
        try setExtendedAttribute(
            name: name,
            value: value,
            options: options
        )

        try updateModificationDate()
    }

    public func updateModificationDate(_ now: Date = .init()) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: now],
            ofItemAtPath: path
        )
    }
}
