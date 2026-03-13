import SwiftUI
import SwiftData

// MARK: - Onboarding Step (New 6-step flow)

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case healthSync
    case fitnessProfile
    case goalSetup
    case schedule
    case planPreview

    var title: String {
        switch self {
        case .welcome:        return "Welcome to Stride"
        case .healthSync:     return "Sync your runs"
        case .fitnessProfile: return "Your fitness profile"
        case .goalSetup:      return "Your race goal"
        case .schedule:       return "Your weekly schedule"
        case .planPreview:    return "Your plan is ready"
        }
    }

    var coachingLine: String {
        switch self {
        case .welcome:        return "Let's get to know you and build a plan that fits your life."
        case .healthSync:     return "If you've been running with Apple Watch, we can pick up right where you left off."
        case .fitnessProfile: return "Here's what your recent runs tell us — adjust anything that doesn't feel right."
        case .goalSetup:      return "Now let's set the target — everything in your plan works backward from race day."
        case .schedule:       return "Pick the days that work for your week — consistency beats perfection."
        case .planPreview:    return "Your plan is ready. Every workout is built around what you told us."
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

    // MARK: Health sync
    var isLoadingHealthKitRuns: Bool = false
    var healthSyncState: HealthSyncState = .notStarted
    var runCount: Int = 0

    enum HealthSyncState {
        case notStarted
        case loading
        case success(runCount: Int)
        case skipped
        case notEnoughData
    }

    // MARK: Fitness analysis
    var fitnessAnalysis: FitnessAnalysis?
    var hasEnoughData: Bool { fitnessAnalysis?.hasEnoughData ?? false }

    // MARK: Fitness profile (editable — pre-filled from analysis when available)
    var currentWeeklyMiles: Double = 20
    var zone2PaceMinutes: Int = 6
    var zone2PaceSeconds: Int = 30
    var selectedFitnessLevel: FitnessLevel = .intermediate
    var longestRunMiles: Double = 0
    var runsPerWeekDisplay: Double = 0
    var hasRecentRaceTime: Bool = false
    var recentRaceType: RaceType = .fiveK
    var recentRaceHours: Int = 0
    var recentRaceMinutes: Int = 28
    var recentRaceSeconds: Int = 0

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

    // MARK: Goal setup
    var selectedGoalType: GoalType = .finishComfortably
    var selectedRaceType: RaceType = .fullMarathon
    var raceDate: Date = Calendar.current.date(
        byAdding: .day, value: 90, to: Date()
    ) ?? Date()

    var hasGoalFinishTime: Bool = false
    var goalFinishHours: Int = 4
    var goalFinishMinutes: Int = 30
    var goalFinishSecs: Int = 0

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

    // MARK: Schedule
    var trainingDaysPerWeek: Int = 4
    var preferredLongRunDay: Weekday = .sunday
    var selectedRestDays: Set<Weekday> = [.monday]

    // MARK: Plan preview
    var suggestedEntryWeek: Int = 1
    var selectedEntryWeek: Int = 1
    var generatedPlan: TrainingPlan?
    var totalPlanWeeks: Int = 18

    // MARK: State flags
    var isGeneratingPlan: Bool = false
    var isComplete: Bool = false

    // MARK: Internal
    var recentRuns: [RecentRunEntry] = []
    private var historicalFetchTask: Task<[HistoricalRunImportData], Never>?
    private var historicalRunData: [HistoricalRunImportData] = []

    // MARK: - Coaching Lines

    /// Returns the appropriate coaching line for the fitness profile step
    /// based on whether HealthKit data is available.
    var fitnessProfileCoachingLine: String {
        if hasEnoughData {
            return "Here's what your recent runs tell us — adjust anything that doesn't feel right."
        } else {
            return "No worries — a few details and we'll have everything we need."
        }
    }

    /// Returns the header text for the fitness profile step.
    var fitnessProfileHeader: String {
        hasEnoughData ? "Here's what we found" : "Tell us about your running"
    }

    /// Schedule coaching note based on detected patterns.
    var schedulePatternNote: String? {
        guard let analysis = fitnessAnalysis, analysis.hasEnoughData else { return nil }
        let dayNames = analysis.preferredRunDays.prefix(4).map(\.shortName).joined(separator: ", ")
        let longDay = analysis.likelyLongRunDay?.displayName ?? preferredLongRunDay.displayName
        return "Based on your history, you usually run on \(dayNames) with your long run on \(longDay)"
    }

    // MARK: - Validation

    var canAdvance: Bool {
        switch currentStep {
        case .welcome:
            return firstName.trimmingCharacters(in: .whitespaces).count >= 1
        case .healthSync:
            return true // Can always skip or continue after sync
        case .fitnessProfile:
            return true
        case .goalSetup:
            return raceDate > Calendar.current.date(byAdding: .weekOfYear, value: 4, to: Date()) ?? Date()
        case .schedule:
            return !selectedRestDays.contains(preferredLongRunDay)
                && trainingDaysPerWeek <= (7 - selectedRestDays.count)
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

        if currentStep == .schedule {
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

    // MARK: - HealthKit Sync + Analysis

    func syncHealthKit() async {
        healthSyncState = .loading
        isLoadingHealthKitRuns = true

        await HealthKitManager.shared.requestAuthorisation()

        guard HealthKitManager.shared.isAuthorized else {
            healthSyncState = .skipped
            isLoadingHealthKitRuns = false
            return
        }

        // Fetch 3 months of history
        let importData = await HealthKitManager.shared.fetchHistoricalRuns(months: 3)
        historicalRunData = importData

        // Map to recent runs for display
        let mapped = importData.map { data in
            RecentRunEntry(
                date: data.startDate,
                workoutType: .easyRun,
                distanceKm: data.distanceMiles * 1.60934,
                durationMinutes: Int(data.durationSeconds / 60),
                isFromHealthKit: true
            )
        }
        recentRuns = mapped.sorted { $0.date > $1.date }
        runCount = importData.count

        // Run fitness analysis
        let analyzer = RunningFitnessAnalyzer()
        let analysis = analyzer.analyze(importData)
        fitnessAnalysis = analysis

        if analysis.hasEnoughData {
            applyAnalysisToFields(analysis)
            healthSyncState = .success(runCount: importData.count)
        } else {
            healthSyncState = .notEnoughData
        }

        isLoadingHealthKitRuns = false
    }

    func skipHealthSync() {
        healthSyncState = .skipped
    }

    /// Apply the analyzer results to the editable fields.
    private func applyAnalysisToFields(_ analysis: FitnessAnalysis) {
        currentWeeklyMiles = analysis.averageWeeklyMiles
        selectedFitnessLevel = analysis.fitnessLevel
        longestRunMiles = analysis.longestRunMiles
        runsPerWeekDisplay = analysis.runsPerWeek

        // Convert zone2 pace (sec/mile) to display values in user's preferred unit
        if analysis.estimatedZone2PaceSecPerMile > 0 {
            let displaySec: Int
            switch selectedUnitSystem {
            case .miles:
                displaySec = analysis.estimatedZone2PaceSecPerMile
            case .kilometers:
                displaySec = Int(Double(analysis.estimatedZone2PaceSecPerMile) / 1.60934)
            }
            zone2PaceMinutes = displaySec / 60
            zone2PaceSeconds = displaySec % 60
        }

        // Pre-fill schedule from detected patterns
        if let longRunDay = analysis.likelyLongRunDay {
            preferredLongRunDay = longRunDay
        }
        if !analysis.likelyRestDays.isEmpty {
            selectedRestDays = Set(analysis.likelyRestDays)
            // Ensure long run day isn't a rest day
            selectedRestDays.remove(preferredLongRunDay)
        }
        if !analysis.preferredRunDays.isEmpty {
            trainingDaysPerWeek = min(5, max(3, Int(analysis.runsPerWeek.rounded())))
        }
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

        // Persist historical runs if we have them
        if !historicalRunData.isEmpty {
            let service = HistoricalRunService(modelContext: modelContext)
            service.persist(historicalRunData)
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
        if hasRecentRaceTime {
            profile.recentRaceTime = RaceTime(
                raceDistance: recentRaceType,
                finishTimeSeconds: recentRaceHours * 3600 + recentRaceMinutes * 60 + recentRaceSeconds,
                raceDate: Date()
            )
        }
        profile.longestRecentRunMiles = longestRunMiles
        profile.recentRuns = recentRuns
        return profile
    }

    private func buildFinalProfile() -> UserProfile {
        buildTemporaryProfile()
    }
}
