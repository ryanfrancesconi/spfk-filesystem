// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation

/// Looks up a localized string from the default (Localizable) table in this module's bundle.
///
/// **This package holds only what a filesystem state can say without knowing the product.** The
/// lock states and their write failures read the same whichever app is running, so they are worded
/// once here rather than in each product's catalog.
func localized(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module)
}
