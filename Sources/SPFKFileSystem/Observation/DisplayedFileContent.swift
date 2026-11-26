// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

#if os(macOS)
    import Foundation

    /// Which file's contents the editor is currently showing.
    ///
    /// An element load rebuilds every sub-system it drives, and some of those rebuilds are expensive
    /// enough to be worth skipping when nothing about the file changed - a filmstrip costs a duration
    /// probe and a frame-store lookup per thumbnail before anything reaches the screen.
    ///
    /// Derived from the file rather than declared by the caller: a track switch, a metadata edit and a
    /// reparse all reach an element load and none of them can be relied on to describe themselves.
    public struct DisplayedFileContent: Hashable, Sendable {
        public let url: URL
        public let modificationState: FileModificationState

        public init(url: URL, modificationState: FileModificationState) {
            self.url = url
            self.modificationState = modificationState
        }

        /// Reads the file's current modification state. One `resourceValues` call.
        public init(url: URL) {
            self.init(url: url, modificationState: FileModificationState(url: url))
        }

        /// Whether `other` is the same file with the same contents.
        ///
        /// An attribute-only change - a Finder tag, a permission - leaves everything derived from the
        /// contents valid, so it counts as unchanged. An unclassifiable comparison reports changed,
        /// which only ever costs work.
        public func showsSameContent(as other: DisplayedFileContent) -> Bool {
            url == other.url && modificationState.change(to: other.modificationState) != .content
        }
    }

    extension DisplayedFileContent? {
        /// Whether the editor is already showing `other`'s contents. Nothing displayed is never a match.
        public func showsSameContent(as other: DisplayedFileContent) -> Bool {
            self?.showsSameContent(as: other) ?? false
        }
    }
#endif
