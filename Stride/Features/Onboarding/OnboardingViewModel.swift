import SwiftUI
import SwiftData

// MARK: - Onboarding Step

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case goalSetup
    case experience
    case fitnessBenchmark
    case injuryCheck
    case lifestyle
    case schedule
    case healthSync
    case planPreview

    var title: String {
        switch self {
        case .welcome:          return "Welcome to Stride"
        case .goalSetup:        return "Your race goal"
        case .experience:       return "Your running background"
        case .fitnessBenchmark: return "Where you are right now"
        case .injuryCheck:      return "Any aches or pains?"
        case .lifestyle:        return "Your daily life"
        case .schedule:         return "Your weekly schedule"
        case .healthSync:       return "Sync your recent runs"
        case .planPreview:      return "Your plan is ready"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome:          return "Let's build your personalised training plan."
        case .goalSetup:        return "Your goal shapes every workout we prescribe."
        case .experience:       return "The more we know, the better we calibrate your plan."
        case .fitnessBenchmark: return "This anchors your training paces and weekly load."
        case .injuryCheck:      return "We factor this into your load management from day one."
        case .lifestyle:        return "Your day affects how your body recovers from training."
        case .schedule:         return "Choose the days that work best for you."
        case .healthSync:       return "We use your recent runs to pinpoint your plan entry week."
        case .planPreview:      return "Review your plan and start training."
        }
    }

    var progress: Double {
        Double(rawValue + 1) / Double(OnboardingStep.allCases.count)
    }
}

// MARK: - ViewModel

@Observable
final class OnboardingViewModel {

    // MARK: Step state
    var currentStep: OnboardingStep = .welcome
    var isAnimatingForward = true

    // MARK: Welcome
    var firstName: String = ""
    var selectedUnitSystem: UnitSystem = .kilometers

    // MARK: Goal setup
    var selectedGoalType: GoalType = .finishComfortably
    var selectedRaceType: RaceType = .fullMarathon
    var raceDate: Date = Calendar.current.date(
        byAdding: .day, value: 90, to: Date()
    ) ?? Date()

    // MARK: Experience
    var selectedExperience: RunningExperience = .oneToThree
    var priorRacesCompleted: Set<RaceType> = []

    var selectedFitnessLevel: FitnessLevel {
        selectedExperience.suggestedFitnessLevel
    }

    // MARK: Fitness benchmark
    var currentWeeklyMiles: Double = 20
    var hasRecentRaceTime: Bool = false
    var recentRaceType: RaceType = .fiveK
    var recentRaceHours: Int = 0
    var recentRaceMinutes: Int = 28
    var recentRaceSeconds: Int = 0

    // MARK: Easy / Zone 2 pace
    // Stored as min:sec in the user's preferred unit; converted to sec/mile for the model.
    var zone2PaceMinutes: Int = 6
    var zone2PaceSeconds: Int = 30

    /// Pace in seconds per mile — stored on UserProfile as the plan anchor.
    var zone2PaceSecondsPerMile: Int {
        let totalSec = zone2PaceMinutes * 60 + zone2PaceSeconds
        switch selectedUnitSystem {
        case .miles:
            return totalSec
        case .kilometers:
            return Int(Double(totalSec) * 1.60934)
        }
    }

    /// Suggested Zone 2 pace label for the user's experience level and unit preference.
    var suggestedZone2PaceLabel: String {
        let secPerKm: Int
        switch selectedExperience {
        case .newRunner:    secPerKm = 510  // 8:30 /km
        case .underOneYear: secPerKm = 450  // 7:30 /km
        case .oneToThree:   secPerKm = 390  // 6:30 /km
        case .threeToFive:  secPerKm = 360  // 6:00 /km
        case .fivePlus:     secPerKm = 330  // 5:30 /km
        }
        let displaySec = selectedUnitSystem == .kilometers
            ? secPerKm
            : Int(Double(secPerKm) * 1.60934)
        let m = displaySec / 60
        let s = displaySec % 60
        return String(format: "%d:%02d /%@", m, s, selectedUnitSystem.shortLabel)
    }

    /// Apply the experience-level suggestion to the pace pickers.
    func applyZone2Suggestion() {
        let secPerKm: Int
        switch selectedExperience {
        case .newRunner:    secPerKm = 510
        case .underOneYear: secPerKm = 450
        case .oneToThree:   secPerKm = 390
        case .threeToFive:  secPerKm = 360
        case .fivePlus:     secPerKm = 330
        }
        let displaySec = selectedUnitSystem == .kilometers
            ? secPerKm
            : Int(Double(secPerKm) * 1.60934)
        zone2PaceMinutes = displaySec / 60
        zone2PaceSeconds = displaySec % 60
    }

    // MARK: Goal finish time
    var hasGoalFinishTime: Bool = false
    var goalFinishHours: Int = 4
    var goalFinishMinutes: Int = 30
    var goalFinishSecs: Int = 0

    /// Total seconds for the goal finish time; 0 when no target is set.
    var goalFinishTotalSeconds: Int {
        (selectedGoalType != .finishComfortably || hasGoalFinishTime)
            ? goalFinishHours * 3600 + goalFinishMinutes * 60 + goalFinishSecs
            : 0
    }

    var formattedGoalTime: String {
        let h = goalFinishHours
        let m = goalFinishMinutes
        let s = goalFinishSecs
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    // MARK: Injury
    var currentInjuryRegion: InjuryRegion = .none

    // MARK: Lifestyle
    var sleepHoursPerNight: Double = 7
    var selectedActivityLevel: ActivityLevel = .mixed
    var doesStrengthTraining: Bool = false

    // MARK: Schedule
    var trainingDaysPerWeek: Int = 4
    var preferredLongRunDay: Weekday = .sunday
    var selectedRestDays: Set<Weekday> = [.monday]

    // MARK: Health sync
    var recentRuns: [RecentRunEntry] = []
    var isLoadingHealthKitRuns: Bool = false

    /// Background task that fetches the 3-month HealthKit history concurrently
    /// while the user reviews the healthSync step. Awaited in complete().
    private var historicalFetchTask: Task<[HistoricalRunImportData], Never>?

    // MARK: Plan preview
    var suggestedEntryWeek: Int = 1
    var selectedEntryWeek: Int = 1
    var generatedPlan: TrainingPlan?
    var totalPlanWeeks: Int = 18

    // MARK: State flags
    var isGeneratingPlan: Bool = false
    var isComplete: Bool = false

    // MARK: - Validation

    var canAdvance: Bool {
        switch currentStep {
        case .welcome:
            return firstName.trimmingCharacters(in: .whitespaces).count >= 1
        case .goalSetup:
            return raceDate > Calendar.current.date(byAdding: .weekOfYear, value: 4, to: Date()) ?? Date()
        case .experience:
            return true
        case .fitnessBenchmark:
            return true
        case .injuryCheck:
            return true
        case .lifestyle:
            return true
        case .schedule:
            return !selectedRestDays.contains(preferredLongRunDay)
                && trainingDaysPerWeek <= (7 - selectedRestDays.count)
        case .healthSync:
            return true
        case .planPreview:
            return generatedPlan != nil
        }
    }

    var scheduleValidationError: String? {
        if selectedRestDays.contains(preferredLongRunDay) {
            return "Your long run day can't be a rest day."
        }
        if trainingDaysPerWeek > (7 - selectedRestDays.count) {
            return "You've selected too many rest days for \(trainingDaysPerWeek) training days."
        }
        return nil
    }

    // MARK: - Navigation

    func advance() {
        guard canAdvance else { return }
        isAnimatingForward = true

        if currentStep == .healthSync {
            generatePlanPreview()
        }

        if let next = OnboardingStep(rawValue: currentStep.rawValue + 1) {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentStep = next
            }
        }
    }

    func goBack() {
        isAnimatingForward = false
        if let prev = OnboardingStep(rawValue: currentStep.rawValue - 1) {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentStep = prev
            }
        }
    }

    // MARK: - HealthKit

    func loadHealthKitRuns() async {
        isLoadingHealthKitRuns = true
        await HealthKitManager.shared.requestAuthorisation()

        guard HealthKitManager.shared.isAuthorized else {
            isLoadingHealthKitRuns = false
            return
        }

        // Fetch the full 3-month history. This task is also awaited in complete()
        // to persist results — Task.value is cached so no double-fetch occurs.
        if historicalFetchTask == nil {
            historicalFetchTask = Task {
                await HealthKitManager.shared.fetchHistoricalRuns(months: 3)
            }
        }

        // Await the fetch and display all 3 months in the run list
        let importData = await historicalFetchTask!.value
        let mapped = importData.map { data in
            RecentRunEntry(
                date: data.startDate,
                workoutType: .easyRun,
                distanceKm: data.distanceMiles * 1.60934,
                durationMinutes: Int(data.durationSeconds / 60),
                isFromHealthKit: true
            )
        }
        let manual = recentRuns.filter { !$0.isFromHealthKit }
        recentRuns = (mapped + manual).sorted { $0.date > $1.date }
        isLoadingHealthKitRuns = false
    }

    func addManualRun(_ run: RecentRunEntry) {
        recentRuns.insert(run, at: 0)
    }

    func removeRun(at offsets: IndexSet) {
        recentRuns.remove(atOffsets: offsets)
    }

    // MARK: - Plan Generation

    func generatePlanPreview() {
        isGeneratingPlan = true
        let profile = buildTemporaryProfile()
        let generator = TrainingPlanGenerator()
        let plan = generator.generate(from: profile)
        totalPlanWeeks = plan.totalWeeks
        suggestedEntryWeek = plan.entryWeek
        selectedEntryWeek = plan.entryWeek
        generatedPlan = plan
        isGeneratingPlan = false
    }

    // MARK: - Completion

    func complete(modelContext: ModelContext) async {
        let profile = buildFinalProfile()
        let generator = TrainingPlanGenerator()
        let plan = generator.generate(from: profile)
        plan.entryWeek = selectedEntryWeek
        profile.activePlan = plan
        profile.onboardingComplete = true
        modelContext.insert(profile)
        try? modelContext.save()
        NotificationManager.shared.scheduleAll(for: profile)

        // Await the background historical fetch (likely already complete by now)
        // and persist the results. No-op if HK was denied or the task wasn't started.
        if let task = historicalFetchTask {
            let importData = await task.value
            if !importData.isEmpty {
                let service = HistoricalRunService(modelContext: modelContext)
                service.persist(importData)
            }
        }

        isComplete = true
    }

    // MARK: - Private Helpers

    private func buildTemporaryProfile() -> UserProfile {
        let profile = UserProfile(
            firstName: firstName,
            raceType: selectedRaceType,
            raceDate: raceDate,
            fitnessLevel: selectedFitnessLevel,
            currentWeeklyMiles: currentWeeklyMiles,
            trainingDaysPerWeek: trainingDaysPerWeek,
            preferredLongRunDay: preferredLongRunDay,
            restDays: Array(selectedRestDays),
            unitPreference: selectedUnitSystem
        )
        profile.goalType = selectedGoalType
        profile.goalFinishTimeSeconds = goalFinishTotalSeconds
        profile.zone2PaceSecondsPerMile = zone2PaceSecondsPerMile
        profile.runningExperience = selectedExperience
        profile.priorRacesCompleted = Array(priorRacesCompleted)
        profile.currentInjuryRegion = currentInjuryRegion
        profile.sleepHoursPerNight = sleepHoursPerNight
        profile.activityLevel = selectedActivityLevel
        profile.doesStrengthTraining = doesStrengthTraining
        if hasRecentRaceTime {
            profile.recentRaceTime = RaceTime(
                raceDistance: recentRaceType,
                finishTimeSeconds: recentRaceHours * 3600 + recentRaceMinutes * 60 + recentRaceSeconds,
                raceDate: Date()
            )
        }
        profile.recentRuns = recentRuns
        return profile
    }

    private func buildFinalProfile() -> UserProfile {
        buildTemporaryProfile()
    }
}
