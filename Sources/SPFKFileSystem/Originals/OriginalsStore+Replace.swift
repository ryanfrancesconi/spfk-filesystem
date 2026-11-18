// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation
import SPFKBase

extension OriginalsStore {
    /// Puts a finished render in place of `url`, keeping `url`'s original first when `originals` is set.
    ///
    /// The order is the point: keep, swap, note. A swap that fails discards what this keep made. A
    /// failed note is logged, since the render is already in place. The render is left where it is
    /// on a failure, for the caller to remove.
    public static func replace(
        _ url: URL,
        with rendered: URL,
        kinds: [String],
        keeping originals: OriginalsStore?
    ) throws {
        let kept = try originals?.keep(url)

        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: rendered)
        } catch {
            if let kept { originals?.discard(kept, unmarking: url) }
            throw error
        }

        do {
            try originals?.noteRender(of: url, kinds: kinds)
        } catch {
            Log.error("The render of \(url.lastPathComponent) could not be noted beside its original", error)
        }
    }
}
