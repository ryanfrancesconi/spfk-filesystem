// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

#if os(macOS)
    import Foundation
    import SPFKBase

    /// What changed about a file, as far as its modification dates can tell.
    ///
    /// The distinction is not academic: on macOS, writing an extended attribute -- which is where
    /// Finder tags live -- bumps the attribute modification date and leaves the content
    /// modification date alone. Verified directly, 2026-08-05: setting
    /// `com.apple.metadata:_kMDItemUserTags` moved ctime and not mtime, while appending a byte
    /// moved both. So "the user tagged this file in Finder" and "the user re-exported this file
    /// from Photoshop" are the same event to anything that only compares one date, and they want
    /// very different responses -- re-reading a few extended attributes versus re-decoding EXIF,
    /// XMP and a video track.
    public enum FileModificationKind: Sendable, Hashable {
        /// The data stream was rewritten. Anything derived from the file's contents -- parsed
        /// metadata, thumbnails, waveforms -- is stale.
        case content

        /// Only file metadata changed: extended attributes (Finder tags), permissions, dates.
        /// The contents, and everything derived from them, are still valid.
        case attributes
    }

    /// A file's last-known modification dates, kept apart rather than collapsed to one value so a
    /// later comparison can say *which* changed. See ``FileModificationKind``.
    ///
    /// Both are optional because a file may not exist, or may sit on a volume that does not report
    /// them. A `nil` on either side makes classification impossible, and callers should treat that
    /// as ``FileModificationKind/content`` -- the conservative answer, since it only costs work.
    public struct FileModificationState: Hashable, Sendable {
        /// When the data stream was last written.
        public var contentModificationDate: Date?

        /// When any of the file's attributes were last modified -- extended attributes included.
        public var attributeModificationDate: Date?

        /// The more recent of the two, which is what "when did this file last change" means to a
        /// caller that does not care which kind of change it was.
        public var modificationDate: Date? {
            switch (contentModificationDate, attributeModificationDate) {
            case let (content?, attribute?): max(content, attribute)
            case let (content?, nil): content
            case let (nil, attribute?): attribute
            case (nil, nil): nil
            }
        }

        /// Whether either date is unknown, in which case a comparison cannot say what changed.
        public var isClassifiable: Bool {
            contentModificationDate != nil && attributeModificationDate != nil
        }

        public init(contentModificationDate: Date? = nil, attributeModificationDate: Date? = nil) {
            self.contentModificationDate = contentModificationDate
            self.attributeModificationDate = attributeModificationDate
        }

        /// Reads both dates from disk. Returns empty dates for a file that cannot be reached.
        ///
        /// One `resourceValues` call for both keys, not two: a catch-up scan builds one of these
        /// per element, so at album size the difference is tens of thousands of syscalls. The
        /// cached values are dropped first because `URL` memoizes them, and a stale read is the
        /// one thing this type must never do.
        public init(url: URL) {
            var uncached = url
            uncached.removeCachedResourceValue(forKey: .contentModificationDateKey)
            uncached.removeCachedResourceValue(forKey: .attributeModificationDateKey)

            let values = try? uncached.resourceValues(
                forKeys: [.contentModificationDateKey, .attributeModificationDateKey]
            )

            contentModificationDate = values?.contentModificationDate
            attributeModificationDate = values?.attributeModificationDate
        }

        /// Classifies the change from `self` to `other`, or `nil` when nothing moved.
        ///
        /// A content change wins over a simultaneous attribute change: re-reading the file covers
        /// both, whereas refreshing attributes alone would leave stale parsed data behind.
        ///
        /// **A date is a change only when it moves forward.** A write advances it, so a disk date
        /// *older* than what was recorded cannot be an edit that happened after we looked -- and
        /// answering it with ``FileModificationKind/content`` reparses a file nobody touched.
        /// Measured 2026-08-14 on five files whose sizes were byte-identical: four sat 965 s behind
        /// their recorded date, one 23 µs behind.
        ///
        /// Strictly forward, with no tolerance around it. A window wide enough to cover that 23 µs
        /// also swallows a real write: writing a file and re-reading it takes well under a
        /// millisecond, which three of this file's own tests demonstrate.
        ///
        /// The trade is a rewrite that lands an *older* date than the last one seen -- a restore
        /// from backup with dates preserved -- which goes unreported. A date comparison cannot
        /// catch that in either direction.
        public func change(to other: FileModificationState) -> FileModificationKind? {
            guard isClassifiable else {
                return collapsedChange(to: other)
            }

            guard other.isClassifiable else {
                return Self.advanced(from: modificationDate, to: other.modificationDate) ? .content : nil
            }

            if Self.advanced(from: contentModificationDate, to: other.contentModificationDate) {
                return .content
            }

            if Self.advanced(from: attributeModificationDate, to: other.attributeModificationDate) {
                return .attributes
            }

            return nil
        }

        /// Whether `later` is after `earlier`. Unknown dates cannot be compared, and report no
        /// movement rather than guessing at one.
        private static func advanced(from earlier: Date?, to later: Date?) -> Bool {
            guard let earlier, let later else { return false }

            return later > earlier
        }

        /// Classifies against a record carrying only the collapsed date -- data written before the
        /// split, seeded into ``contentModificationDate`` with no attribute side.
        ///
        /// The collapsed value is `max(content, attribute)`, so it is an **upper bound** on the
        /// content date at the time it was recorded: a content date that is no newer than it
        /// cannot have advanced since, and the difference can only be attributes. Measured
        /// 2026-08-13: copying a file sets its attribute date 18-37 µs after its content date, so
        /// the collapsed value of any copied file is its attribute date, and answering every later
        /// difference with ``FileModificationKind/content`` reported a full rewrite for every one
        /// of them the first time anything touched an extended attribute.
        ///
        /// The trade is a content rewrite that lands a modification date *older* than what was
        /// recorded -- a restore from backup with dates preserved -- which reads as attributes
        /// only. Nothing in a date comparison can catch that case either way.
        private func collapsedChange(to other: FileModificationState) -> FileModificationKind? {
            guard let recorded = modificationDate,
                  let current = other.modificationDate,
                  Self.advanced(from: recorded, to: current)
            else {
                return nil
            }

            guard let currentContent = other.contentModificationDate else { return .content }

            return Self.advanced(from: recorded, to: currentContent) ? .content : .attributes
        }
    }
#endif
