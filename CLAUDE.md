# Stride — Claude Development Guide

## Project Overview
Stride is a Swift/SwiftUI iOS running app for training plan management. It generates personalised training plans based on race type, race date, fitness level, and schedule preferences. The primary user is a runner training for a marathon (~90 days out), but the app supports 5K, 10K, Half Marathon, and Full Marathon for all levels.

**Distribution:** TestFlight
**Platform:** iOS 18+ (iPhone only; watchOS is a v2 goal)

---

## Build Configuration
- **Build simulator:** Always use `iPhone 17 Pro` as the destination simulator. Never use any other device.
  ```
  xcodebuild -scheme Stride -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
  ```

---

## Tech Stack
- **Language:** Swift 5.10+
- **UI:** SwiftUI (no UIKit)
- **State management:** `@Observable` macro (NOT `ObservableObject`)
- **Persistence:** SwiftData (`@Model` classes)
- **Health:** HealthKit (read-only, passive post-run sync)
- **Maps & Location:** MapKit + CoreLocation (route planning, MKDirections for road-snapped routes)
- **Notifications:** `UserNotifications` framework (local only, no push server)
- **Xcode:** 16+
- **No custom backend.** Native Apple API network calls (MapKit, HealthKit, etc.) are fine.
- **Third-party packages (SPM):** Allowed on a case-by-case basis. Prefer native frameworks when they cover the need. Justify any new dependency before adding it.

---

## Architecture: MVVM

Every feature follows strict MVVM:
- **Views** are pure layout — no business logic, no direct model access
- **ViewModels** are `@Observable` classes — own all state, all logic
- **Models** are SwiftData `@Model` classes — data only, no logic
- **Services** are plain Swift classes/actors — injected into ViewModels

```
View → ViewModel → Services → Models (SwiftData)
```

### Dependency injection
Pass services down via the environment or initialiser. Never instantiate services inside a View.

```swift
// Good
@State private var viewModel = DashboardViewModel(planService: planService)

// Bad — never do this inside a View
let generator = TrainingPlanGenerator()
```

---

## Project Folder Structure

```
Stride/
├── StrideApp.swift                  # App entry, SwiftData container, env setup
├── ContentView.swift                # Root navigation (TabView + FAB)
├── Assets.xcassets
├── Info.plist
│
├── Core/
│   ├── Models/                      # SwiftData @Model classes + value types
│   │   ├── Models.swift             # UserProfile, TrainingPlan, WorkoutDay, WorkoutLog,
│   │   │                            #   HistoricalRun, enums (RaceType, WorkoutType, etc.)
│   │   ├── ReadinessCheck.swift     # Daily readiness assessment model
│   │   └── AdaptationRecord.swift   # Plan adaptation history
│   │
│   ├── Services/
│   │   ├── TrainingPlanGenerator.swift    # Plan generation algorithm
│   │   ├── HealthKitManager.swift         # HealthKit read-only integration
│   │   ├── NotificationManager.swift      # Local notification scheduling
│   │   ├── FinishTimeEstimator.swift      # Riegel formula projections
│   │   ├── PlanAdaptationEngine.swift     # Adaptive plan adjustments
│   │   ├── ReadinessEngine.swift          # Daily readiness scoring
│   │   ├── RunningFitnessAnalyzer.swift   # Fitness analysis
│   │   ├── HistoricalRunService.swift     # Historical run tracking
│   │   ├── WorkoutAdjustmentService.swift # Workout modifications
│   │   └── DateProvider.swift             # Date abstraction (supports time-travel debugging)
│   │
│   └── Extensions/
│       └── Double+Formatting.swift
│
├── UI/
│   ├── DesignSystem.swift           # Colors, fonts, gradients — single source of truth
│   └── Components/
│       ├── GlassCard.swift          # Reusable glassmorphism card
│       └── StrideButton.swift       # Primary/secondary button styles
│
└── Features/
    ├── Onboarding/
    │   ├── OnboardingView.swift
    │   ├── OnboardingViewModel.swift
    │   └── Steps/
    │       ├── WelcomeStepView.swift
    │       ├── RaceSetupStepView.swift
    │       ├── FitnessProfileStepView.swift
    │       ├── ScheduleStepView.swift
    │       ├── HealthSyncStepView.swift
    │       ├── PlanPreviewStepView.swift
    │       └── OnboardingComponents.swift
    │
    ├── Dashboard/
    │   ├── DashboardView.swift
    │   ├── DashboardViewModel.swift
    │   └── Components/
    │       ├── AdaptationBannerCard.swift
    │       └── AdaptationDetailView.swift
    │
    ├── Calendar/
    │   └── TrainingCalendarView.swift
    │
    ├── Workout/
    │   ├── WorkoutDetailView.swift
    │   ├── WorkoutDetailViewModel.swift
    │   └── LogWorkoutView.swift
    │
    ├── Progress/
    │   └── StatsView.swift          # Named StatsView to avoid SwiftUI ProgressView conflict
    │
    ├── ReadyCheck/
    │   ├── ReadyCheckView.swift
    │   └── ReadyCheckViewModel.swift
    │
    ├── Profile/
    │   ├── ProfileView.swift
    │   └── ProfileViewModel.swift
    │
    └── Debug/                       # Debug-only tools
        ├── DebugTimeTravelView.swift
        └── MockHealthKitManager.swift
```

---

## Navigation

Root structure: `TabView` with 4 tabs + a floating action button (FAB) for logging.

```
TabView
├── Tab 1: Dashboard  (house.fill)
├── Tab 2: Plan       (calendar)
├── Tab 3: Progress   (chart.bar.fill)
├── Tab 4: Profile    (person.circle.fill)
└── FAB overlay: "Log Workout" (plus.circle.fill) — floats above tab bar, home tab only
```

- Use `NavigationStack` inside each tab (not `NavigationView`)
- Sheets for: workout detail, log workout, onboarding (full-screen cover)
- `fullScreenCover` for onboarding only — shown on first launch

---

## Data Model Summary

```
UserProfile (1)
  └── TrainingPlan (1)                — .activePlan, cascade delete
        └── WorkoutDay[] (N)          — one per calendar day across the full plan
              └── WorkoutLog?         — nil until completed

HistoricalRun (N)                     — imported from HealthKit, standalone
ReadinessCheck (N)                    — daily readiness assessments
AdaptationRecord (N)                  — plan adaptation history
```

See `docs/ARCHITECTURE.md` for full SwiftData schema.

---

## Key Patterns

### ViewModels use @Observable
```swift
@Observable
final class DashboardViewModel {
    var todayWorkout: WorkoutDay?
    var weeklyMiles: Double = 0
    // ...
}
```

### Views inject ViewModel via @State
```swift
struct DashboardView: View {
    @State private var viewModel = DashboardViewModel()
    // ...
}
```

### SwiftData access in ViewModels (not in Views)
```swift
// Pass modelContext into the ViewModel
final class DashboardViewModel {
    private let modelContext: ModelContext
    init(modelContext: ModelContext) { self.modelContext = modelContext }
}
```

---

## Design System Rules
- **Primary colour:** `#DAC3E8` (pastel lavender)
- **Background:** soft lavender → white gradient
- **Cards:** glassmorphism — `.ultraThinMaterial` + subtle lavender tint + rounded corners (20pt)
- **Typography:** SF Pro (system font) — never custom fonts unless specified
- **Spacing:** 16pt base unit, multiples of 8
- **Never** use hard-coded hex values in Views — always use `Color.stride.*` from `DesignSystem.swift`
- **Never** add emoji to UI unless explicitly listed in the design spec

---

## HealthKit Integration Rules
- Request authorisation on first launch (after onboarding)
- **Read only:** `HKWorkoutType`, `HKQuantityType.distanceWalkingRunning`, `HKQuantityType.heartRate`
- Query the last 24h of workouts when the app foregrounds
- Match HealthKit workout to today's planned WorkoutDay by date
- Pre-fill log form with HealthKit data; user confirms before saving
- Never write to HealthKit

---

## Notifications Rules
- Request permission after onboarding completes
- All notifications are **local** (no APNs server)
- Three types: daily reminder, weekly summary (Sunday 8pm), motivational nudge (after missed workout, 48h grace period)
- Let user configure daily reminder time in Settings
- Cancel/reschedule all notifications when plan changes

---

## Training Plan Rules
- See `docs/TRAINING_PLAN_LOGIC.md` for full algorithm
- Never mutate `WorkoutDay` objects after the plan is generated — only `WorkoutLog` is mutable
- Plan regeneration creates a new `TrainingPlan` and soft-deletes the old one
- The 10% weekly mileage increase rule is a hard cap in the generator

---

## Known Naming Notes
- The Progress tab view is named `StatsView` (not `ProgressView`) — `ProgressView` is a built-in SwiftUI component and causes a naming conflict.
- `ConfettiOverlay` is implemented as a Canvas particle system in the UI layer.

---

## What NOT to do
- No UIKit — SwiftUI only
- No `ObservableObject` / `@Published` — use `@Observable` macro
- No global singletons — inject dependencies
- No force unwraps (`!`) — use `guard`, `if let`, or `??`
- No `NavigationView` — use `NavigationStack`
- No hardcoded strings in UI — define workout type names as enums
- No custom backend or server-side networking — native Apple API calls only
- No SPM packages without justification — prefer native frameworks first
