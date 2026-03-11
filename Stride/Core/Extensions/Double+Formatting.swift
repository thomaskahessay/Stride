import Foundation

extension Int {
    /// Formats a pace stored as seconds-per-mile into a display string
    /// respecting the user's unit preference.
    ///
    /// Example: 628 sec/mile → "6:30 /km" (kilometers) or "10:28 /mi" (miles)
    func formattedPace(unit: UnitSystem) -> String {
        let secPerUnit: Int
        switch unit {
        case .miles:
            secPerUnit = self
        case .kilometers:
            secPerUnit = Int(Double(self) / 1.60934)
        }
        let minutes = secPerUnit / 60
        let seconds = secPerUnit % 60
        return String(format: "%d:%02d /%@", minutes, seconds, unit.shortLabel)
    }

    /// Formats a pace as a compact label without the slash-unit suffix.
    /// Useful in tight layouts where the unit is shown separately.
    func formattedPaceCompact(unit: UnitSystem) -> String {
        let secPerUnit: Int
        switch unit {
        case .miles:
            secPerUnit = self
        case .kilometers:
            secPerUnit = Int(Double(self) / 1.60934)
        }
        let minutes = secPerUnit / 60
        let seconds = secPerUnit % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

extension Double {
    /// Formats a distance in miles to a localised display string.
    func formattedDistance(unit: UnitSystem) -> String {
        let value = unit.convert(self)
        return String(format: value < 10 ? "%.1f" : "%.0f", value)
    }
}
