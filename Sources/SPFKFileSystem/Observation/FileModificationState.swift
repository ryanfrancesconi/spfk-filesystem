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
        public init(url: URL) {
            var uncached = url
            uncached.removeCachedResourceValue(forKey: .contentModificationDateKey)
            uncached.removeCachedResourceValue(forKey: .attributeModificationDateKey)

            contentModificationDate = uncached.contentModificationDate
            attributeModificationDate = uncached.attributeModificationDate
        }

        /// Classifies the change from `self` to `other`, or `nil` when nothing moved.
        ///
        /// A content change wins over a simultaneous attribute change: re-reading the file covers
        /// both, whereas refreshing attributes alone would leave stale parsed data behind. When
        /// either state can't be classified, any difference reports as
        /// ``FileModificationKind/content`` for the same reason.
        public func change(to other: FileModificationState) -> FileModificationKind? {
            guard isClassifiable, other.isClassifiable else {
                return modificationDate == other.modificationDate ? nil : .content
            }

            if contentModificationDate != other.contentModificationDate {
                return .content
            }

            if attributeModificationDate != other.attributeModificationDate {
                return .attributes
            }

            return nil
        }
    }
#endif
