import Foundation
import SwiftData

// MARK: - Enumerations

enum RaceType: String, Codable, CaseIterable {
    case fiveK = "5K"
    case tenK = "10K"
    case halfMarathon = "Half Marathon"
    case fullMarathon = "Full Marathon"

    var distanceMiles: Double {
        switch self {
        case .fiveK: return 3.1
        case .tenK: return 6.2
        case .halfMarathon: return 13.1
        case .fullMarathon: return 26.2
        }
    }

    var distanceKm: Double {
        switch self {
        case .fiveK: return 5.0
        case .tenK: return 10.0
        case .halfMarathon: return 21.1
        case .fullMarathon: return 42.2
        }
    }

    var standardPlanWeeks: Int {
        switch self {
        case .fiveK: return 8
        case .tenK: return 10
        case .halfMarathon: return 14
        case .fullMarathon: return 18
        }
    }

    var displayName: String { rawValue }

    var shortDisplayName: String {
        switch self {
        case .fiveK: return "5K"
        case .tenK: return "10K"
        case .halfMarathon: return "Half"
        case .fullMarathon: return "Full"
        }
    }
}

enum WorkoutType: String, Codable, CaseIterable {
    case easyRun = "Easy Run"
    case longRun = "Long Run"
    case tempoRun = "Tempo Run"
    case intervalRun = "Intervals"
    case recoveryRun = "Recovery Run"
    case strengthDay = "Strength Day"
    case restDay = "Rest Day"

    var isRun: Bool {
        switch self {
        case .easyRun, .longRun, .tempoRun, .intervalRun, .recoveryRun: return true
        case .strengthDay, .restDay: return false
        }
    }

    var isHard: Bool {
        switch self {
        case .tempoRun, .intervalRun, .longRun: return true
        default: return false
        }
    }

    var colorToken: String {
        switch self {
        case .easyRun: return "mint"
        case .longRun: return "lavender"
        case .tempoRun: return "sage"
        case .intervalRun: return "coral"
        case .recoveryRun: return "green"
        case .strengthDay: return "sky"
        case .restDay: return "gray"
        }
    }

    var sfSymbol: String {
        switch self {
        case .easyRun: return "figure.run"
        case .longRun: return "figure.run.circle.fill"
        case .tempoRun: return "flame.fill"
        case .intervalRun: return "bolt.fill"
        case .recoveryRun: return "figure.walk"
        case .strengthDay: return "dumbbell.fill"
        case .restDay: return "moon.fill"
        }
    }
}

enum FitnessLevel: String, Codable, CaseIterable {
    case beginner = "Beginner"
    case intermediate = "Intermediate"
    case advanced = "Advanced"

    var description: String {
        switch self {
        case .beginner: return "New to running or returning after a long break. Run/walk combinations are common."
        case .intermediate: return "Running consistently for 6+ months. Comfortable with distances up to a 10K."
        case .advanced: return "Running 4+ days/week for 1+ year. Familiar with tempo runs and intervals."
        }
    }
}

enum EffortLevel: String, Codable {
    case easy = "Easy"
    case moderate = "Moderate"
    case hard = "Hard"
    case maxEffort = "Max Effort"

    var description: String {
        switch self {
        case .easy: return "Conversational pace — full sentences, comfortable breathing"
        case .moderate: return "Comfortably hard — short sentences, controlled effort"
        case .hard: return "Very hard — few words, heavy breathing"
        case .maxEffort: return "All out — race pace or faster, unsustainable"
        }
    }

    var rpeRange: String {
        switch self {
        case .easy: return "RPE 3–4"
        case .moderate: return "RPE 5–6"
        case .hard: return "RPE 7–8"
        case .maxEffort: return "RPE 9–10"
        }
    }
}

enum Weekday: Int, Codable, CaseIterable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    var displayName: String {
        switch self {
        case .sunday: return "Sunday"
        case .monday: return "Monday"
        case .tuesday: return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday: return "Thursday"
        case .friday: return "Friday"
        case .saturday: return "Saturday"
        }
    }

    var shortName: String { String(displayName.prefix(3)) }
}

enum UnitSystem: String, Codable, CaseIterable {
    case miles = "Miles"
    case kilometers = "Kilometers"

    var shortLabel: String {
        switch self {
        case .miles: return "mi"
        case .kilometers: return "km"
        }
    }

    func convert(_ miles: Double) -> Double {
        switch self {
        case .miles: return miles
        case .kilometers: return miles * 1.60934
        }
    }
}

enum AdaptationType: String, Codable {
    case downgraded           // intervals→tempo, tempo→easy, etc.
    case skippedByCoach       // engine auto-skipped a workout
    case progressionHeld      // weekly mileage frozen at previous week's level
    case recoveryInserted     // converted to recovery run
    case strengthSubstituted  // hard run → strength/mobility session
}

enum RestDayActivityType: String, Codable, CaseIterable {
    case crossTraining = "Cross-Training"
    case easyShakeout  = "Easy Shakeout"
    case fullRun       = "Full Run"

    var description: String {
        switch self {
        case .crossTraining: return "Yoga, swimming, cycling — logged but doesn't count toward running volume."
        case .easyShakeout:  return "A short, easy jog under 2 miles / 3 km — minimal impact on recovery."
        case .fullRun:       return "A proper run — counts toward your weekly mileage."
        }
    }

    var sfSymbol: String {
        switch self {
        case .crossTraining: return "figure.cooldown"
        case .easyShakeout:  return "figure.walk"
        case .fullRun:       return "figure.run"
        }
    }

    /// Whether this activity type should count toward weekly running mileage.
    var countsTowardRunningVolume: Bool {
        switch self {
        case .crossTraining: return false
        case .easyShakeout:  return true
        case .fullRun:       return true
        }
    }
}

enum GoalType: String, Codable, CaseIterable {
    case finishComfortably = "Finish Comfortably"
    case targetTime        = "Hit a Target Time"
    case competitive       = "Race Competitively"

    var description: String {
        switch self {
        case .finishComfortably: return "Enjoy the journey and cross the finish line feeling strong."
        case .targetTime:        return "Train specifically to hit a goal finish time."
        case .competitive:       return "Peak performance — race hard and fight for every second."
        }
    }

    var sfSymbol: String {
        switch self {
        case .finishComfortably: return "heart.fill"
        case .targetTime:        return "stopwatch.fill"
        case .competitive:       return "bolt.fill"
        }
    }
}

enum RunningExperience: String, Codable, CaseIterable {
    case newRunner    = "New to running"
    case underOneYear = "Under 1 year"
    case oneToThree   = "1–3 years"
    case threeToFive  = "3–5 years"
    case fivePlus     = "5+ years"

    var description: String {
        switch self {
        case .newRunner:    return "Just getting started or returning from a long break."
        case .underOneYear: return "Run occasionally, still building a consistent habit."
        case .oneToThree:   return "Running regularly, have completed at least one race."
        case .threeToFive:  return "Multi-year runner, comfortable with longer distances."
        case .fivePlus:     return "Experienced runner with a solid training base."
        }
    }

    var suggestedFitnessLevel: FitnessLevel {
        switch self {
        case .newRunner, .underOneYear: return .beginner
        case .oneToThree:               return .intermediate
        case .threeToFive, .fivePlus:   return .advanced
        }
    }
}

enum InjuryRegion: String, Codable, CaseIterable {
    case none      = "No current issues"
    case knee      = "Knee"
    case shinCalf  = "Shin / Calf"
    case hipGlute  = "Hip / Glute"
    case footAnkle = "Foot / Ankle"
    case lowerBack = "Lower Back"
    case other     = "Other"

    var sfSymbol: String {
        switch self {
        case .none:      return "checkmark.circle.fill"
        case .knee:      return "figure.run"
        case .shinCalf:  return "figure.run"
        case .hipGlute:  return "figure.run"
        case .footAnkle: return "figure.run"
        case .lowerBack: return "figure.run"
        case .other:     return "bandage.fill"
        }
    }

    var planNote: String? {
        switch self {
        case .none:      return nil
        case .knee:      return "We'll limit downhill repeats and keep easy days truly easy."
        case .shinCalf:  return "Conservative mileage build and calf mobility cues included."
        case .hipGlute:  return "Extra rest buffers and hip mobility guidance on easy days."
        case .footAnkle: return "Softer surface tips and arch care notes included."
        case .lowerBack: return "Core-stability tips and posture cues on your easy runs."
        case .other:     return "We'll build cautiously — please see a physio if pain persists."
        }
    }
}

enum ActivityLevel: String, Codable, CaseIterable {
    case sedentary = "Mostly sedentary"
    case mixed     = "Mix of sitting and moving"
    case active    = "On my feet all day"

    var description: String {
        switch self {
        case .sedentary: return "Office or desk-based — most of the day is sitting."
        case .mixed:     return "Some walking and movement but also long periods sitting."
        case .active:    return "Retail, healthcare, trades — physically demanding all day."
        }
    }

    var sfSymbol: String {
        switch self {
        case .sedentary: return "laptopcomputer"
        case .mixed:     return "figure.walk"
        case .active:    return "figure.stand"
        }
    }
}

// MARK: - Pace Zones

/// All training paces derived from the user's Zone 2 easy pace.
/// Stored internally as seconds per mile; convert to km for display.
struct PaceZones: Codable {
    let recoveryPaceSecPerMile: Int    // RPE 3–4  — easy jog / between intervals
    let easyPaceSecPerMile: Int        // RPE 4–5  — Zone 2 anchor (user-supplied)
    let longRunPaceSecPerMile: Int     // RPE 5    — aerobic long run (same as easy)
    let tempoPaceSecPerMile: Int       // RPE 6–7  — lactate threshold
    let racePaceSecPerMile: Int        // RPE 7–8  — goal race pace
    let intervalPaceSecPerMile: Int    // RPE 8–9  — VO2max / 5K effort

    /// Derive all zones from the user's Zone 2 pace.
    /// Race pace uses the goal-time anchor when available; otherwise estimated from Zone 2.
    static func from(
        zone2SecPerMile: Int,
        goalTimeSeconds: Int,
        raceType: RaceType
    ) -> PaceZones {
        let z2 = Double(zone2SecPerMile)

        let racePace: Int
        if goalTimeSeconds > 0 {
            racePace = Int(Double(goalTimeSeconds) / raceType.distanceMiles)
        } else {
            let multiplier: Double
            switch raceType {
            case .fiveK:        multiplier = 0.76
            case .tenK:         multiplier = 0.78
            case .halfMarathon: multiplier = 0.80
            case .fullMarathon: multiplier = 0.83
            }
            racePace = Int(z2 * multiplier)
        }

        return PaceZones(
            recoveryPaceSecPerMile: Int(z2 * 1.10),
            easyPaceSecPerMile: zone2SecPerMile,
            longRunPaceSecPerMile: zone2SecPerMile,
            tempoPaceSecPerMile: Int(z2 * 0.87),
            racePaceSecPerMile: racePace,
            intervalPaceSecPerMile: Int(z2 * 0.80)
        )
    }
}

// MARK: - Value Types

struct WorkoutStep: Codable, Identifiable {
    var id: UUID = UUID()
    var order: Int
    var label: String
    var distanceMiles: Double?
    var durationMinutes: Int?
    var description: String
    var targetPaceSecPerMile: Int? = nil
}

struct RecentRunEntry: Codable, Identifiable {
    var id: UUID = UUID()
    var date: Date
    var workoutType: WorkoutType
    var distanceKm: Double
    var durationMinutes: Int
    var isFromHealthKit: Bool

    var distanceMiles: Double { distanceKm / 1.60934 }
}

struct RaceTime: Codable {
    var raceDistance: RaceType
    var finishTimeSeconds: Int
    var raceDate: Date

    var formattedTime: String {
        let h = finishTimeSeconds / 3600
        let m = (finishTimeSeconds % 3600) / 60
        let s = finishTimeSeconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }
}

// MARK: - SwiftData Models

@Model
final class UserProfile {
    var id: UUID
    var firstName: String
    var raceType: RaceType
    var raceDate: Date
    var fitnessLevel: FitnessLevel
    var currentWeeklyMiles: Double
    var trainingDaysPerWeek: Int
    var preferredLongRunDay: Weekday
    var restDays: [Weekday]
    var recentRaceTimeData: Data?   // encoded RaceTime
    var recentRunsData: Data?       // encoded [RecentRunEntry]
    var unitPreference: UnitSystem
    var onboardingComplete: Bool
    var createdAt: Date
    var notificationsEnabled: Bool
    var dailyReminderHour: Int      // 0–23
    var dailyReminderMinute: Int

    // MARK: Extended profile (onboarding v2)
    var goalType: GoalType
    var goalFinishTimeSeconds: Int   // 0 = no target time set
    var zone2PaceSecondsPerMile: Int // 0 = not set; user's comfortable Zone 2 pace
    var runningExperience: RunningExperience
    var priorRacesCompleted: [RaceType]
    var currentInjuryRegion: InjuryRegion
    var sleepHoursPerNight: Double
    var activityLevel: ActivityLevel
    var doesStrengthTraining: Bool

    @Relationship(deleteRule: .cascade)
    var activePlan: TrainingPlan?

    init(
        firstName: String = "",
        raceType: RaceType = .fullMarathon,
        raceDate: Date = Date(),
        fitnessLevel: FitnessLevel = .intermediate,
        currentWeeklyMiles: Double = 20,
        trainingDaysPerWeek: Int = 4,
        preferredLongRunDay: Weekday = .sunday,
        restDays: [Weekday] = [.monday],
        unitPreference: UnitSystem = .kilometers
    ) {
        self.id = UUID()
        self.firstName = firstName
        self.raceType = raceType
        self.raceDate = raceDate
        self.fitnessLevel = fitnessLevel
        self.currentWeeklyMiles = currentWeeklyMiles
        self.trainingDaysPerWeek = trainingDaysPerWeek
        self.preferredLongRunDay = preferredLongRunDay
        self.restDays = restDays
        self.unitPreference = unitPreference
        self.onboardingComplete = false
        self.createdAt = Date()
        self.notificationsEnabled = true
        self.dailyReminderHour = 7
        self.dailyReminderMinute = 0
        self.goalType = .finishComfortably
        self.goalFinishTimeSeconds = 0
        self.zone2PaceSecondsPerMile = 0
        self.runningExperience = .oneToThree
        self.priorRacesCompleted = []
        self.currentInjuryRegion = .none
        self.sleepHoursPerNight = 7
        self.activityLevel = .mixed
        self.doesStrengthTraining = false
    }

    var recentRaceTime: RaceTime? {
        get {
            guard let data = recentRaceTimeData else { return nil }
            return try? JSONDecoder().decode(RaceTime.self, from: data)
        }
        set {
            recentRaceTimeData = try? JSONEncoder().encode(newValue)
        }
    }

    var recentRuns: [RecentRunEntry] {
        get {
            guard let data = recentRunsData else { return [] }
            return (try? JSONDecoder().decode([RecentRunEntry].self, from: data)) ?? []
        }
        set {
            recentRunsData = try? JSONEncoder().encode(newValue)
        }
    }
}

@Model
final class TrainingPlan {
    var id: UUID
    var generatedAt: Date
    var planStartDate: Date
    var raceDate: Date
    var totalWeeks: Int
    var entryWeek: Int
    var isActive: Bool
    var paceZonesData: Data?        // encoded PaceZones?
    var lastAdaptationDate: Date?    // prevents re-running engine same day

    @Relationship(deleteRule: .cascade)
    var workoutDays: [WorkoutDay]

    init(
        planStartDate: Date,
        raceDate: Date,
        totalWeeks: Int,
        entryWeek: Int = 1
    ) {
        self.id = UUID()
        self.generatedAt = Date()
        self.planStartDate = planStartDate
        self.raceDate = raceDate
        self.totalWeeks = totalWeeks
        self.entryWeek = entryWeek
        self.isActive = true
        self.paceZonesData = nil
        self.lastAdaptationDate = nil
        self.workoutDays = []
    }

    var paceZones: PaceZones? {
        get {
            guard let data = paceZonesData else { return nil }
            return try? JSONDecoder().decode(PaceZones.self, from: data)
        }
        set {
            paceZonesData = try? JSONEncoder().encode(newValue)
        }
    }

    var currentWeekNumber: Int {
        let days = Calendar.current.dateComponents([.day], from: planStartDate, to: Date()).day ?? 0
        return max(1, min(totalWeeks, (days / 7) + 1))
    }

    /// Timeline-based progress: how far through the plan calendar we are (0.0–1.0).
    var completionPercentage: Double {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let start = cal.startOfDay(for: planStartDate)
        let end = cal.startOfDay(for: raceDate)
        let totalDays = cal.dateComponents([.day], from: start, to: end).day ?? 1
        guard totalDays > 0 else { return 1.0 }
        let elapsed = cal.dateComponents([.day], from: start, to: today).day ?? 0
        return min(1.0, max(0.0, Double(elapsed) / Double(totalDays)))
    }
}

@Model
final class WorkoutDay {
    var id: UUID
    var date: Date
    var weekNumber: Int
    var dayOfWeek: Weekday
    var workoutType: WorkoutType
    var targetDistanceMiles: Double
    var targetDurationMinutes: Int
    var targetPaceSecPerMile: Int?  // nil = effort-only (no goal time or zone2 set)
    var effortLevel: EffortLevel
    var workoutTitle: String
    var coachingNote: String
    var stepsData: Data?            // encoded [WorkoutStep]
    var isCompleted: Bool
    var isSkipped: Bool
    var rescheduledDate: Date?      // non-nil when user has moved this workout
    var isAdapted: Bool = false
    var originalWorkoutType: WorkoutType?       // what the generator originally created
    var originalTargetDistanceMiles: Double?    // original distance before adaptation
    var originalEffortLevel: EffortLevel?       // original effort before adaptation
    var adaptationNote: String?                 // "Downgraded from Tempo — recovery was low"

    @Relationship(deleteRule: .cascade)
    var log: WorkoutLog?

    init(
        date: Date,
        weekNumber: Int,
        dayOfWeek: Weekday,
        workoutType: WorkoutType,
        targetDistanceMiles: Double = 0,
        targetDurationMinutes: Int = 0,
        targetPaceSecPerMile: Int? = nil,
        effortLevel: EffortLevel = .easy,
        workoutTitle: String = "",
        coachingNote: String = "",
        steps: [WorkoutStep] = []
    ) {
        self.id = UUID()
        self.date = date
        self.weekNumber = weekNumber
        self.dayOfWeek = dayOfWeek
        self.workoutType = workoutType
        self.targetDistanceMiles = targetDistanceMiles
        self.targetDurationMinutes = targetDurationMinutes
        self.targetPaceSecPerMile = targetPaceSecPerMile
        self.effortLevel = effortLevel
        self.workoutTitle = workoutTitle
        self.coachingNote = coachingNote
        self.isCompleted = false
        self.isSkipped = false
        self.rescheduledDate = nil
        self.isAdapted = false
        self.originalWorkoutType = nil
        self.originalTargetDistanceMiles = nil
        self.originalEffortLevel = nil
        self.adaptationNote = nil
        self.steps = steps
    }

    var steps: [WorkoutStep] {
        get {
            guard let data = stepsData else { return [] }
            return (try? JSONDecoder().decode([WorkoutStep].self, from: data)) ?? []
        }
        set {
            stepsData = try? JSONEncoder().encode(newValue)
        }
    }

    /// The date this workout actually appears on — respects any user-initiated move.
    var effectiveDate: Date {
        rescheduledDate ?? date
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(effectiveDate)
    }

    var isPast: Bool {
        effectiveDate < Calendar.current.startOfDay(for: Date())
    }

    var isMissed: Bool {
        isPast && !isCompleted && !isSkipped && workoutType != .restDay
    }
}

@Model
final class WorkoutLog {
    var id: UUID
    var loggedAt: Date
    var actualDistanceMiles: Double
    var actualDurationSeconds: Int
    var effortRating: Int           // RPE 1–10
    var notes: String
    var sourceHealthKit: Bool
    var averageHeartRate: Double?
    var averagePaceSecPerMile: Int? // nil = not recorded
    var restDayActivityType: RestDayActivityType? // nil = normal workout day log

    init(
        actualDistanceMiles: Double = 0,
        actualDurationSeconds: Int = 0,
        effortRating: Int = 5,
        notes: String = "",
        sourceHealthKit: Bool = false,
        averageHeartRate: Double? = nil,
        averagePaceSecPerMile: Int? = nil,
        restDayActivityType: RestDayActivityType? = nil
    ) {
        self.id = UUID()
        self.loggedAt = Date()
        self.actualDistanceMiles = actualDistanceMiles
        self.actualDurationSeconds = actualDurationSeconds
        self.effortRating = effortRating
        self.notes = notes
        self.sourceHealthKit = sourceHealthKit
        self.averageHeartRate = averageHeartRate
        self.averagePaceSecPerMile = averagePaceSecPerMile
        self.restDayActivityType = restDayActivityType
    }

    var formattedDuration: String {
        let h = actualDurationSeconds / 3600
        let m = (actualDurationSeconds % 3600) / 60
        let s = actualDurationSeconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }
}

// MARK: - HistoricalRun

/// A running workout imported from HealthKit history (pre-plan).
/// Stores aggregated stats only — raw samples stay in HealthKit and can be re-queried.
@Model
final class HistoricalRun {
    // MARK: Identity
    var id: UUID
    var date: Date                          // workout start date (day precision for calendar lookup)
    var startDate: Date                     // exact start time
    var endDate: Date                       // exact end time
    var sourceHKUUID: String                // HKWorkout.uuid — used to prevent duplicate imports
    var isIndoorRun: Bool                   // true = treadmill, false = outdoor

    // MARK: Core stats (always present — derived from HKWorkout directly)
    var distanceMiles: Double
    var durationSeconds: Double
    var totalCalories: Double?              // nil if not recorded

    // MARK: Pace
    /// Seconds per mile. Computed from runningSpeed samples when available;
    /// falls back to durationSeconds / distanceMiles if the device did not record speed.
    var averagePaceSecondsPerMile: Double

    // MARK: Heart rate (from HKQuantityType(.heartRate) samples)
    var averageHeartRate: Double?           // bpm — nil if HR not recorded
    var maxHeartRate: Double?               // bpm

    // MARK: Running dynamics (iOS 16+ only — nil on older OS or if not recorded)
    var averageCadenceSPM: Double?          // steps per minute
    var averageStrideLengthMeters: Double?  // metres per stride

    init(
        startDate: Date,
        endDate: Date,
        sourceHKUUID: String,
        isIndoorRun: Bool,
        distanceMiles: Double,
        durationSeconds: Double,
        totalCalories: Double? = nil,
        averagePaceSecondsPerMile: Double,
        averageHeartRate: Double? = nil,
        maxHeartRate: Double? = nil,
        averageCadenceSPM: Double? = nil,
        averageStrideLengthMeters: Double? = nil
    ) {
        self.id = UUID()
        self.date = Calendar.current.startOfDay(for: startDate)
        self.startDate = startDate
        self.endDate = endDate
        self.sourceHKUUID = sourceHKUUID
        self.isIndoorRun = isIndoorRun
        self.distanceMiles = distanceMiles
        self.durationSeconds = durationSeconds
        self.totalCalories = totalCalories
        self.averagePaceSecondsPerMile = averagePaceSecondsPerMile
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.averageCadenceSPM = averageCadenceSPM
        self.averageStrideLengthMeters = averageStrideLengthMeters
    }

    // MARK: Computed helpers

    /// "8:32 /mi" or "5:18 /km" format depending on unit preference
    func formattedPace(units: UnitSystem) -> String {
        let paceSeconds = units == .miles
            ? averagePaceSecondsPerMile
            : averagePaceSecondsPerMile / 1.60934
        let total = Int(paceSeconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d /%@", m, s, units.shortLabel)
    }

    /// "42:15" or "1:12:04" format
    var formattedDuration: String {
        let total = Int(durationSeconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }

    /// Rounded to 1 decimal place for display
    var formattedDistance: String {
        String(format: "%.1f mi", distanceMiles)
    }
}
