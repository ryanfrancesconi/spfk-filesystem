// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation

/// Folder names shared by every cache store under one caches root.
public enum CacheDirectoryName {
    /// The folder each store keeps its own directory in: `<caches root>/Data/<store>`.
    public static let data = "Data"
}
