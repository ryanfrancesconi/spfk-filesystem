// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

#if os(macOS)
    import Foundation

    // https://developer.apple.com/documentation/coreservices/file_metadata/mditem/common_metadata_attribute_keys

    /// Finder tag read/write extensions for `URL`.
    ///
    /// **macOS only** (`#if os(macOS)`).
    ///
    /// These properties and methods read and write the
    /// `com.apple.metadata:_kMDItemUserTags` extended attribute, which is the
    /// storage mechanism macOS Finder uses for both built-in color labels and
    /// custom text tags. Each tag is stored as a property-list–encoded string
    /// array; color tags use the format `"Color\nIndex"` (e.g., `"Red\n6"`),
    /// while text-only tags are bare strings.
    ///
    /// Reading is non-throwing — missing or unreadable attributes return empty
    /// arrays. Writing is throwing because xattr operations can fail (e.g., on
    /// read-only volumes).
    ///
    /// The underlying xattr I/O is performed by ``setExtendedAttributeAndModify(name:value:options:)``
    /// in `URL+XAttr.swift`, which also bumps the file's modification date so
    /// Spotlight picks up the change.
    ///
    /// - SeeAlso: ``TagColor``, ``FinderTagDescription``, ``FinderTagGroup``
    extension URL {
        /// The xattr key for Finder user tags.
        static let userTagsKey = "com.apple.metadata:_kMDItemUserTags"

        /// The legacy Finder label color for this file, if any.
        ///
        /// macOS maintains a separate per-file label index (0–7) stored via
        /// `URLResourceKey.labelNumberKey`. Finder displays this label even
        /// when the `_kMDItemUserTags` xattr doesn't include it. Returns
        /// `nil` when the label is `.none` (0) or unreadable.
        var legacyLabelColor: TagColor? {
            guard let resourceValues = try? resourceValues(forKeys: [.labelNumberKey]),
                  let labelNumber = resourceValues.labelNumber,
                  let tagColor = TagColor(rawValue: labelNumber),
                  tagColor != .none
            else {
                return nil
            }

            return tagColor
        }

        /// The raw tag name strings attached to this file URL.
        ///
        /// Color tags appear in `"Color\nIndex"` format (e.g., `"Red\n6"`);
        /// custom text tags are plain strings. Returns an empty array if the
        /// attribute is missing or cannot be read.
        public var tagNames: [String] {
            do {
                let data = try extendedAttributeValue(forName: Self.userTagsKey)

                return try PropertyListDecoder().decode(
                    [String].self,
                    from: data
                )

            } catch {
                // Log.error(error)
                return []
            }
        }

        /// The ``TagColor`` values derived from this file's tags.
        ///
        /// Includes colors from the `_kMDItemUserTags` xattr and the legacy
        /// Finder label (``legacyLabelColor``). The legacy label is appended
        /// only when it isn't already present in the xattr colors.
        public var tagColors: [TagColor] {
            var colors = tagNames.compactMap { TagColor(label: $0) }

            if let legacy = legacyLabelColor, !colors.contains(legacy) {
                colors.append(legacy)
            }

            return colors
        }

        /// All Finder tags on this file as ``FinderTagDescription`` values.
        ///
        /// Both color labels and custom text-only tags are included. Tags that
        /// match a known ``TagColor`` are created via
        /// ``FinderTagDescription/init(tagColor:)``, while unrecognised strings
        /// become text-only descriptions via ``FinderTagDescription/init(label:)``.
        ///
        /// The legacy Finder label (``legacyLabelColor``) is included when it
        /// isn't already present among the xattr-derived color tags.
        public var finderTags: [FinderTagDescription] {
            var tags = [FinderTagDescription]()
            var colorsSeen = Set<TagColor>()

            for string in tagNames {
                guard let tagColor = TagColor(label: string) else {
                    tags.insert(
                        FinderTagDescription(label: string)
                    )
                    continue
                }

                tags.insert(
                    FinderTagDescription(tagColor: tagColor)
                )
                colorsSeen.insert(tagColor)
            }

            // Include legacy Finder label if not already present from xattr tags
            if let legacy = legacyLabelColor, !colorsSeen.contains(legacy) {
                tags.insert(
                    FinderTagDescription(tagColor: legacy)
                )
            }

            return tags
        }

        /// Replaces this file's Finder color tags.
        ///
        /// Converts each ``TagColor`` to its ``TagColor/dataElement`` string and
        /// writes the result to the `_kMDItemUserTags` extended attribute.
        /// - Parameter tagColors: The color tags to apply. Pass an empty array
        ///   to remove all tags.
        public func set(tagColors: [TagColor]) throws {
            let labels: [String] = tagColors.compactMap(\.dataElement)
            try set(tagNames: labels)
        }

        /// Replaces this file's Finder tags with the given raw name strings.
        ///
        /// If `tagNames` is empty, all tags are removed via ``removeAllTags()``.
        /// - Parameter tagNames: Raw tag strings in the format stored by the
        ///   xattr (e.g., `"Red\n6"` for colors, or plain text for custom tags).
        public func set(tagNames: [String]) throws {
            guard tagNames.isNotEmpty else {
                try removeAllTags()
                return
            }

            let data = try tagNames.propertyListData()

            try setExtendedAttributeAndModify(
                name: Self.userTagsKey,
                value: data
            )
        }

        /// Replaces this file's Finder tags from a ``FinderTagGroup``.
        ///
        /// Color tags are written using their ``TagColor/dataElement`` encoding,
        /// followed by any text-only tags (those with ``TagColor/none``).
        /// - Parameter finderTags: The tag group to apply.
        public func set(finderTags: FinderTagGroup) throws {
            let colors: [String] = finderTags.tagColors.compactMap(\.dataElement)
            let textTags: [String] = finderTags.tags.filter { $0.tagColor == .none }.map(\.label)

            try set(tagNames: colors + textTags)
        }

        /// Removes all Finder tags from this file, including the legacy label.
        ///
        /// Clears the `_kMDItemUserTags` xattr and resets the legacy Finder
        /// label (`labelNumberKey`) to 0 (none).
        public func removeAllTags() throws {
            let empty: [String] = []

            try setExtendedAttributeAndModify(
                name: Self.userTagsKey,
                value: empty.propertyListData()
            )

            try removeLegacyLabel()
        }

        /// Resets the legacy Finder label to none (0).
        ///
        /// Sets `URLResourceKey.labelNumberKey` to 0 via `setResourceValues`.
        public func removeLegacyLabel() throws {
            var url = self
            var resourceValues = URLResourceValues()
            resourceValues.labelNumber = 0
            try url.setResourceValues(resourceValues)
        }
    }

    /// Batch Finder tag operations on an array of file URLs.
    ///
    /// **macOS only** (`#if os(macOS)`).
    ///
    /// Convenience methods that apply the same set of tags to every URL in the
    /// array. Each call iterates the array and delegates to the single-URL
    /// ``URL/set(tagNames:)`` or ``URL/set(tagColors:)`` method.
    extension [URL] {
        /// Applies the given raw tag name strings to every URL in the array.
        /// - Parameter tagNames: Raw tag strings (see ``URL/set(tagNames:)``).
        public func set(tagNames: [String]) throws {
            for url in self {
                try url.set(tagNames: tagNames)
            }
        }

        /// Applies the given color tags to every URL in the array.
        /// - Parameter tagColors: The color tags to apply (see ``URL/set(tagColors:)``).
        public func set(tagColors: [TagColor]) throws {
            for url in self {
                try url.set(tagColors: tagColors)
            }
        }
    }
#endif
