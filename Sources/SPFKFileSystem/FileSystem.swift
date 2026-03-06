// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation

/// Collection of static file system utility methods for directory enumeration, file discovery,
/// byte count formatting, and volume queries.
///
/// **Available on all Apple platforms** (macOS, iOS, tvOS, watchOS).
///
/// Methods are organized into focused extensions:
/// - ``byteCountToString(_:)`` / ``stringToByteCount(_:)`` — byte count formatting
/// - ``getMountedVolumes()`` / ``volumeURL(forFileURL:)`` — volume queries
/// - ``getFileURLs(in:)-6p0n5`` / ``getDirectories(in:recursive:skipHidden:)`` — file enumeration
/// - ``deleteEmptyDirectories(in:)`` — cleanup
/// - ``fileURLStream(in:)`` — async streaming enumeration
///
/// On macOS, additional methods for security-scoped file access and Finder tag management
/// are available in ``SecureURLRegistry`` and the Tags extensions (``URL/tagNames``,
/// ``TagColor``, ``FinderTagGroup``). An AppKit-dependent extension with `getAuthorizedFileURLs`
/// and `requestDirectory` lives in `spfk-utils` as `FileSystem+AppKit.swift`.
public enum FileSystem {}
