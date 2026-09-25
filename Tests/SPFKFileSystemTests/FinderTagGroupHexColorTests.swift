// Copyright Ryan Francesconi. All Rights Reserved.

#if os(macOS)

    import Foundation
    import SPFKBase
    import Testing

    @testable import SPFKFileSystem

    /// Tests for the FinderTagGroup+HexColor extension (hexColorTag getter,
    /// updateCustom mutator) and Codable round-trips involving hex color
    /// text tags.
    @Suite
    final class FinderTagGroupHexColorTests {
        // MARK: - hexColorTag getter

        @Test func hexColorTagNilForEmptyGroup() {
            let group = FinderTagGroup()
            #expect(group.hexColorTag == nil)
        }

        @Test func hexColorTagNilForColorOnlyGroup() {
            let group = FinderTagGroup(tags: [
                FinderTagDescription(tagColor: .red),
                FinderTagDescription(tagColor: .blue),
            ])
            #expect(group.hexColorTag == nil)
        }

        @Test func hexColorTagIgnoresNonHexTextTags() {
            let group = FinderTagGroup(tags: [
                FinderTagDescription(label: "NotAHexString"),
                FinderTagDescription(label: "AlsoNotHex"),
            ])
            #expect(group.hexColorTag == nil)
        }

        @Test func hexColorTagFindsHexAmongNonHexTextTags() {
            let group = FinderTagGroup(tags: [
                FinderTagDescription(label: "SomeLabel"),
                FinderTagDescription(label: "FF2160FF"),
            ])
            #expect(group.hexColorTag?.stringValue == "FF2160FF")
        }

        @Test func hexColorTagReturnsFirstHex() {
            let group = FinderTagGroup(tags: [
                FinderTagDescription(label: "FF2160FF"),
                FinderTagDescription(label: "00FF00FF"),
            ])
            #expect(group.hexColorTag?.stringValue == "FF2160FF")
        }

        // MARK: - setHexColorTag mutator

        @Test func setHexColorTagAddsToEmptyGroup() {
            var group = FinderTagGroup()
            group.updateCustom(hexColor: HexColor(string: "FF2160FF"))

            #expect(group.tags.count == 1)
            #expect(group.tags[0].tagColor == .none)
            #expect(group.tags[0].label == "FF2160FF")
        }

        @Test func setHexColorTagReplacesExisting() {
            var group = FinderTagGroup()
            group.updateCustom(hexColor: HexColor(string: "FF2160FF"))
            group.updateCustom(hexColor: HexColor(string: "00FF00FF"))

            #expect(group.tags.count == 1)
            #expect(group.hexColorTag?.stringValue == "00FF00FF")
        }

        @Test func setHexColorTagNilClearsHexTag() {
            var group = FinderTagGroup(tags: [
                FinderTagDescription(tagColor: .red),
            ])
            group.updateCustom(hexColor: HexColor(string: "FF2160FF"))
            #expect(group.tags.count == 2)

            group.updateCustom(hexColor: nil)
            #expect(group.tags.count == 1)
            #expect(group.hexColorTag == nil)
            #expect(group.tags[0].tagColor == .red)
        }

        @Test func setHexColorTagPreservesNonHexTextTags() {
            var group = FinderTagGroup(tags: [
                FinderTagDescription(label: "MyCustomTag"),
                FinderTagDescription(tagColor: .red),
            ])
            group.updateCustom(hexColor: HexColor(string: "FF2160FF"))

            #expect(group.tags.count == 3)
            #expect(group.tags.contains(where: { $0.label == "MyCustomTag" }))
            #expect(group.hexColorTag?.stringValue == "FF2160FF")
        }

        @Test func setHexColorTagClearsOnlyHexNotCustomText() {
            var group = FinderTagGroup(tags: [
                FinderTagDescription(label: "MyCustomTag"),
            ])
            group.updateCustom(hexColor: HexColor(string: "FF2160FF"))
            #expect(group.tags.count == 2)

            group.updateCustom(hexColor: nil)
            #expect(group.tags.count == 1)
            #expect(group.tags[0].label == "MyCustomTag")
        }

        // MARK: - Codable with hex color tags

        @Test func encodeDecodeHexColorTextTag() throws {
            let tag = FinderTagDescription(label: "FF2160FF")
            let data = try JSONEncoder().encode(tag)
            let decoded = try JSONDecoder().decode(FinderTagDescription.self, from: data)
            #expect(decoded.tagColor == .none)
            #expect(decoded.label == "FF2160FF")
        }

        @Test func encodeDecodeGroupWithHexColorTag() throws {
            var group = FinderTagGroup(tags: [
                FinderTagDescription(tagColor: .red),
                FinderTagDescription(tagColor: .orange),
            ])
            group.updateCustom(hexColor: HexColor(string: "FF2160FF"))

            let data = try JSONEncoder().encode(group)
            let decoded = try JSONDecoder().decode(FinderTagGroup.self, from: data)

            #expect(decoded.tags.count == 3)
            #expect(decoded.hexColorTag?.stringValue == "FF2160FF")
        }

        @Test func encodeDecodeGroupWithOnlyHexColorTag() throws {
            var group = FinderTagGroup()
            group.updateCustom(hexColor: HexColor(string: "53A653AE"))

            let data = try JSONEncoder().encode(group)
            let decoded = try JSONDecoder().decode(FinderTagGroup.self, from: data)

            #expect(decoded.tags.count == 1)
            #expect(decoded.tags[0].tagColor == .none)
            #expect(decoded.tags[0].label == "53A653AE")
            #expect(decoded.hexColorTag?.stringValue == "53A653AE")
        }

        @Test func encodeDecodeGroupMixedTagsAndHexColor() throws {
            var group = FinderTagGroup(tags: [
                FinderTagDescription(tagColor: .red),
                FinderTagDescription(tagColor: .purple),
                FinderTagDescription(tagColor: .gray),
                FinderTagDescription(tagColor: .orange),
                FinderTagDescription(tagColor: .green),
                FinderTagDescription(tagColor: .blue),
            ])
            group.updateCustom(hexColor: HexColor(string: "000000FF"))

            let data = try JSONEncoder().encode(group)
            let decoded = try JSONDecoder().decode(FinderTagGroup.self, from: data)

            #expect(decoded.tags.count == 7)
            #expect(decoded.hexColorTag?.stringValue == "000000FF")

            let colorTags = decoded.tags.filter { $0.tagColor != .none }
            #expect(colorTags.count == 6)
        }

        @Test func multipleRoundTripsPreserveHexColorTag() throws {
            var group = FinderTagGroup(tags: [
                FinderTagDescription(tagColor: .red),
            ])
            group.updateCustom(hexColor: HexColor(string: "53A653AE"))

            for _ in 0 ..< 10 {
                let data = try JSONEncoder().encode(group)
                group = try JSONDecoder().decode(FinderTagGroup.self, from: data)
            }

            #expect(group.tags.count == 2)
            #expect(group.hexColorTag?.stringValue == "53A653AE")
        }

        @Test func encodeDecodeAllDefaultTagsPlusHex() throws {
            var group = FinderTagGroup.defaultTags
            group.updateCustom(hexColor: HexColor(string: "AABBCCDD"))

            let data = try JSONEncoder().encode(group)
            let decoded = try JSONDecoder().decode(FinderTagGroup.self, from: data)

            #expect(decoded.tags.count == TagColor.allCases.count + 1)
            #expect(decoded.hexColorTag?.stringValue == "AABBCCDD")

            for tagColor in TagColor.allCases {
                #expect(decoded.tags.contains(where: { $0.tagColor == tagColor }))
            }
        }

        // MARK: - Interactions with insert/update

        @Test func insertColorsPreservesHexTag() {
            var group = FinderTagGroup(tags: [
                FinderTagDescription(tagColor: .red),
            ])
            group.updateCustom(hexColor: HexColor(string: "53A653AE"))

            group.insert(colors: [FinderTagDescription(tagColor: .blue)])

            #expect(group.hexColorTag?.stringValue == "53A653AE")
            #expect(group.tagColors == [.blue])
        }

        @Test func updateColorsPreservesHexTag() {
            var group = FinderTagGroup(tags: [
                FinderTagDescription(tagColor: .red),
            ])
            group.updateCustom(hexColor: HexColor(string: "53A653AE"))

            group.update(colors: [FinderTagDescription(tagColor: .orange)])

            #expect(group.hexColorTag?.stringValue == "53A653AE")
            #expect(group.tags.contains(where: { $0.tagColor == .orange }))
            #expect(!group.tags.contains(where: { $0.tagColor == .red }))
        }

        // MARK: - tagColors/labels() with hex tags

        @Test func tagColorsExcludesHexTextTags() {
            var group = FinderTagGroup(tags: [
                FinderTagDescription(tagColor: .red),
                FinderTagDescription(tagColor: .green),
            ])
            group.updateCustom(hexColor: HexColor(string: "FF2160FF"))

            #expect(group.tagColors.count == 2)
        }

        @Test func labelsExcludesHexTextTags() {
            var group = FinderTagGroup(tags: [
                FinderTagDescription(tagColor: .red),
            ])
            group.updateCustom(hexColor: HexColor(string: "FF2160FF"))

            #expect(group.labels() == ["Red"])
        }

        @Test func defaultColorNilWhenOnlyHexTags() {
            var group = FinderTagGroup()
            group.updateCustom(hexColor: HexColor(string: "FF2160FF"))
            #expect(group.defaultColor == nil)
        }

        @Test func stringValueIncludesHexColorLabel() {
            var group = FinderTagGroup(tags: [
                FinderTagDescription(tagColor: .red),
            ])
            group.updateCustom(hexColor: HexColor(string: "FF2160FF"))
            #expect(group.stringValue.contains("FF2160FF"))
            #expect(group.stringValue.contains("Red"))
        }
    }

#endif
