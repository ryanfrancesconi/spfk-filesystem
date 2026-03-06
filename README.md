# SPFKFileSystem

Cross-platform file system utilities for Apple platforms — directory enumeration, recursive directory observation, byte count formatting, extended attributes, and macOS Finder tag management.

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
| `ByteCount` | Y | Y |
| `DirectoryObserver` | Y | Y |
| `DirectoryEnumerationObserver` | Y | Y |
| `DirectoryEvent` | Y | Y |
| `URL` xattr extensions | Y | Y |
| `FSEventsDirectoryObserver` | Y | — |
| `SecureURLRegistry` | Y | — |
| `TagColor` | Y | — |
| `FinderTagDescription` | Y | — |
| `FinderTagGroup` | Y | — |
| `URL` Finder tag extensions | Y | — |

## Directory Observation

Two strategies for monitoring a directory tree for file additions and deletions. Both produce `DirectoryEvent` values (`.new` / `.removed`) delivered through `DirectoryEnumerationObserverDelegate`.

### kqueue (cross-platform)

`DirectoryEnumerationObserver` creates one `DirectoryObserver` per subdirectory, each backed by a file descriptor and `DispatchSource`. Works on all Apple platforms but consumes one file descriptor per monitored subdirectory.

```swift
let observer = try DirectoryEnumerationObserver(url: directoryURL, delegate: self)
try await observer.start()
// ...
await observer.stop()
```

### FSEvents (macOS only)

`FSEventsDirectoryObserver` uses a single CoreServices `FSEventStream` to monitor an entire directory tree recursively. More efficient for large hierarchies — no per-directory file descriptors.

```swift
let observer = try FSEventsDirectoryObserver(url: directoryURL, delegate: self)
await observer.start()
// ...
await observer.stop()
```

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

- **Byte formatting** — `byteCountToString(_:)`, `stringToByteCount(_:)`
- **Disk space** — `getSystemFreeSizeInBytes(forPath:)`, `getSystemSizeInBytes(forPath:)`
- **Volumes** — `getMountedVolumes()`, `volumeURL(forFileURL:)`
- **Directory enumeration** — `getFileURLs(in:...)`, `getDirectories(in:...)`, `getPackages(in:...)`
- **Path utilities** — `nextAvailableURL(_:)`, `getQueryStringParameter(url:param:)`
- **Cleanup** — `deleteEmptyDirectories(in:)`

## Finder Tags (macOS)

Read and write macOS Finder color labels and custom text tags via extended attributes.

```swift
// Read tags
let tagColors = fileURL.tagColors       // [TagColor]
let tagNames = fileURL.tagNames         // [String]
let tags = fileURL.finderTags           // [FinderTagDescription]

// Write tags
try fileURL.set(tagColors: [.red, .blue])
try fileURL.set(finderTags: tagGroup)
try fileURL.removeAllTags()
```

`TagColor` represents the 7 built-in Finder label colors (gray, green, purple, blue, yellow, red, orange) plus `.none`. `FinderTagDescription` pairs a color with a label string and also supports custom text-only tags. `FinderTagGroup` collects multiple tag descriptions for batch operations.

## Security-Scoped Bookmarks (macOS)

`SecureURLRegistry` manages `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()` lifecycle for sandboxed apps. Duplicate access calls for the same URL are automatically deduplicated to prevent unbalanced reference counts.

```swift
let registry = SecureURLRegistry()
let (url, isStale) = try await registry.create(resolvingBookmarkData: bookmarkData)
// ... use url ...
await registry.release(url: url)    // release individual URL when done
await registry.releaseAll()         // or release all on app shutdown
```

## Dependencies

- [spfk-base](https://github.com/ryanfrancesconi/spfk-base) — logging and base utilities
- [swift-extensions](https://github.com/orchetect/swift-extensions) — Swift standard library extensions
- [swift-xattr](https://github.com/jozefizso/swift-xattr) — extended attribute read/write

## License

Copyright Ryan Francesconi. All Rights Reserved.

## About

Spongefork (SPFK) is the personal software projects of [Ryan Francesconi](https://github.com/ryanfrancesconi). Dedicated to creative sound manipulation, his first application, Spongefork, was released in 1999 for macOS 8. From 2016 to 2025 he was the lead macOS developer at [Audio Design Desk](https://add.app).

