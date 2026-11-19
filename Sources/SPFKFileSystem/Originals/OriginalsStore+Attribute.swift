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

    /// Every product's mark starts with this.
    static let attributePrefix = "com.spongefork.original."

    /// Removes every product's mark from `url`, so it stands as a new file with no original.
    public static func removeMarks(from url: URL) throws {
        let path = url.path
        let size = listxattr(path, nil, 0, 0)
        guard size > 0 else { return }

        var buffer = [CChar](repeating: 0, count: size)
        let read = listxattr(path, &buffer, size, 0)
        guard read > 0 else { return }

        let names = buffer.prefix(read).split(separator: 0).map { String(decoding: $0.map { UInt8(bitPattern: $0) }, as: UTF8.self) }

        for name in names where name.hasPrefix(attributePrefix) {
            guard removexattr(path, name, 0) != 0, errno != ENOATTR else { continue }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
