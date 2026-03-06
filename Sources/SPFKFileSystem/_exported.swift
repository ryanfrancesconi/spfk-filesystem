// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

/// SPFKFileSystem provides cross-platform file system utilities for Apple platforms (macOS, iOS),
/// including directory enumeration, file observation, byte count helpers, and Finder tag support.
///
/// ## Platform Availability
///
/// - **Cross-platform** (macOS + iOS): ``FileSystem``, ``ByteCount``, ``DirectoryObserver``,
///   ``DirectoryEnumerationObserver``, ``DirectoryEvent``, URL extended attributes.
/// - **macOS only**: ``FSEventsDirectoryObserver`` (CoreServices FSEvents API),
///   ``SecureURLRegistry`` (security-scoped bookmarks), Finder tags
///   (``TagColor``, ``FinderTagDescription``, ``FinderTagGroup``, ``URL`` tag extensions).
///
/// ## Directory Observation
///
/// Two observation strategies are available:
///
/// - **kqueue** (cross-platform): ``DirectoryObserver`` monitors a single directory using a
///   file descriptor and `DispatchSource`. For recursive monitoring, use
///   ``DirectoryEnumerationObserver`` which manages one ``DirectoryObserver`` per subdirectory
///   via ``ObservationData``. Available on all Apple platforms.
///
/// - **FSEvents** (macOS only): ``FSEventsDirectoryObserver`` monitors an entire directory
///   tree with a single `FSEventStream`. More efficient for large hierarchies — no per-directory
///   file descriptors. Preferred on macOS.
///
/// Both strategies produce ``DirectoryEvent`` values (`.new` / `.removed`) and deliver them
/// through ``DirectoryEnumerationObserverDelegate``.

@_exported import SPFKBase
