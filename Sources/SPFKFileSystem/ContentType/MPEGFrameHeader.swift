// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation

/// An MPEG audio or ADTS frame header that TagLib's `MPEG::Header` would accept: a frame sync,
/// and no reserved version, layer, bitrate or sample-rate value.
struct MPEGFrameHeader {
    /// 1, 2 or 3; 0 for ADTS.
    let layer: Int

    var isADTS: Bool { layer == 0 }

    init?(_ bytes: [UInt8]) {
        guard bytes.count >= 4, bytes[0] == 0xFF, bytes[1] != 0xFF, bytes[1] & 0xE0 == 0xE0 else { return nil }

        let versionBits = (bytes[1] >> 3) & 0x03
        guard versionBits != 1 else { return nil }

        switch (bytes[1] >> 1) & 0x03 {
        case 1: layer = 3
        case 2: layer = 2
        case 3: layer = 1
        default:
            // Layer bits 00 with the version's high bit set are ADTS.
            guard versionBits & 0x02 != 0 else { return nil }
            layer = 0
        }

        if isADTS {
            guard (bytes[2] >> 2) & 0x0F < 13 else { return nil }
        } else {
            let bitrateIndex = (bytes[2] >> 4) & 0x0F
            guard bitrateIndex != 0, bitrateIndex != 15, (bytes[2] >> 2) & 0x03 != 3 else { return nil }
        }
    }
}
