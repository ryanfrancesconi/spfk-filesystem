// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation
import XAttr

extension OriginalsStore {
    /// The id the file's attribute names, or nil when it has none or it is not an id.
    func keptID(of url: URL) -> UUID? {
        let path = url.path
        let size = getxattr(path, attributeName, nil, 0, 0, 0)
        guard size > 0 else { return nil }

        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes {
            getxattr(path, attributeName, $0.baseAddress, size, 0, 0)
        }
        guard read > 0 else { return nil }

        return UUID(uuidString: String(decoding: data.prefix(read), as: UTF8.self))
    }

    /// Plain `setExtendedAttribute`, not `setExtendedAttributeAndModify`: the modification date stays.
    func setAttribute(_ id: UUID, on url: URL) throws {
        try url.setExtendedAttribute(name: attributeName, value: Data(id.uuidString.utf8))
    }

    /// No-op when the file has no attribute.
    func removeAttribute(from url: URL) throws {
        guard removexattr(url.path, attributeName, 0) != 0 else { return }
        guard errno != ENOATTR else { return }
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
