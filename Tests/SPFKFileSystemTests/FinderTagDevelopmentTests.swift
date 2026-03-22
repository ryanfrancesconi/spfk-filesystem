// Copyright Ryan Francesconi. All Rights Reserved.

#if os(macOS)
    import AppKit
    import Foundation
    import SPFKBase
    import SPFKTesting
    import Testing

    @testable import SPFKFileSystem

    @Suite(.tags(.development))
    final class FinderTagDevelopmentTests {
        @Test func dumpFinderTags() {
            let url = URL(fileURLWithPath: "/Users/rf/Downloads/TestResources/formats/tabla.m4a")

            guard FileManager.default.fileExists(atPath: url.path) else {
                print("File not found: \(url.path)")
                return
            }

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
