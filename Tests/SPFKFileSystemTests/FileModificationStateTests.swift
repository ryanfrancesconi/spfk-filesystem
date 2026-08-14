// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

#if os(macOS)
    import Foundation
    import SPFKBase
    @testable import SPFKFileSystem
    import SPFKTesting
    import Testing

    @Suite
    class FileModificationStateTests: BinTestCase {
        /// A fresh file per test, named after the caller so tags set by one test can't leak into
        /// another through a reused path.
        private func createFile(named name: String) throws -> URL {
            let url = bin.appendingPathComponent("\(name).txt")
            try? url.delete()
            try Data("initial".utf8).write(to: url)
            return url
        }

        // MARK: - Real file system behavior

        /// Writes Finder tags the way an external process does: a binary plist array in the
        /// `_kMDItemUserTags` xattr via a bare `setxattr`, with no modification-date bump. That
        /// last part is the difference from `URL.set(tagNames:)` and the whole point here.
        private func setTagsExternally(on url: URL, to tagNames: [String]) throws {
            let data = try PropertyListSerialization.data(
                fromPropertyList: tagNames,
                format: .binary,
                options: 0
            )
            let result = data.withUnsafeBytes { buffer in
                setxattr(url.path, "com.apple.metadata:_kMDItemUserTags", buffer.baseAddress, buffer.count, 0, 0)
            }
            #expect(result == 0)

            // Guard the guard: if the write format were wrong, the date would still move and the
            // classification test would pass while testing nothing about Finder tags.
            #expect(url.tagNames == tagNames)
        }

        /// The whole reason this type exists. An external Finder tag edit writes an extended
        /// attribute, which moves the attribute modification date and leaves the content
        /// modification date alone -- so a file the user merely tagged must not be reported as
        /// needing its contents re-read. If this ever fails, the classification is unsafe and
        /// every consumer is doing the wrong amount of work.
        @Test func anExternalTagWriteReportsAnAttributeChangeNotAContentChange() throws {
            deleteBinOnExit = true
            let url = try createFile(named: #function)

            let before = FileModificationState(url: url)

            try setTagsExternally(on: url, to: [TagColor.red.dataElement])

            let after = FileModificationState(url: url)

            #expect(before.change(to: after) == .attributes)
            #expect(before.contentModificationDate == after.contentModificationDate)
        }

        /// This app's *own* tag writes go through `setExtendedAttributeAndModify`, which bumps the
        /// content modification date on purpose so Spotlight and other watchers notice. They
        /// therefore classify as `.content`, unlike the external write above.
        ///
        /// Pinned deliberately: the asymmetry looks like a bug from either side alone, and the
        /// resolution is not to make them agree. Our own writes are suppressed at the observer
        /// while a save is in flight, so the coarser classification costs nothing -- whereas
        /// dropping the bump would cost the Spotlight behavior it exists for.
        @Test func thisAppsOwnTagWriteAlsoMovesTheContentDate() throws {
            deleteBinOnExit = true
            let url = try createFile(named: #function)

            let before = FileModificationState(url: url)

            try url.set(tagColors: [.red])

            #expect(before.change(to: FileModificationState(url: url)) == .content)
        }

        /// The other half: rewriting the data stream moves both dates (a write touches the inode
        /// too), and the classification must come back as content rather than being confused by
        /// the attribute date moving alongside it.
        @Test func rewritingAFileReportsAContentChange() throws {
            deleteBinOnExit = true
            let url = try createFile(named: #function)

            let before = FileModificationState(url: url)

            try Data("rewritten with different length".utf8).write(to: url)

            let after = FileModificationState(url: url)

            #expect(before.change(to: after) == .content)
        }

        /// Rewriting a file in place with the *same* length still reports. A modification date
        /// records when the data stream was written, not whether the bytes ended up different --
        /// so an edit that leaves size and duration alone, like a fade rendered in place, moves it
        /// like any other write.
        @Test func aSameLengthRewriteReportsAContentChange() throws {
            deleteBinOnExit = true
            let url = try createFile(named: #function)

            let before = FileModificationState(url: url)
            let originalSize = url.fileSize

            try Data("INITIAL".utf8).write(to: url)

            let after = FileModificationState(url: url)

            #expect(url.fileSize == originalSize)
            #expect(before.change(to: after) == .content)
        }

        @Test func anUntouchedFileReportsNoChange() throws {
            deleteBinOnExit = true
            let url = try createFile(named: #function)

            #expect(FileModificationState(url: url).change(to: FileModificationState(url: url)) == nil)
        }

        // MARK: - Classification rules

        /// Content wins when both moved: re-reading the file covers the attributes too, whereas
        /// refreshing attributes alone would leave stale parsed data behind.
        @Test func aSimultaneousChangeToBothIsReportedAsContent() {
            let early = Date(timeIntervalSince1970: 1_000)
            let late = Date(timeIntervalSince1970: 2_000)

            let before = FileModificationState(contentModificationDate: early, attributeModificationDate: early)
            let after = FileModificationState(contentModificationDate: late, attributeModificationDate: late)

            #expect(before.change(to: after) == .content)
        }

        /// A missing date makes classification impossible, and the safe answer is the expensive
        /// one -- reporting `.attributes` on a guess would silently skip a real content change.
        @Test func anUnclassifiableStateFallsBackToContent() {
            let early = Date(timeIntervalSince1970: 1_000)
            let late = Date(timeIntervalSince1970: 2_000)

            let unknown = FileModificationState(contentModificationDate: nil, attributeModificationDate: early)
            let known = FileModificationState(contentModificationDate: late, attributeModificationDate: late)

            #expect(!unknown.isClassifiable)
            #expect(unknown.change(to: known) == .content)

            // ...but an unclassifiable state that still compares equal is not a change at all,
            // or every event would report every file.
            #expect(unknown.change(to: unknown) == nil)
        }

        /// A write moves a date forward, so a disk date *older* than the recorded one cannot be an
        /// edit that happened after we looked. Measured 2026-08-14 on four files whose sizes were
        /// byte-identical and whose disk dates sat 965 s behind what was recorded -- every one of
        /// them reported as a rewrite.
        @Test func aDateThatMovedBackwardsIsNotAChange() {
            let recorded = FileModificationState(
                contentModificationDate: Date(timeIntervalSinceReferenceDate: 804_543_992.017),
                attributeModificationDate: Date(timeIntervalSinceReferenceDate: 804_543_992.017)
            )

            // The same file, 965 s earlier on disk, and a much later attribute touch.
            let current = FileModificationState(
                contentModificationDate: Date(timeIntervalSinceReferenceDate: 804_543_026.477),
                attributeModificationDate: Date(timeIntervalSinceReferenceDate: 806_191_765.392)
            )

            #expect(recorded.change(to: current) == .attributes)
        }

        /// The same rule at the other end of the scale. Measured 2026-08-14 on two volumes:
        /// recorded dates landed 18.8 µs and 23 µs *later* than the same files' dates read back
        /// from disk, which reported a rewrite on every comparison thereafter.
        @Test func aMicrosecondBackwardsDifferenceIsNotAChange() {
            let recorded = FileModificationState(
                contentModificationDate: Date(timeIntervalSinceReferenceDate: 805_388_173.1507955),
                attributeModificationDate: Date(timeIntervalSinceReferenceDate: 805_388_173.1507955)
            )

            let current = FileModificationState(
                contentModificationDate: Date(timeIntervalSinceReferenceDate: 805_388_173.1507725),
                attributeModificationDate: Date(timeIntervalSinceReferenceDate: 805_388_173.1507725)
            )

            #expect(recorded.change(to: current) == nil)
        }

        /// The direction rule must not become a tolerance: a write that lands microseconds later
        /// is still a write. Back-to-back file operations are well under a millisecond apart, so a
        /// window wide enough to absorb the artifact above would hide real ones.
        @Test func aMicrosecondForwardDifferenceIsAChange() {
            let recorded = FileModificationState(
                contentModificationDate: Date(timeIntervalSinceReferenceDate: 805_388_173.1507725),
                attributeModificationDate: Date(timeIntervalSinceReferenceDate: 805_388_173.1507725)
            )

            let current = FileModificationState(
                contentModificationDate: Date(timeIntervalSinceReferenceDate: 805_388_173.1507955),
                attributeModificationDate: Date(timeIntervalSinceReferenceDate: 805_388_173.1507955)
            )

            #expect(recorded.change(to: current) == .content)
        }

        /// A record written before the split carries `max(content, attribute)` in the content
        /// slot. On a copied file that is the *attribute* date -- measured on
        /// `airplane_flyby.wav`, whose content date is `.009266` and whose recorded collapsed
        /// value was `.0092849`, 18.8 µs later. A later Finder tag write must not turn that
        /// 18.8 µs into a reported rewrite of the whole file.
        @Test func aCollapsedRecordReadsALaterAttributeWriteAsAttributes() {
            let content = Date(timeIntervalSinceReferenceDate: 787_971_844.009266)
            let collapsed = Date(timeIntervalSinceReferenceDate: 787_971_844.0092849)
            let tagged = Date(timeIntervalSinceReferenceDate: 806_968_617.7240558)

            let recorded = FileModificationState(contentModificationDate: collapsed, attributeModificationDate: nil)
            let current = FileModificationState(contentModificationDate: content, attributeModificationDate: tagged)

            #expect(!recorded.isClassifiable)
            #expect(recorded.change(to: current) == .attributes)
        }

        /// The bound only holds downward: a content date *newer* than the collapsed value is a
        /// rewrite that happened after the record was written, and still has to reparse.
        @Test func aCollapsedRecordStillReportsARealRewrite() {
            let collapsed = Date(timeIntervalSince1970: 1_000)
            let rewritten = Date(timeIntervalSince1970: 2_000)

            let recorded = FileModificationState(contentModificationDate: collapsed, attributeModificationDate: nil)
            let current = FileModificationState(
                contentModificationDate: rewritten,
                attributeModificationDate: rewritten
            )

            #expect(recorded.change(to: current) == .content)
        }

        /// A file whose two dates were equal when collapsed, and which nothing has touched since.
        @Test func aCollapsedRecordMatchingDiskIsNotAChange() {
            let date = Date(timeIntervalSince1970: 1_000)

            let recorded = FileModificationState(contentModificationDate: date, attributeModificationDate: nil)
            let current = FileModificationState(contentModificationDate: date, attributeModificationDate: date)

            #expect(recorded.change(to: current) == nil)
        }

        /// `modificationDate` is what callers that don't care about the split read, and it has to
        /// stay the later of the two -- it replaced a stored property with exactly that meaning.
        @Test func modificationDateIsTheLaterOfTheTwo() {
            let early = Date(timeIntervalSince1970: 1_000)
            let late = Date(timeIntervalSince1970: 2_000)

            #expect(
                FileModificationState(contentModificationDate: early, attributeModificationDate: late)
                    .modificationDate == late
            )
            #expect(
                FileModificationState(contentModificationDate: late, attributeModificationDate: early)
                    .modificationDate == late
            )
            #expect(FileModificationState().modificationDate == nil)
        }
    }
#endif
