// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation

// swiftformat:disable consecutiveSpaces

/// Binary byte size constants for file size and disk space calculations.
///
/// **Available on all Apple platforms** (macOS, iOS, tvOS, watchOS).
///
/// Raw values represent the exact number of bytes for each unit (powers of 1024).
/// Used by ``FileSystem/byteCountToString(_:)`` and ``FileSystem/stringToByteCount(_:)``
/// for human-readable file size formatting.
public enum ByteCount: UInt64 {
    case byte     = 1
    case kilobyte = 1024
    case megabyte = 1048576
    case gigabyte = 1073741824
    case terabyte = 1099511627776
    case petabyte = 1125899906842624
    case exabyte  = 1152921504606846976
}

// swiftformat:enable consecutiveSpaces
