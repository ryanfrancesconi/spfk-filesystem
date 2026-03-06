// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation

// swiftformat:disable consecutiveSpaces

/// For file size and disk space checks
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
