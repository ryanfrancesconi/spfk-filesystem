// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

#if os(macOS)
    import AppKit
    import Foundation
    import SPFKBase
    import XAttr

    // swiftformat:disable consecutiveSpaces

    /// The 7 built-in macOS Finder label colors plus `.none`.
    ///
    /// **macOS only** (`#if os(macOS)`).
    ///
    /// Raw values match the Finder's internal label indices (0–7). The ``dataElement`` property
    /// produces the string format stored in the `com.apple.metadata:_kMDItemUserTags` extended
    /// attribute, and ``nsColor`` / ``cgColor`` provide the display colors sourced from
    /// `NSWorkspace.shared.fileLabelColors`.
    ///
    /// Initialize from a display name with ``init(name:)`` or from the xattr data element
    /// string with ``init(label:)``.
    public enum TagColor: Int, Hashable, CaseIterable, Comparable, Sendable, Codable {
        public static func < (lhs: TagColor, rhs: TagColor) -> Bool {
            lhs.name.standardCompare(with: rhs.name)
        }

        case none   = 0
        case gray   = 1
        case green  = 2
        case purple = 3
        case blue   = 4
        case yellow = 5
        case red    = 6
        case orange = 7

        /// These are the data elements stored in
        /// `com.apple.metadata:_kMDItemUserTags`
        /// It's unfortunate to hardcode these strings,
        /// but the alternative is reading the Finder preferences
        /// which would be disallowed on a sandboxed app.
        public var dataElement: String {
            switch self {
            case .none:     ""           // 0
            case .gray:     "Gray\n1"    // 1
            case .green:    "Green\n2"   // 2
            case .purple:   "Purple\n3"  // 3
            case .blue:     "Blue\n4"    // 4
            case .yellow:   "Yellow\n5"  // 5
            case .red:      "Red\n6"     // 6
            case .orange:   "Orange\n7"  // 7
            }
        }

        /// The `NSColor` for this label color, sourced from `NSWorkspace.shared.fileLabelColors`.
        public var nsColor: NSColor? {
            Self.array[self]
        }

        /// The `CGColor` equivalent of ``nsColor``.
        public var cgColor: CGColor? {
            nsColor?.cgColor
        }

        /// These should match `NSWorkspace.shared.fileLabels` and
        /// `defaults read com.apple.Finder FavoriteTagNames`
        public var name: String {
            switch self {
            case .none:     "None"       // 0
            case .gray:     "Gray"       // 1
            case .green:    "Green"      // 2
            case .purple:   "Purple"     // 3
            case .blue:     "Blue"       // 4
            case .yellow:   "Yellow"     // 5
            case .red:      "Red"        // 6
            case .orange:   "Orange"     // 7
            }
        }

        /// Creates a tag color from its display name (e.g., `"Red"`, `"Blue"`).
        /// - Returns: `nil` if no case matches the given name.
        public init?(name: String) {
            for item in Self.allCases where item.name == name {
                self = item
                return
            }

            return nil
        }

        /// Creates a tag color from its xattr data element string (e.g., `"Red\n6"`).
        /// - Returns: `nil` if no case matches the given data element.
        public init?(label: String) {
            for item in Self.allCases where item.dataElement == label {
                self = item
                return
            }

            return nil
        }

        /// Combines NSWorkspace fileLabels and fileLabelColors into one object
        static let array: [TagColor: NSColor] = {
            var array = [TagColor: NSColor]()

            // You can listen for notifications named didChangeFileLabelsNotification
            // to be notified when file labels change.
            let fileLabels = NSWorkspace.shared.fileLabels

            // This array has the same number of elements as fileLabels,
            // and the color at a given index corresponds to the label at the same index.
            let fileLabelColors = NSWorkspace.shared.fileLabelColors

            for i in 0 ..< fileLabels.count {
                guard fileLabelColors.indices.contains(i) else {
                    // according to Apple this array should match
                    continue
                }

                let fileLabel = fileLabels[i]

                guard let tagColor = TagColor(name: fileLabel) else {
                    Log.error("Unknown label: \(fileLabel)") // shouldn't happen
                    continue
                }

                array[tagColor] = fileLabelColors[i]
            }

            return array
        }()
    }

    extension [TagColor] {
        public func propertyListData() throws -> Data {
            let labels: [String] = map(\.dataElement)
            return try labels.propertyListData()
        }
    }

    extension [String] {
        public func propertyListData() throws -> Data {
            try PropertyListSerialization.data(
                fromPropertyList: self,
                format: .binary,
                options: 0
            )
        }
    }

    // swiftformat:enable consecutiveSpaces
#endif
