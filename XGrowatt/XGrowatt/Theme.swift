import SwiftUI

/// Single source of truth for the app's palette.
///
/// Every view aliases its local color constants to these statics, so the semantic names
/// (`batteryGreen`, `solarGold`, …) mean the same pixel values on every page. Before this
/// existed, ContentView used a saturated palette (#10B981 emerald / #F59E0B amber) while
/// EnergyFlowView and the Analytics charts used a lighter pastel variant of the same names —
/// two different greens could appear on the same screen. Change a value here, it changes
/// everywhere.
enum Theme {
    // Core energy-domain palette
    static let solarGold    = Color(red: 0.96, green: 0.62, blue: 0.04)  // #F59E0B amber
    static let batteryGreen = Color(red: 0.06, green: 0.73, blue: 0.51)  // #10B981 emerald
    static let loadBlue     = Color(red: 0.14, green: 0.54, blue: 0.90)  // #2489E6
    static let gridPurple   = Color(red: 0.70, green: 0.36, blue: 0.98)  // #B35BF9
    static let alertRed     = Color(red: 0.94, green: 0.27, blue: 0.27)  // #F04545

    // Per-MPPT string accents (charts, tooltips, dashboard sub-rows)
    static let pv1Cyan = Color(red: 94/255, green: 234/255, blue: 212/255)   // teal
    static let pv2Pink = Color(red: 244/255, green: 114/255, blue: 182/255)  // pink

    // Surfaces
    static let bgDark = Color(red: 0.07, green: 0.07, blue: 0.08)
    static let cardBg = Color(red: 0.12, green: 0.12, blue: 0.14)
}
