// Copyright Ryan Francesconi. All Rights Reserved.

#if os(macOS)
    import AppKit
    import Foundation
    import SPFKBase
    import SPFKTesting
    import Testing

    @testable import SPFKFileSystem

    /// A folder of local files, named by `SPFK_DEVELOPMENT_RESOURCES`. Unset, these tests are disabled.
    private let developmentResources = ProcessInfo.processInfo.environment["SPFK_DEVELOPMENT_RESOURCES"]
        .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }

    @Suite(
        .tags(.development, .slow),
        .enabled(if: developmentResources != nil, "Set SPFK_DEVELOPMENT_RESOURCES to a folder holding formats/tabla.m4a")
    )
    final class FinderTagDevelopmentTests {
        @Test func dumpFinderTags() throws {
            let url = try #require(developmentResources).appendingPathComponent("formats/tabla.m4a")
            try #require(FileManager.default.fileExists(atPath: url.path))

            // Raw xattr tag names
            let tagNames = url.tagNames
            print("Raw tagNames (\(tagNames.count)):")
            for (i, name) in tagNames.enumerated() {
                let escaped = name.replacingOccurrences(of: "\n", with: "\\n")
                print("  [\(i)] \"\(escaped)\"")
            }

            // Parsed tag colors
            let tagColors = url.tagColors
            print("\nParsed tagColors (\(tagColors.count)):")
            for color in tagColors {
                print("  \(color) rawValue=\(color.rawValue) name=\(color.name)")
            }

            // Full FinderTagDescription array
            let finderTags = url.finderTags
            print("\nFinderTag descriptions (\(finderTags.count)):")
            for tag in finderTags {
                print("  label=\"\(tag.label)\" tagColor=\(tag.tagColor) (rawValue=\(tag.tagColor.rawValue))")
            }

            // FinderTagGroup
            let group = FinderTagGroup(url: url)
            print("\nFinderTagGroup:")
            print("  stringValue: \"\(group.stringValue)\"")
            print("  tagColors: \(group.tagColors)")
            print("  tags count: \(group.tags.count)")

            for tag in group.tags {
                print("  tag: label=\"\(tag.label)\" color=\(tag.tagColor) (rawValue=\(tag.tagColor.rawValue))")
            }

            // Legacy Finder label (separate from user tags)
            // Finder can display a color from this legacy label even when _kMDItemUserTags doesn't include it
            do {
                let resourceValues = try url.resourceValues(forKeys: [.labelNumberKey, .labelColorKey])

                let labelNumber = resourceValues.labelNumber ?? 0
                print("\nLegacy Finder label:")
                print("  labelNumber: \(labelNumber)")

                if let labelColor = resourceValues.labelColor {
                    print("  labelColor: \(labelColor)")
                } else {
                    print("  labelColor: nil")
                }

                // Map labelNumber to TagColor (they share the same index)
                if let tagColor = TagColor(rawValue: labelNumber), tagColor != .none {
                    print("  maps to TagColor: \(tagColor.name) (rawValue=\(tagColor.rawValue))")
                } else {
                    print("  no color label set")
                }
            } catch {
                print("\nFailed to read resource values: \(error)")
            }
        }
    }
#endif
