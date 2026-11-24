// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation
import SPFKBase
import UniformTypeIdentifiers

/// Every file's companions, the Live Photo rule included.
///
/// A still's same-named `.mov` is its companion only when both carry the same content identifier:
/// a short video can share a photo's name without being its movie.
public enum FileCompanions {
    /// Each of `urls` → its companions on disk, sidecars and edit records first. A movie paired
    /// with a still in `urls` is listed under that still and is never a key, even when it is in
    /// `urls` itself. A companion is listed under the first owner that claims it.
    public static func resolve(
        _ urls: [URL],
        identifiers: LivePhotoIdentifierReading = .system
    ) async -> [URL: [URL]] {
        await resolve(urls, identifiers: identifiers, listFolder: listing(of:))
    }

    /// - Parameter listFolder: the names in a folder, asked once per folder.
    static func resolve(
        _ urls: [URL],
        identifiers: LivePhotoIdentifierReading,
        listFolder: @Sendable (URL) -> [String]
    ) async -> [URL: [URL]] {
        let byPath = Dictionary(urls.map { ($0.standardizedFileURL.path, $0) }, uniquingKeysWith: { first, _ in first })
        var listings: [String: [String: String]] = [:]
        var movies: [URL: URL] = [:]
        var pairedMovies: Set<String> = []

        for still in urls where isPairableStill(still) {
            let folder = still.deletingLastPathComponent()
            let key = folder.standardizedFileURL.path

            if listings[key] == nil {
                listings[key] = Dictionary(listFolder(folder).map { (folded($0), $0) }, uniquingKeysWith: { first, _ in first })
            }

            let base = still.deletingPathExtension().lastPathComponent

            guard let name = listings[key]?[folded(base + ".mov")] else { continue }

            // Named as the caller names it when it is a row too.
            let found = folder.appendingPathComponent(name)
            let moviePath = found.standardizedFileURL.path
            let movie = byPath[moviePath] ?? found

            guard !pairedMovies.contains(moviePath),
                  let stillIdentifier = await identifiers.still(still),
                  let movieIdentifier = await identifiers.movie(movie),
                  stillIdentifier == movieIdentifier
            else { continue }

            movies[still] = movie
            pairedMovies.insert(moviePath)
        }

        var result: [URL: [URL]] = [:]
        var claimed: Set<URL> = []

        for url in urls where !pairedMovies.contains(url.standardizedFileURL.path) && result[url] == nil {
            var companions = url.existingCompanionURLs

            if let movie = movies[url] {
                companions.append(movie)
            }

            result[url] = companions.filter { claimed.insert($0).inserted }
        }

        return result
    }

    /// A still that can be a Live Photo's: an image other than a RAW.
    private static func isPairableStill(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image) && !type.conforms(to: .rawImage)
    }

    private static func folded(_ name: String) -> String {
        name.decomposedStringWithCanonicalMapping.lowercased()
    }

    private static func listing(of folder: URL) -> [String] {
        do {
            return try FileManager.default.contentsOfDirectory(atPath: folder.path)
        } catch {
            Log.error("Couldn't list \(folder.lastPathComponent)", error)
            return []
        }
    }
}
