# SPFKFileSystem

[![Version](https://img.shields.io/github/v/tag/ryanfrancesconi/spfk-filesystem)](https://github.com/ryanfrancesconi/spfk-filesystem/tags)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-filesystem%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/ryanfrancesconi/spfk-filesystem)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-filesystem%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/ryanfrancesconi/spfk-filesystem)

Cross-platform file system utilities for Apple platforms — directory enumeration, recursive directory observation, extended attributes, and macOS Finder tag management.

## Requirements

- **Platforms:** macOS 13+, iOS 16+
- **Swift:** 6.2+

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/ryanfrancesconi/spfk-filesystem", from: "0.0.1"),
]
```

Then add `SPFKFileSystem` to your target's dependencies:

```swift
.target(
    name: "MyTarget",
    dependencies: [
        .product(name: "SPFKFileSystem", package: "spfk-filesystem"),
    ]
)
```

## Platform Availability

| Type / Extension | macOS | iOS |
|---|:---:|:---:|
| `FileSystem` | Y | Y |
| `DirectoryObserver` | Y | Y |
| `DirectoryEnumerationObserver` | Y | Y |
| `DirectoryEvent` | Y | Y |
| `URL` xattr extensions | Y | Y |
| `FileModificationObserver` | Y | Y |
| `FileCommands` | Y | Y |
| `TrashReceipt` | Y | Y |
| `FSEventsDirectoryObserver` | Y | — |
| `VolumeObserver` | Y | — |
| `FileLockState` | Y | — |
| `TagColor` | Y | — |
| `FinderTagDescription` | Y | — |
| `FinderTagGroup` | Y | — |
| `URL` Finder tag extensions | Y | — |

## Directory Observation

Two strategies for monitoring a directory tree for file additions and deletions. Both produce `DirectoryEvent` values (`.new` / `.removed`) delivered through `DirectoryEnumerationObserverDelegate`.

### kqueue (cross-platform)

`DirectoryEnumerationObserver` creates one `DirectoryObserver` per subdirectory, each backed by a file descriptor and `DispatchSource`. Works on all Apple platforms but consumes one file descriptor per monitored subdirectory.

### FSEvents (macOS only)

`FSEventsDirectoryObserver` uses a single CoreServices `FSEventStream` to monitor an entire directory tree recursively. More efficient for large hierarchies — no per-directory file descriptors.

| | `DirectoryEnumerationObserver` | `FSEventsDirectoryObserver` |
|---|---|---|
| Platform | All Apple platforms | macOS only |
| Underlying API | kqueue (`DispatchSource`) | CoreServices `FSEventStream` |
| Resources | 1 file descriptor per subdirectory | 1 stream total |
| Recursive | Via `ObservationData` coordination | Built-in |
| `start()` | `async throws` | Non-throwing |
| Event source URL | Per-subdirectory | Root URL only |

## File System Utilities

`FileSystem` provides static methods for common operations:

- **Disk space** — `freeSpace(forPath:)`, `totalSpace(forPath:)`, `freeSpaceDescription(forPath:)`, `totalSpaceDescription(forPath:)`
- **Volumes** — `mountedVolumes()`, `volumeURL(forFileURL:)`
- **File enumeration** — `enumerateFiles(in:...)`, `enumerateDirectories(in:...)`, `enumeratePackages(in:...)`
- **Search** — `findDirectory(named:in:)`
- **Streaming** — `fileURLStream(in:)`
- **Path utilities** — `nextAvailableURL(_:)`
- **Cleanup** — `deleteEmptyDirectories(in:)`

## Finder Tags (macOS)

Read and write macOS Finder color labels and custom text tags via extended attributes.

`TagColor` represents the 7 built-in Finder label colors (gray, green, purple, blue, yellow, red, orange) plus `.none`. `FinderTagDescription` pairs a color with a label string and also supports custom text-only tags. `FinderTagGroup` collects multiple tag descriptions for batch operations.

## Security-scoped access (macOS)

`URL.withSecurityScopedAccess` scopes access to the duration of a body, in sync and async forms —
for short-lived work such as reading tags, parsing a waveform or analyzing a file. Longer-lived
access, such as streaming a file for playback, calls `startAccessingSecurityScopedResource()` and
its counterpart directly.

The body runs even when `startAccessingSecurityScopedResource()` returns `false`: the file may be
reachable through the powerbox — a current-session open-panel selection — or be a local path
needing no sandbox extension at all. The async form runs on the caller's actor rather than hopping
off it, so a body touching isolated state stays legal.

## File modification

`FileModificationObserver` watches a set of tracked files and reports what changed, classified by
`FileModificationKind` as content or attributes-only.

**The distinction is not academic.** On macOS, writing an extended attribute — which is where Finder
tags live — bumps the attribute modification date and leaves the content modification date alone.
Verified directly: setting the user-tags attribute moved ctime and not mtime, while appending a byte
moved both. So "the user tagged this file in Finder" and "the user re-exported this file from
Photoshop" are the same event to anything comparing one date, and they want very different
responses — re-reading a few extended attributes versus re-decoding EXIF, XMP and a video track.
`FileModificationState` keeps the dates apart rather than collapsing them, so a later comparison can
say which moved.

`VolumeObserver` reports volumes mounting and unmounting.

## File commands

`FileCommands` covers rename, duplicate, move to trash, restore from trash and delete.

Two error conventions, split by arity. The single-URL `rename` throws, because there is one outcome
and the caller must react to it. The batch calls report per file so one bad file does not cost the
caller the other nine — duplicate and move-to-trash hand back whatever succeeded and throw only when
nothing did, while restore and delete return a map naming just the failures.

`TrashReceipt` carries where a trashed set currently sits, keyed by where it came from. Mutable
because the location is only stable until the name collides: a file re-trashed while one of the same
name is already in the Trash gets a timestamp appended, so an undo engine that registers the inverse
before running the handler has no other channel to learn where the files actually went.

`FileLockState` answers why a file refuses a write, or that it does not. Not a `Bool`, because
`isWritable` cannot say *why*: a file the owner made read-only and a file carrying the `uchg` flag
both report `false`, and only the second is something an app can offer to clear.

## Dependencies

- [spfk-base](https://github.com/ryanfrancesconi/spfk-base) — logging and base utilities
- [swift-extensions](https://github.com/orchetect/swift-extensions) — Swift standard library extensions
- [swift-xattr](https://github.com/jozefizso/swift-xattr) — extended attribute read/write

## License

Copyright Ryan Francesconi. All Rights Reserved.

## About

Spongefork is the personal software projects of musician and developer [Ryan Francesconi](https://spongefork.com). Dedicated to creative sound manipulation, his first application, Spongefork, was released in 1999 for macOS 8. From 2026, Spongefork returns as his software container for more musical experimentation. In addition to [software releases](https://spongefork.com/shadowtag/), open source components can be found on his [GitHub page](https://github.com/ryanfrancesconi).
