import Foundation
import SwiftData

// MARK: - Readiness Recommendation

enum ReadinessRecommendation: String, Codable {
    case sendIt = "Send It"
    case dialBack = "Dial Back"
    case swapRecovery = "Swap to Recovery"
    case restToday = "Rest Today"

    var description: String {
        switch self {
        case .sendIt: return "You're primed. Run as planned."
        case .dialBack: return "Same workout, but ease off the pace or distance ~15-20%."
        case .swapRecovery: return "Replace with an easy 20-min shakeout jog."
        case .restToday: return "Your body is asking for a break. Swap with tomorrow."
        }
    }

    var sfSymbol: String {
        switch self {
        case .sendIt: return "bolt.fill"
        case .dialBack: return "dial.low.fill"
        case .swapRecovery: return "arrow.triangle.2.circlepath"
        case .restToday: return "moon.zzz.fill"
        }
    }

    var tintColor: String {
        switch self {
        case .sendIt: return "mint"
        case .dialBack: return "lavender"
        case .swapRecovery: return "warmOrange"
        case .restToday: return "coral"
        }
    }
}

// MARK: - ReadinessCheck Model

@Model
final class ReadinessCheck {
    var id: UUID
    var date: Date

    // Self-reported inputs (1-5 scale)
    var sleepQuality: Int
    var muscleSoreness: Int
    var energyLevel: Int
    var motivation: Int

    // HealthKit-sourced sleep (nil if unavailable)
    var healthKitSleepHours: Double?
    var healthKitSleepEfficiency: Double?

    // Output
    var recommendation: ReadinessRecommendation
    var readinessScore: Double // 0-100 composite score
    var wasAccepted: Bool

    init(
        sleepQuality: Int = 3,
        muscleSoreness: Int = 3,
        energyLevel: Int = 3,
        motivation: Int = 3,
        healthKitSleepHours: Double? = nil,
        healthKitSleepEfficiency: Double? = nil,
        recommendation: ReadinessRecommendation = .sendIt,
        readinessScore: Double = 50
    ) {
        self.id = UUID()
        self.date = Calendar.current.startOfDay(for: Date())
        self.sleepQuality = sleepQuality
        self.muscleSoreness = muscleSoreness
        self.energyLevel = energyLevel
        self.motivation = motivation
        self.healthKitSleepHours = healthKitSleepHours
        self.healthKitSleepEfficiency = healthKitSleepEfficiency
        self.recommendation = recommendation
        self.readinessScore = readinessScore
        self.wasAccepted = false
    }
}
