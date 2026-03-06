// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

#if os(macOS)
    import Foundation

    // https://developer.apple.com/documentation/coreservices/file_metadata/mditem/common_metadata_attribute_keys

    /// Parses the finder tags from this `URL`
    extension URL {
        static let userTagsKey = "com.apple.metadata:_kMDItemUserTags"

        /// The values of all tags attached to the `URL`
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

        public var tagColors: [TagColor] {
            tagNames.compactMap { TagColor(label: $0) }
        }

        public var finderTags: [FinderTagDescription] {
            var tags = [FinderTagDescription]()

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
            }

            return tags
        }

        public func set(tagColors: [TagColor]) throws {
            let labels: [String] = tagColors.compactMap(\.dataElement)
            try set(tagNames: labels)
        }

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

        public func set(finderTags: FinderTagGroup) throws {
            let colors: [String] = finderTags.tagColors.compactMap(\.dataElement)
            let textTags: [String] = finderTags.tags.filter { $0.tagColor == .none }.map(\.label)

            try set(tagNames: colors + textTags)
        }

        public func removeAllTags() throws {
            let empty: [String] = []

            try setExtendedAttributeAndModify(
                name: Self.userTagsKey,
                value: empty.propertyListData()
            )
        }
    }

    extension [URL] {
        public func set(tagNames: [String]) throws {
            for url in self {
                try url.set(tagNames: tagNames)
            }
        }

        public func set(tagColors: [TagColor]) throws {
            for url in self {
                try url.set(tagColors: tagColors)
            }
        }
    }
#endif
