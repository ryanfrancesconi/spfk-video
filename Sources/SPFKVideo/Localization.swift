// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import Foundation

/// Looks up a localized string from the default (Localizable) table in this module's bundle.
func localized(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module)
}
