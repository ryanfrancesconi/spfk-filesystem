// Copyright Ryan Francesconi. All Rights Reserved.

#if os(macOS)

    import Foundation
    import SPFKBase
    import Testing

    @testable import SPFKFileSystem

    /// Tests for FinderTagGroup and FinderTagDescription — Codable round-trips,
    /// computed properties, mutating methods, and edge cases.
    @Suite
    final class FinderTagGroupTests {
        // MARK: - FinderTagDescription basics

        @Test func encodeDecodeStandardColorTag() throws {
            let tag = FinderTagDescription(tagColor: .red)
            let data = try JSONEncoder().encode(tag)
            let decoded = try JSONDecoder().decode(FinderTagDescription.self, from: data)
            #expect(decoded.tagColor == .red)
            #expect(decoded.label == "Red")
        }

        @Test func encodeDecodeCustomTextTag() throws {
            let tag = FinderTagDescription(label: "MyTag")
            let data = try JSONEncoder().encode(tag)
            let decoded = try JSONDecoder().decode(FinderTagDescription.self, from: data)
            #expect(decoded.tagColor == .none)
            #expect(decoded.label == "MyTag")
        }

        @Test func tagDescriptionComparable() {
            let red = FinderTagDescription(tagColor: .red)
            let blue = FinderTagDescription(tagColor: .blue)
            let custom = FinderTagDescription(label: "AAA")

            // Comparable uses label.standardCompare — "AAA" < "Blue" < "Red"
            let sorted = [red, blue, custom].sorted()
            #expect(sorted[0].label == "AAA")
            #expect(sorted[1].label == "Blue")
            #expect(sorted[2].label == "Red")
        }

        @Test func tagDescriptionEquality() {
            let a = FinderTagDescription(tagColor: .red)
            let b = FinderTagDescription(tagColor: .red)
            let c = FinderTagDescription(label: "Red")

            #expect(a == b)
            // label-only init sets tagColor to .none, so it differs from a color tag
            #expect(a != c)
        }

        // MARK: - FinderTagGroup Codable

        @Test func encodeDecodeEmptyGroup() throws {
            let group = FinderTagGroup()
            let data = try JSONEncoder().encode(group)
            let decoded = try JSONDecoder().decode(FinderTagGroup.self, from: data)
            #expect(decoded.tags.isEmpty)
        }

        @Test func encodeDecodeGroupWithStandardTags() throws {
            let group = FinderTagGroup(tags: [
                FinderTagDescription(tagColor: .red),
                FinderTagDescription(tagColor: .blue),
                FinderTagDescription(tagColor: .green),
            ])
            let data = try JSONEncoder().encode(group)
            let decoded = try JSONDecoder().decode(FinderTagGroup.self, from: data)
            #expect(decoded.tags.count == 3)
            #expect(decoded.tags[0].tagColor == .red)
            #expect(decoded.tags[1].tagColor == .blue)
            #expect(decoded.tags[2].tagColor == .green)
        }

        @Test func encodeDecodeGroupWithTextTag() throws {
            let group = FinderTagGroup(tags: [
                FinderTagDescription(tagColor: .red),
                FinderTagDescription(label: "CustomText"),
            ])
            let data = try JSONEncoder().encode(group)
            let decoded = try JSONDecoder().decode(FinderTagGroup.self, from: data)
            #expect(decoded.tags.count == 2)
            #expect(decoded.tags[1].tagColor == .none)
            #expect(decoded.tags[1].label == "CustomText")
        }

        @Test func multipleRoundTripsPreserveTags() throws {
            var group = FinderTagGroup(tags: [
                FinderTagDescription(tagColor: .red),
                FinderTagDescription(label: "TextTag"),
            ])

            for _ in 0 ..< 10 {
                let data = try JSONEncoder().encode(group)
                group = try JSONDecoder().decode(FinderTagGroup.self, from: data)
            }

            #expect(group.tags.count == 2)
            #expect(group.tags[0].tagColor == .red)
            #expect(group.tags[1].label == "TextTag")
        }

        // MARK: - defaultTags

        @Test func defaultTagsContainsAllColors() {
            let defaults = FinderTagGroup.defaultTags
            #expect(defaults.tags.count == TagColor.allCases.count)

            for tagColor in TagColor.allCases {
                #expect(defaults.tags.contains(where: { $0.tagColor == tagColor }))
            }
        }

        // MARK: - stringValue

        @Test func stringValueEmptyGroup() {
            let group = FinderTagGroup()
            #expect(group.stringValue == "")
        }

        @Test func stringValueColorTagsOnly() {
            let group = FinderTagGroup(tags: [
                FinderTagDescription(tagColor: .red),
                FinderTagDescription(tagColor: .blue),
            ])
            #expect(group.stringValue == "Red, Blue")
        }

        @Test func stringValueIncludesTextTagLabel() {
            let group = FinderTagGroup(tags: [
                FinderTagDescription(tagColor: .red),
                FinderTagDescription(label: "Custom"),
            ])
            #expect(group.stringValue == "Red, Custom")
        }

        @Test func stringValueCustomTextTagOnly() {
            let group = FinderTagGroup(tags: [
                FinderTagDescription(label: "MyCustomTag"),
            ])
            #expect(group.stringValue == "MyCustomTag")
        }

        // MARK: - defaultColor

        @Test func defaultColorReturnsFirstColorTag() {
            let group = FinderTagGroup(tags: [
                FinderTagDescription(tagColor: .red),
                FinderTagDescription(tagColor: .blue),
            ])
            #expect(group.defaultColor != nil)
        }

        @Test func defaultColorNilForEmptyGroup() {
            let group = FinderTagGroup()
            #expect(group.defaultColor == nil)
        }

        @Test func defaultColorNilWhenOnlyTextTags() {
            let group = FinderTagGroup(tags: [
                FinderTagDescription(label: "TextOnly"),
            ])
            #expect(group.defaultColor == nil)
        }

        @Test func defaultColorSkipsNoneTagsReturnsFirstColor() {
            let group = FinderTagGroup(tags: [
                FinderTagDescription(label: "TextTag"),
                FinderTagDescription(tagColor: .blue),
            ])
            #expect(group.defaultColor != nil)
        }

        // MARK: - tagColors

        @Test func tagColorsExcludesNone() {
            let group = FinderTagGroup(tags: [
                FinderTagDescription(tagColor: .none),
                FinderTagDescription(tagColor: .red),
                FinderTagDescription(tagColor: .blue),
            ])
            #expect(group.tagColors == [.red, .blue])
        }

        @Test func tagColorsExcludesTextTags() {
            let group = FinderTagGroup(tags: [
                FinderTagDescription(tagColor: .red),
                FinderTagDescription(label: "CustomText"),
                FinderTagDescription(tagColor: .green),
            ])
            #expect(group.tagColors == [.red, .green])
        }

        @Test func tagColorsEmptyForEmptyGroup() {
            let group = FinderTagGroup()
            #expect(group.tagColors.isEmpty)
        }

        @Test func tagColorsEmptyWhenOnlyTextTags() {
            let group = FinderTagGroup(tags: [
                FinderTagDescription(label: "A"),
                FinderTagDescription(label: "B"),
            ])
            #expect(group.tagColors.isEmpty)
        }

        // MARK: - labels()

        @Test func labelsExcludesNoneTags() {
            let group = FinderTagGroup(tags: [
                FinderTagDescription(tagColor: .red),
                FinderTagDescription(tagColor: .blue),
                FinderTagDescription(label: "CustomText"),
            ])
            #expect(group.labels() == ["Red", "Blue"])
        }

        @Test func labelsEmptyWhenOnlyTextTags() {
            let group = FinderTagGroup(tags: [
                FinderTagDescription(label: "TextOnly"),
            ])
            #expect(group.labels().isEmpty)
        }

        @Test func labelsEmptyForEmptyGroup() {
            let group = FinderTagGroup()
            #expect(group.labels().isEmpty)
        }

        // MARK: - insert(colors:)

        @Test func insertColorsReplacesColorTagsPreservesTextTags() {
            var group = FinderTagGroup(tags: [
                FinderTagDescription(tagColor: .red),
                FinderTagDescription(label: "CustomText"),
            ])

            group.insert(colors: [
                FinderTagDescription(tagColor: .blue),
                FinderTagDescription(tagColor: .green),
            ])

            let colorTags = group.tags.filter { $0.tagColor != .none }
            let textTags = group.tags.filter { $0.tagColor == .none }

            #expect(colorTags.count == 2)
            #expect(colorTags.contains(where: { $0.tagColor == .blue }))
            #expect(colorTags.contains(where: { $0.tagColor == .green }))
            #expect(textTags.count == 1)
            #expect(textTags[0].label == "CustomText")
        }

        @Test func insertColorsFiltersNoneFromInput() {
            var group = FinderTagGroup()

            group.insert(colors: [
                FinderTagDescription(tagColor: .none),
                FinderTagDescription(tagColor: .red),
            ])

            let colorTags = group.tags.filter { $0.tagColor != .none }
            #expect(colorTags.count == 1)
            #expect(colorTags[0].tagColor == .red)
        }

        // MARK: - update(colors:)

        @Test func updateColorsReplacesColorTagsKeepsTextTags() {
            var group = FinderTagGroup(tags: [
                FinderTagDescription(tagColor: .red),
                FinderTagDescription(label: "MyTag"),
            ])

            group.update(colors: [
                FinderTagDescription(tagColor: .green),
                FinderTagDescription(tagColor: .yellow),
            ])

            let textTags = group.tags.filter { $0.tagColor == .none }
            let colorTags = group.tags.filter { $0.tagColor != .none }

            #expect(textTags.count == 1)
            #expect(textTags[0].label == "MyTag")
            #expect(colorTags.count == 2)
            #expect(colorTags.contains(where: { $0.tagColor == .green }))
            #expect(colorTags.contains(where: { $0.tagColor == .yellow }))
        }

        @Test func updateColorsRemovesOldColors() {
            var group = FinderTagGroup(tags: [
                FinderTagDescription(tagColor: .red),
                FinderTagDescription(tagColor: .blue),
            ])

            group.update(colors: [FinderTagDescription(tagColor: .orange)])

            #expect(group.tagColors == [.orange])
            #expect(!group.tags.contains(where: { $0.tagColor == .red }))
            #expect(!group.tags.contains(where: { $0.tagColor == .blue }))
        }
    }

#endif
