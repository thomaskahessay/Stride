import Foundation

/// Provides a centralized "now" date for the entire app.
/// In DEBUG builds, allows overriding the current date for time-travel testing.
/// In RELEASE builds, always returns the real `Date()`.
@Observable
final class DateProvider {
    static let shared = DateProvider()

    #if DEBUG
    /// When non-nil, the app treats this as "now" instead of the real clock.
    var overrideDate: Date?

    /// The current date the app should use everywhere instead of `Date()`.
    var now: Date {
        overrideDate ?? Date()
    }

    /// Whether time travel is currently active.
    var isTimeTraveling: Bool {
        overrideDate != nil
    }

    /// Advance the override by a number of days.
    func advanceDays(_ count: Int) {
        let base = overrideDate ?? Date()
        overrideDate = Calendar.current.date(byAdding: .day, value: count, to: base)
    }

    /// Reset to real time.
    func resetToRealTime() {
        overrideDate = nil
    }
    #else
    var now: Date { Date() }
    var isTimeTraveling: Bool { false }
    #endif
}
