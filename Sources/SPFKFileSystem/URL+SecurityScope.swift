// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation

extension URL {
    /// Temporarily activates security-scoped access for `self` for the duration of `body`,
    /// then stops access via `defer` before returning.
    ///
    /// Use this for short-lived I/O operations such as reading or writing metadata,
    /// parsing waveforms, or running analysis on a single file. For longer-lived access
    /// (e.g. audio playback where the file is streamed), use `startAccessingSecurityScopedResource()`
    /// and `stopAccessingSecurityScopedResource()` directly.
    ///
    /// If `startAccessingSecurityScopedResource()` returns `false`, the body is still
    /// executed — the file may be accessible via the powerbox (a current-session
    /// NSOpenPanel selection) or may be a local path that does not require a sandbox extension.
    @discardableResult
    public func withSecurityScopedAccess<T>(_ body: () throws -> T) rethrows -> T {
        let accessed = startAccessingSecurityScopedResource()
        defer { if accessed { stopAccessingSecurityScopedResource() } }
        return try body()
    }

    /// Async variant of ``withSecurityScopedAccess(_:)``.
    ///
    /// Security-scoped access is active from the point of `startAccessingSecurityScopedResource()`
    /// through the entire async body, including any suspension points. Access is released
    /// in the `defer` block when the function returns, regardless of suspension.
    @discardableResult
    public func withSecurityScopedAccess<T>(_ body: () async throws -> T) async rethrows -> T {
        let accessed = startAccessingSecurityScopedResource()
        defer { if accessed { stopAccessingSecurityScopedResource() } }
        return try await body()
    }
}
