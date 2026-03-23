// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-utils

#if os(macOS)

    import Foundation
    import SPFKBase

    extension FinderTagGroup {
        /// Returns the first hex color text tag (e.g. "FF6B2CFF"), or nil.
        ///
        /// Scans text-only tags (`.none` color) looking for one whose label
        /// is a valid 8-character RGBA hex string.
        public var hexColorTag: HexColor? {
            for tag in tags where tag.tagColor == .none {
                if let hex = HexColor(string: tag.label) { return hex }
            }
            return nil
        }

        /// Returns a `HexColor` derived from the first Finder label color (sorted by rawValue), or nil.
        ///
        /// This does NOT check text-only hex tags — use ``hexColorTag`` for that.
        /// Sorting by rawValue gives Finder's internal label index order:
        /// gray(1), green(2), purple(3), blue(4), yellow(5), red(6), orange(7).
        public var hexColorFromLabel: HexColor? {
            guard let tagColor = tagColors.sorted().first,
                  let nsColor = tagColor.nsColor
            else {
                return nil
            }
            return HexColor(nsColor: nsColor)
        }

        /// Set or remove the custom hex color text tag.
        ///
        /// Removes any existing hex-color text tags first, then appends
        /// a new one if `hexColor` is non-nil.
        public mutating func setHexColorTag(_ hexColor: HexColor?) {
            // Remove existing hex color text tags
            tags.removeAll { $0.tagColor == .none && HexColor(string: $0.label) != nil }

            // Add new one if provided
            if let hexColor {
                tags.append(FinderTagDescription(label: hexColor.stringValue))
            }
        }
    }

#endif
