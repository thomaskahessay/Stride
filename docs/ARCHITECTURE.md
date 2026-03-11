# Stride — Technical Architecture

**Version:** 1.0
**Stack:** Swift 5.10 / SwiftUI / SwiftData / iOS 18+

---

## 1. Architectural Pattern: MVVM

```
┌──────────┐     binds to      ┌────────────────┐     calls      ┌──────────────┐
│   View   │ ────────────────► │  ViewModel     │ ─────────────► │   Service    │
│ (SwiftUI)│                   │ (@Observable)  │                │  (Swift cls) │
└──────────┘                   └────────────────┘                └──────────────┘
                                       │                                │
                                  reads/writes                    reads/writes
                                       │                                │
                                       ▼                                ▼
                               ┌──────────────┐              ┌──────────────────┐
                               │  SwiftData   │              │   HealthKit /    │
                               │  ModelContext│              │  Notifications   │
                               └──────────────┘              └──────────────────┘
```

### Rules
- Views contain **no logic** — only layout and bindings
- ViewModels are `@Observable` — use `@State private var vm = VM()` in views
- Services are pure Swift classes — no SwiftUI imports
- ModelContext is passed into ViewModels (not accessed from Views directly)

---

## 2. SwiftData Schema

### UserProfile
```swift
@Model final class UserProfile {
    var id: UUID
    var firstName: String
    var raceType: RaceType              // enum: fiveK, tenK, halfMarathon, fullMarathon
    var raceDate: Date
    var fitnessLevel: FitnessLevel      // enum: beginner, intermediate, advanced
    var currentWeeklyMiles: Double      // miles per week at time of onboarding
    var trainingDaysPerWeek: Int        // 3, 4, or 5
    var preferredLongRunDay: Weekday    // enum: sunday, saturday, etc.
    var restDays: [Weekday]
    var recentRaceTime: RaceTime?       // optional — for Riegel projection
    var unitPreference: UnitSystem      // enum: miles, kilometers
    var onboardingComplete: Bool
    var createdAt: Date

    // Relationships
    @Relationship(deleteRule: .cascade)
    var activePlan: TrainingPlan?
}
```

### TrainingPlan
```swift
@Model final class TrainingPlan {
    var id: UUID
    var generatedAt: Date
    var planStartDate: Date             // first day of training (week 1 day 1)
    var raceDate: Date
    var totalWeeks: Int
    var entryWeek: Int                  // which week the user started at (1-based)
    var isActive: Bool

    @Relationship(deleteRule: .cascade)
    var workoutDays: [WorkoutDay]

    // Computed
    var currentWeekNumber: Int          // derived from today vs planStartDate
    var completionPercentage: Double    // completed / total scheduled
}
```

### WorkoutDay
```swift
@Model final class WorkoutDay {
    var id: UUID
    var date: Date                      // the calendar date this workout is scheduled
    var weekNumber: Int                 // 1-based week within the plan
    var dayOfWeek: Weekday
    var workoutType: WorkoutType        // see enum below
    var targetDistanceMiles: Double     // 0 for rest/strength days
    var targetDurationMinutes: Int
    var effortLevel: EffortLevel        // easy, moderate, hard, maxEffort
    var workoutTitle: String            // e.g. "Tempo Run", "20-Mile Long Run"
    var coachingNote: String            // plain language explanation
    var steps: [WorkoutStep]            // structured breakdown (warmup, main, cooldown)
    var isCompleted: Bool
    var isSkipped: Bool

    @Relationship(deleteRule: .cascade)
    var log: WorkoutLog?
}
```

### WorkoutStep
```swift
// Embedded value type (not a @Model — stored as JSON in WorkoutDay)
struct WorkoutStep: Codable {
    var order: Int
    var label: String           // e.g. "Warm-up", "Main Set", "Cool-down"
    var distanceMiles: Double?
    var durationMinutes: Int?
    var description: String     // e.g. "Easy jog at conversational pace"
}
```

### WorkoutLog
```swift
@Model final class WorkoutLog {
    var id: UUID
    var loggedAt: Date
    var actualDistanceMiles: Double
    var actualDurationSeconds: Int
    var effortRating: Int               // RPE 1–10
    var notes: String
    var sourceHealthKit: Bool           // was this pre-filled from HealthKit?
    var averageHeartRate: Double?       // from HealthKit if available
}
```

### RaceTime (value type)
```swift
struct RaceTime: Codable {
    var raceDistance: RaceType
    var finishTimeSeconds: Int          // total seconds
    var raceDate: Date
}
```

---

## 3. Enumerations

```swift
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

    var standardPlanWeeks: Int {
        switch self {
        case .fiveK: return 8
        case .tenK: return 10
        case .halfMarathon: return 14
        case .fullMarathon: return 18
        }
    }
}

enum WorkoutType: String, Codable {
    case easyRun = "Easy Run"
    case longRun = "Long Run"
    case tempoRun = "Tempo Run"
    case intervalRun = "Intervals"
    case strengthDay = "Strength Day"
    case restDay = "Rest Day"
    case recoveryRun = "Recovery Run"

    var accentColor: String {       // maps to Color.stride.* in DesignSystem
        switch self {
        case .easyRun: return "mint"
        case .longRun: return "lavender"
        case .tempoRun: return "orange"
        case .intervalRun: return "red"
        case .strengthDay: return "blue"
        case .restDay: return "gray"
        case .recoveryRun: return "green"
        }
    }
}

enum FitnessLevel: String, Codable, CaseIterable {
    case beginner = "Beginner"
    case intermediate = "Intermediate"
    case advanced = "Advanced"
}

enum EffortLevel: String, Codable {
    case easy = "Easy"
    case moderate = "Moderate"
    case hard = "Hard"
    case maxEffort = "Max Effort"

    var description: String {
        switch self {
        case .easy: return "Conversational pace — you can speak in full sentences"
        case .moderate: return "Comfortably hard — short sentences only"
        case .hard: return "Very hard — breathing heavily, few words"
        case .maxEffort: return "All out — race pace or faster"
        }
    }
}

enum Weekday: Int, Codable, CaseIterable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday
}

enum UnitSystem: String, Codable {
    case miles, kilometers
}
```

---

## 4. Service Layer

### TrainingPlanGenerator
Generates the full `[WorkoutDay]` array from a `UserProfile`.

**Inputs:** `UserProfile`
**Output:** `TrainingPlan` with populated `workoutDays`

Key responsibilities:
- Determine total plan weeks from race type + user fitness
- Calculate `planStartDate` from race date − plan length
- Determine `entryWeek` (which week maps to today's date)
- Build week-by-week mileage progression (10% rule, phases)
- Assign workout types per day respecting rest days and long run day
- Generate `WorkoutStep` arrays for each run day
- Generate coaching notes per workout type and week

See `docs/TRAINING_PLAN_LOGIC.md` for full algorithm.

### HealthKitManager
Manages all HealthKit interaction.

**Authorisation:** request read permissions on first launch
**Query:** on app foreground, fetch `HKWorkout` objects for running in the last 48h
**Match:** compare workout date to open `WorkoutDay` objects
**Return:** `HealthKitWorkoutData` struct with distance, duration, heartRate

```swift
struct HealthKitWorkoutData {
    let workoutDate: Date
    let distanceMiles: Double
    let durationSeconds: Int
    let averageHeartRate: Double?
}
```

### NotificationManager
Schedules and manages all local notifications.

**Daily reminder:** `UNCalendarNotificationTrigger` at user-set time, repeats daily
**Weekly summary:** every Sunday at 20:00 — calculates weekly stats from SwiftData
**Missed workout nudge:** checks 48h after each scheduled workout day — if no log exists, fires nudge

### FinishTimeEstimator
Implements the Riegel formula for race time projection.

```
T2 = T1 × (D2 / D1)^1.06
```

Where:
- `T1` = known finish time (e.g. 5K = 25:00)
- `D1` = known race distance
- `D2` = target race distance
- `T2` = projected finish time

---

## 5. Navigation Flow

```
App Launch
    │
    ├─ First launch → fullScreenCover: OnboardingView
    │       └─ Complete → generate plan → dismiss → ContentView
    │
    └─ Returning → ContentView (TabView)
            ├─ Tab 1: DashboardView
            │       └─ Tap workout → sheet: WorkoutDetailView
            │               └─ Tap "Log" → sheet: LogWorkoutView
            │
            ├─ Tab 2: TrainingCalendarView
            │       └─ Tap day → sheet: WorkoutDetailView
            │
            ├─ Tab 3: ProgressView
            │       └─ Tap finish time card → sheet: AddTimeTrialView
            │
            ├─ Tab 4: ProfileView
            │       └─ Tap Settings → NavigationStack push: SettingsView
            │
            └─ FAB (floating) → sheet: LogWorkoutView (for today)
```

---

## 6. State Management

### App-level state
`StrideApp.swift` holds the `ModelContainer` and checks `UserProfile.onboardingComplete` to decide whether to show onboarding.

```swift
@main
struct StrideApp: App {
    let container: ModelContainer
    @State private var showOnboarding = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(container)
                .fullScreenCover(isPresented: $showOnboarding) {
                    OnboardingView()
                }
                .onAppear { checkOnboarding() }
        }
    }
}
```

### HealthKit trigger
`HealthKitManager.shared.fetchRecentWorkouts()` is called in `.onAppear` of `ContentView` and posts results to a `@Observable` store that ViewModels subscribe to.

---

## 7. HealthKit Permission Manifest (Info.plist)

Add these keys to `Info.plist`:
```xml
<key>NSHealthShareUsageDescription</key>
<string>Stride reads your running workouts to automatically fill in your training log.</string>
<key>NSHealthUpdateUsageDescription</key>
<string>Stride does not write health data.</string>
```

And add `HealthKit` capability in Xcode project settings.

---

## 8. iCloud Readiness (v2)

SwiftData supports CloudKit sync with minimal changes. To enable in v2:
1. Add `iCloud` capability + CloudKit container (`iCloud.com.stride.app`)
2. Change `ModelContainer` initialisation to include `CloudKitDatabase`
3. All `@Model` classes must use optional relationships (already designed this way)

No changes needed to model classes — they're CloudKit-compatible from day one.

---

## 9. Testing Strategy

- **Unit tests:** `TrainingPlanGenerator`, `FinishTimeEstimator` — pure logic, no UI
- **UI tests:** Onboarding flow end-to-end, log workout flow
- **Manual:** HealthKit integration (requires device), notifications (requires device)

No snapshot tests for v1 — move fast.
