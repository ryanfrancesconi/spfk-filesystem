// Copyright Ryan Francesconi. All Rights Reserved.

#if os(macOS)
    import Foundation
    import SPFKBase
    import Testing

    @testable import SPFKFileSystem

    /// The rule that decides whether an element load can reuse what is on screen. Every case here is a
    /// caller of an element load.
    @Suite
    struct DisplayedFileContentTests {
        private let url = URL(fileURLWithPath: "/tmp/a.mov")
        private let other = URL(fileURLWithPath: "/tmp/b.mov")

        private func content(
            url: URL,
            content contentDate: TimeInterval,
            attributes attributeDate: TimeInterval
        ) -> DisplayedFileContent {
            DisplayedFileContent(
                url: url,
                modificationState: FileModificationState(
                    contentModificationDate: Date(timeIntervalSince1970: contentDate),
                    attributeModificationDate: Date(timeIntervalSince1970: attributeDate)
                )
            )
        }

        /// An audio track switch: the element changed, the file did not.
        @Test func sameFileUnchangedReusesWhatIsOnScreen() {
            let displayed = content(url: url, content: 100, attributes: 100)
            #expect(displayed.showsSameContent(as: content(url: url, content: 100, attributes: 100)))
        }

        /// A Finder tag written externally moves only the attribute date, and nothing derived from the
        /// file's contents is stale.
        @Test func attributeOnlyChangeReusesWhatIsOnScreen() {
            let displayed = content(url: url, content: 100, attributes: 100)
            #expect(displayed.showsSameContent(as: content(url: url, content: 100, attributes: 200)))
        }

        /// A save or a render rewrites the data stream.
        @Test func contentChangeRebuilds() {
            let displayed = content(url: url, content: 100, attributes: 100)
            #expect(!displayed.showsSameContent(as: content(url: url, content: 200, attributes: 200)))
        }

        @Test func differentFileRebuilds() {
            let displayed = content(url: url, content: 100, attributes: 100)
            #expect(!displayed.showsSameContent(as: content(url: other, content: 100, attributes: 100)))
        }

        /// Nothing displayed is never a match, which is what makes clearing the editor a reliable way
        /// to force the next load to rebuild.
        @Test func nothingDisplayedRebuilds() {
            let displayed: DisplayedFileContent? = nil
            #expect(!displayed.showsSameContent(as: content(url: url, content: 100, attributes: 100)))
        }

        /// A volume that reports no dates cannot classify, and the conservative answer only costs work.
        @Test func unclassifiableStateRebuilds() {
            let displayed = DisplayedFileContent(url: url, modificationState: FileModificationState())
            let incoming = DisplayedFileContent(
                url: url,
                modificationState: FileModificationState(contentModificationDate: Date(timeIntervalSince1970: 100))
            )

            #expect(!displayed.showsSameContent(as: incoming))
        }
    }
#endif
