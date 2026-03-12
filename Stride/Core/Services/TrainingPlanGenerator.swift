import Foundation

/// Generates a complete day-by-day TrainingPlan from a UserProfile.
/// See docs/TRAINING_PLAN_LOGIC.md for the full algorithm specification.
final class TrainingPlanGenerator {

    // MARK: - Public API

    func generate(from profile: UserProfile) -> TrainingPlan {
        let totalWeeks = planLength(for: profile.raceType, level: profile.fitnessLevel)
        let planStartDate = planStart(raceDate: profile.raceDate, totalWeeks: totalWeeks)
        let suggestedEntry = suggestedEntryWeek(planStartDate: planStartDate)
        let entryWeek = max(1, min(totalWeeks, suggestedEntry))

        let plan = TrainingPlan(
            planStartDate: planStartDate,
            raceDate: profile.raceDate,
            totalWeeks: totalWeeks,
            entryWeek: entryWeek
        )

        let paceZones = calculatePaceZones(profile: profile)
        plan.paceZones = paceZones

        let mileageByWeek = weeklyMileageProgression(
            profile: profile,
            totalWeeks: totalWeeks
        )

        let days = buildWorkoutDays(
            profile: profile,
            plan: plan,
            mileageByWeek: mileageByWeek,
            paceZones: paceZones
        )

        plan.workoutDays = days
        return plan
    }

    // MARK: - Pace Zone Calculator

    private func calculatePaceZones(profile: UserProfile) -> PaceZones? {
        guard profile.zone2PaceSecondsPerMile > 0 else { return nil }
        return PaceZones.from(
            zone2SecPerMile: profile.zone2PaceSecondsPerMile,
            goalTimeSeconds: profile.goalFinishTimeSeconds,
            raceType: profile.raceType
        )
    }

    // MARK: - Plan Length

    func planLength(for raceType: RaceType, level: FitnessLevel) -> Int {
        switch (raceType, level) {
        case (.fiveK, .beginner): return 8
        case (.fiveK, .intermediate): return 8
        case (.fiveK, .advanced): return 6
        case (.tenK, .beginner): return 10
        case (.tenK, .intermediate): return 10
        case (.tenK, .advanced): return 8
        case (.halfMarathon, .beginner): return 16
        case (.halfMarathon, .intermediate): return 14
        case (.halfMarathon, .advanced): return 12
        case (.fullMarathon, .beginner): return 20
        case (.fullMarathon, .intermediate): return 18
        case (.fullMarathon, .advanced): return 16
        }
    }

    // MARK: - Plan Start Date

    func planStart(raceDate: Date, totalWeeks: Int) -> Date {
        Calendar.current.date(
            byAdding: .weekOfYear,
            value: -totalWeeks,
            to: raceDate
        ) ?? raceDate
    }

    // MARK: - Suggested Entry Week

    func suggestedEntryWeek(planStartDate: Date) -> Int {
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: planStartDate),
            to: Calendar.current.startOfDay(for: Date())
        ).day ?? 0
        return max(1, (days / 7) + 1)
    }


    // MARK: - Weekly Mileage Progression

    func weeklyMileageProgression(profile: UserProfile, totalWeeks: Int) -> [Int: Double] {
        let startMiles = startingMileage(profile: profile)
        let peakMiles = peakMileage(for: profile.raceType, level: profile.fitnessLevel)
        let taperWeeks = taperLength(for: profile.raceType)
        let buildWeeks = totalWeeks - taperWeeks

        var mileage: [Int: Double] = [:]
        var current = startMiles

        for week in 1...totalWeeks {
            if week > buildWeeks {
                // Taper phase
                let taperWeek = week - buildWeeks
                let taperMultiplier = taperFactor(week: taperWeek, total: taperWeeks)
                mileage[week] = peakMiles * taperMultiplier
            } else if week % 4 == 0 {
                // Recovery week every 4th week
                mileage[week] = current * 0.80
            } else {
                mileage[week] = current
                // Progress toward peak, capped at 10%
                let next = current * 1.10
                current = min(next, peakMiles)
            }
        }

        return mileage
    }

    private func startingMileage(profile: UserProfile) -> Double {
        let levelBase: Double
        switch (profile.raceType, profile.fitnessLevel) {
        case (.fiveK, .beginner): levelBase = 8
        case (.fiveK, .intermediate): levelBase = 15
        case (.fiveK, .advanced): levelBase = 25
        case (.tenK, .beginner): levelBase = 10
        case (.tenK, .intermediate): levelBase = 20
        case (.tenK, .advanced): levelBase = 30
        case (.halfMarathon, .beginner): levelBase = 15
        case (.halfMarathon, .intermediate): levelBase = 25
        case (.halfMarathon, .advanced): levelBase = 35
        case (.fullMarathon, .beginner): levelBase = 20
        case (.fullMarathon, .intermediate): levelBase = 30
        case (.fullMarathon, .advanced): levelBase = 40
        }
        // Don't shock a runner already above the level base
        return max(levelBase, profile.currentWeeklyMiles * 0.9)
    }

    private func peakMileage(for race: RaceType, level: FitnessLevel) -> Double {
        switch (race, level) {
        case (.fiveK, .beginner): return 25
        case (.fiveK, .intermediate): return 35
        case (.fiveK, .advanced): return 45
        case (.tenK, .beginner): return 30
        case (.tenK, .intermediate): return 40
        case (.tenK, .advanced): return 55
        case (.halfMarathon, .beginner): return 35
        case (.halfMarathon, .intermediate): return 45
        case (.halfMarathon, .advanced): return 60
        case (.fullMarathon, .beginner): return 40
        case (.fullMarathon, .intermediate): return 55
        case (.fullMarathon, .advanced): return 70
        }
    }

    private func taperLength(for race: RaceType) -> Int {
        switch race {
        case .fiveK, .tenK: return 2
        case .halfMarathon: return 2
        case .fullMarathon: return 3
        }
    }

    private func taperFactor(week: Int, total: Int) -> Double {
        switch (week, total) {
        case (1, _): return 0.75
        case (2, 2): return 0.40
        case (2, 3): return 0.60
        case (3, 3): return 0.40
        default: return 0.40
        }
    }

    // MARK: - Build Workout Days

    private func buildWorkoutDays(
        profile: UserProfile,
        plan: TrainingPlan,
        mileageByWeek: [Int: Double],
        paceZones: PaceZones?
    ) -> [WorkoutDay] {
        var days: [WorkoutDay] = []
        let calendar = Calendar.current

        for week in 1...plan.totalWeeks {
            let weekStartOffset = (week - 1) * 7
            let weekMiles = mileageByWeek[week] ?? 0
            let phase = trainingPhase(week: week, total: plan.totalWeeks)

            // Collect all dates + weekdays for this 7-day window
            var weekDays: [(date: Date, weekday: Weekday)] = []
            for dayInWeek in 0..<7 {
                guard let date = calendar.date(
                    byAdding: .day,
                    value: weekStartOffset + dayInWeek,
                    to: plan.planStartDate
                ) else { continue }
                let weekdayRaw = calendar.component(.weekday, from: date)
                guard let weekday = Weekday(rawValue: weekdayRaw) else { continue }
                weekDays.append((date, weekday))
            }

            // --- Slot budget ---
            // 1. Long run: always 1 slot (on preferredLongRunDay)
            // 2. Quality run: 1 slot in build/peak, on the first available midweek day
            // 3. Strength: 1 slot in base/build, from the remaining slots after quality
            // 4. Easy runs: fill the rest up to trainingDaysPerWeek
            // All other days become rest.

            let midweekDays: [Weekday] = [.tuesday, .wednesday, .thursday]
            let qualityWeekday: Weekday? = (phase == .build || phase == .peak)
                ? midweekDays.first {
                    !profile.restDays.contains($0) && $0 != profile.preferredLongRunDay
                }
                : nil

            // Running slots: trainingDaysPerWeek covers long run + quality + easy runs only
            let easyRunSlots = max(0, profile.trainingDaysPerWeek
                - 1
                - (qualityWeekday != nil ? 1 : 0))
            var easyRunWeekdays: Set<Weekday> = []
            var easyCount = 0
            for (_, weekday) in weekDays {
                guard easyCount < easyRunSlots else { break }
                if !profile.restDays.contains(weekday)
                    && weekday != profile.preferredLongRunDay
                    && weekday != qualityWeekday {
                    easyRunWeekdays.insert(weekday)
                    easyCount += 1
                }
            }

            // Strength is an additional day on top of trainingDaysPerWeek (base/build only).
            // Place it on the first free day that isn't a rest, run, or quality day.
            let strengthWeekday: Weekday? = (phase == .base || phase == .build)
                ? weekDays.map(\.weekday).first {
                    !profile.restDays.contains($0)
                        && $0 != profile.preferredLongRunDay
                        && $0 != qualityWeekday
                        && !easyRunWeekdays.contains($0)
                }
                : nil

            // Build each day using the pre-determined slot assignments
            for (date, weekday) in weekDays {
                let workoutDay: WorkoutDay

                if profile.restDays.contains(weekday) {
                    workoutDay = makeRestDay(date: date, weekNumber: week, weekday: weekday)
                } else if weekday == profile.preferredLongRunDay {
                    workoutDay = makeLongRunDay(
                        date: date, weekNumber: week, weekday: weekday,
                        weeklyMiles: weekMiles, profile: profile,
                        phase: phase, paceZones: paceZones
                    )
                } else if weekday == qualityWeekday {
                    workoutDay = week % 2 == 0
                        ? makeTempoDay(date: date, weekNumber: week, weekday: weekday,
                                       weeklyMiles: weekMiles, profile: profile, paceZones: paceZones)
                        : makeIntervalDay(date: date, weekNumber: week, weekday: weekday,
                                          weeklyMiles: weekMiles, profile: profile, paceZones: paceZones)
                } else if weekday == strengthWeekday {
                    workoutDay = makeStrengthDay(date: date, weekNumber: week, weekday: weekday)
                } else if easyRunWeekdays.contains(weekday) {
                    workoutDay = makeEasyRunDay(
                        date: date, weekNumber: week, weekday: weekday,
                        weeklyMiles: weekMiles, profile: profile, paceZones: paceZones
                    )
                } else {
                    workoutDay = makeRestDay(date: date, weekNumber: week, weekday: weekday)
                }

                days.append(workoutDay)
            }
        }

        return days
    }

    private func trainingPhase(week: Int, total: Int) -> TrainingPhase {
        let base = Int(Double(total) * 0.30)
        let build = Int(Double(total) * 0.65)
        let peak = Int(Double(total) * 0.85)

        if week <= base { return .base }
        else if week <= build { return .build }
        else if week <= peak { return .peak }
        else { return .taper }
    }

    // MARK: - Workout Factories

    private func makeRestDay(date: Date, weekNumber: Int, weekday: Weekday) -> WorkoutDay {
        WorkoutDay(
            date: date,
            weekNumber: weekNumber,
            dayOfWeek: weekday,
            workoutType: .restDay,
            workoutTitle: "Rest Day",
            coachingNote: "Rest is training. Your body adapts and gets stronger during recovery, not during the run. Sleep well, eat well, and keep your feet up where possible.",
            steps: []
        )
    }

    private func makeEasyRunDay(
        date: Date,
        weekNumber: Int,
        weekday: Weekday,
        weeklyMiles: Double,
        profile: UserProfile,
        paceZones: PaceZones?
    ) -> WorkoutDay {
        let distance = max(3.0, weeklyMiles * 0.20)
        let duration = estimatedDuration(miles: distance, paceSecPerMile: paceZones?.easyPaceSecPerMile, fallbackMph: 5.5)

        let steps: [WorkoutStep] = [
            WorkoutStep(order: 1, label: "Warm-up", durationMinutes: 5,
                        description: "5 minutes of brisk walking or very slow jogging",
                        targetPaceSecPerMile: paceZones?.recoveryPaceSecPerMile),
            WorkoutStep(order: 2, label: "Easy Run", distanceMiles: distance,
                        description: "Run at a fully conversational pace — if you can't speak full sentences, slow down",
                        targetPaceSecPerMile: paceZones?.easyPaceSecPerMile),
            WorkoutStep(order: 3, label: "Cool-down", durationMinutes: 5,
                        description: "5 minutes walking + light calf and hip flexor stretches")
        ]

        return WorkoutDay(
            date: date,
            weekNumber: weekNumber,
            dayOfWeek: weekday,
            workoutType: .easyRun,
            targetDistanceMiles: distance,
            targetDurationMinutes: duration,
            targetPaceSecPerMile: paceZones?.easyPaceSecPerMile,
            effortLevel: .easy,
            workoutTitle: "Easy Run",
            coachingNote: "Today is about recovery and building your aerobic base. Run slow enough to hold a conversation. Don't worry about pace — your easy runs make your hard runs possible.",
            steps: steps
        )
    }

    private func makeLongRunDay(
        date: Date,
        weekNumber: Int,
        weekday: Weekday,
        weeklyMiles: Double,
        profile: UserProfile,
        phase: TrainingPhase,
        paceZones: PaceZones?
    ) -> WorkoutDay {
        let distance = longRunDistance(weekNumber: weekNumber, profile: profile)
        let duration = estimatedDuration(miles: distance, paceSecPerMile: paceZones?.longRunPaceSecPerMile, fallbackMph: 5.0)

        let coachingNote = phase == .peak
            ? "This is a peak long run — one of the most important sessions in your plan. Run the first two-thirds easy, then pick up slightly for the final miles. This teaches your body to run strong on tired legs."
            : "Your long run this week is all about time on feet. Run at a pace where you can chat comfortably. Finish feeling like you had more in the tank."

        let units = profile.unitPreference
        let warmupLabel = units == .kilometers ? "Warm-up km" : "Warm-up Mile"
        let warmupDesc = units == .kilometers
            ? "First km very easy — let the body wake up"
            : "First mile very easy — let the body wake up"
        let displayDist = String(format: "%.1f", units.convert(distance))
        let longRunTitle = "\(displayDist) \(units.shortLabel) Long Run"

        // Peak phase: final miles at race pace to simulate race fatigue
        let finalMilePace = phase == .peak ? paceZones?.racePaceSecPerMile : paceZones?.longRunPaceSecPerMile
        let finalMileDesc = phase == .peak
            ? "Final 2 miles at goal race pace — simulate race day on tired legs."
            : "Keep the effort steady and comfortable. Don't race the final miles."

        let steps: [WorkoutStep] = [
            WorkoutStep(order: 1, label: warmupLabel, distanceMiles: 1.0,
                        description: warmupDesc,
                        targetPaceSecPerMile: paceZones?.easyPaceSecPerMile),
            WorkoutStep(order: 2, label: "Long Run", distanceMiles: max(distance - 3.0, distance * 0.85),
                        description: "Settle into your easy aerobic pace. Focus on consistent effort, not pace.",
                        targetPaceSecPerMile: paceZones?.longRunPaceSecPerMile),
            WorkoutStep(order: 3, label: "Final Miles", distanceMiles: phase == .peak ? 2.0 : distance * 0.10,
                        description: finalMileDesc,
                        targetPaceSecPerMile: finalMilePace),
            WorkoutStep(order: 4, label: "Cool-down", durationMinutes: 10,
                        description: "10 minutes walking, then full leg stretching routine — quads, hamstrings, calves, hips")
        ]

        return WorkoutDay(
            date: date,
            weekNumber: weekNumber,
            dayOfWeek: weekday,
            workoutType: .longRun,
            targetDistanceMiles: distance,
            targetDurationMinutes: duration,
            targetPaceSecPerMile: paceZones?.longRunPaceSecPerMile,
            effortLevel: .easy,
            workoutTitle: longRunTitle,
            coachingNote: coachingNote,
            steps: steps
        )
    }

    private func makeTempoDay(
        date: Date,
        weekNumber: Int,
        weekday: Weekday,
        weeklyMiles: Double,
        profile: UserProfile,
        paceZones: PaceZones?
    ) -> WorkoutDay {
        let tempoMiles = max(2.0, weeklyMiles * 0.15)
        let totalDistance = tempoMiles + 2.0 // +1mi warmup +1mi cooldown
        let duration = estimatedDuration(miles: totalDistance, paceSecPerMile: paceZones?.tempoPaceSecPerMile, fallbackMph: 7.0)

        let unitLabel = profile.unitPreference == .kilometers ? "km" : "mile"
        let steps: [WorkoutStep] = [
            WorkoutStep(order: 1, label: "Warm-up", distanceMiles: 1.0,
                        description: "1 \(unitLabel) easy jog to raise heart rate gradually",
                        targetPaceSecPerMile: paceZones?.easyPaceSecPerMile),
            WorkoutStep(order: 2, label: "Tempo Effort", distanceMiles: tempoMiles,
                        description: "Comfortably hard pace — you can speak a few words, not full sentences. This is your lactate threshold effort.",
                        targetPaceSecPerMile: paceZones?.tempoPaceSecPerMile),
            WorkoutStep(order: 3, label: "Cool-down", distanceMiles: 1.0,
                        description: "1 \(unitLabel) easy jog to flush out the lactate",
                        targetPaceSecPerMile: paceZones?.easyPaceSecPerMile)
        ]

        return WorkoutDay(
            date: date,
            weekNumber: weekNumber,
            dayOfWeek: weekday,
            workoutType: .tempoRun,
            targetDistanceMiles: totalDistance,
            targetDurationMinutes: duration,
            targetPaceSecPerMile: paceZones?.tempoPaceSecPerMile,
            effortLevel: .moderate,
            workoutTitle: "Tempo Run",
            coachingNote: "Tempo runs build your lactate threshold — the pace you can sustain for a long time. Aim for 'comfortably hard'. The effort should feel controlled, not desperate.",
            steps: steps
        )
    }

    private func makeIntervalDay(
        date: Date,
        weekNumber: Int,
        weekday: Weekday,
        weeklyMiles: Double,
        profile: UserProfile,
        paceZones: PaceZones?
    ) -> WorkoutDay {
        // 6 × 800m intervals as a standard workout
        let intervalCount = 6
        let repDistanceMiles = 0.5 // 800m
        let totalDistance = 2.0 + Double(intervalCount) * repDistanceMiles
        let duration = estimatedDuration(miles: totalDistance, paceSecPerMile: paceZones?.intervalPaceSecPerMile, fallbackMph: 6.5)

        let unitLabel = profile.unitPreference == .kilometers ? "km" : "mile"
        let steps: [WorkoutStep] = [
            WorkoutStep(order: 1, label: "Warm-up", distanceMiles: 1.0,
                        description: "1 \(unitLabel) easy + 4 × 20-second strides to prep the legs",
                        targetPaceSecPerMile: paceZones?.easyPaceSecPerMile),
            WorkoutStep(order: 2, label: "\(intervalCount) × 800m Intervals",
                        description: "Run each 800m at hard effort — 8/10 intensity. Take 90 seconds of easy jogging between each rep.",
                        targetPaceSecPerMile: paceZones?.intervalPaceSecPerMile),
            WorkoutStep(order: 3, label: "Cool-down", distanceMiles: 1.0,
                        description: "1 \(unitLabel) easy jog — let the heart rate come down slowly",
                        targetPaceSecPerMile: paceZones?.easyPaceSecPerMile)
        ]

        return WorkoutDay(
            date: date,
            weekNumber: weekNumber,
            dayOfWeek: weekday,
            workoutType: .intervalRun,
            targetDistanceMiles: totalDistance,
            targetDurationMinutes: duration,
            targetPaceSecPerMile: paceZones?.intervalPaceSecPerMile,
            effortLevel: .hard,
            workoutTitle: "\(intervalCount) × 800m Intervals",
            coachingNote: "Intervals build speed and running economy. Each rep should feel hard — around 8/10 effort. The rest is real rest: jog slowly so you can hit the next rep with the same quality.",
            steps: steps
        )
    }

    private func makeStrengthDay(date: Date, weekNumber: Int, weekday: Weekday) -> WorkoutDay {
        WorkoutDay(
            date: date,
            weekNumber: weekNumber,
            dayOfWeek: weekday,
            workoutType: .strengthDay,
            targetDurationMinutes: 25,
            effortLevel: .moderate,
            workoutTitle: "Runner's Strength",
            coachingNote: "Strength training makes you a more resilient, efficient runner. Focus on glutes, hips, and core — the foundation of every stride. 20–30 minutes is enough.",
            steps: [
                WorkoutStep(order: 1, label: "Activation", durationMinutes: 5,
                            description: "Glute bridges, clamshells, hip circles — 2 rounds"),
                WorkoutStep(order: 2, label: "Main Set", durationMinutes: 15,
                            description: "Single-leg squats, Romanian deadlifts, lateral band walks, plank variations — 3 rounds"),
                WorkoutStep(order: 3, label: "Cool-down", durationMinutes: 5,
                            description: "Hip flexor stretch, pigeon pose, figure-four stretch")
            ]
        )
    }

    // MARK: - Duration Estimation

    /// Estimate duration in minutes from distance and pace.
    /// Falls back to a speed-based estimate when no pace zones are available.
    private func estimatedDuration(miles: Double, paceSecPerMile: Int?, fallbackMph: Double) -> Int {
        if let pace = paceSecPerMile {
            return Int(miles * Double(pace) / 60)
        }
        return Int(miles / fallbackMph * 60)
    }

    // MARK: - Long Run Distance Table

    private func longRunDistance(weekNumber: Int, profile: UserProfile) -> Double {
        let totalWeeks = planLength(for: profile.raceType, level: profile.fitnessLevel)
        let progress = Double(weekNumber) / Double(totalWeeks)
        let peak = peakLongRun(for: profile.raceType, level: profile.fitnessLevel)
        let taperWeeks = taperLength(for: profile.raceType)
        let buildWeeks = totalWeeks - taperWeeks

        if weekNumber > buildWeeks {
            let taperWeek = weekNumber - buildWeeks
            switch taperWeek {
            case 1: return peak * 0.75
            case 2: return peak * 0.55
            default: return peak * 0.40
            }
        }

        // Anchor the start of the progression to the user's recent longest run.
        // If their recent long run is above the formula start, we begin there and
        // progress to peak. If below (or no data), use the standard formula start.
        let formulaStart = peak * 0.45
        let recentLongest = profile.recentRuns.map(\.distanceMiles).max() ?? 0
        let startLong = recentLongest > formulaStart
            ? min(recentLongest, peak * 0.85) // don't start above 85% of peak
            : formulaStart

        let distance = startLong + (peak - startLong) * progress
        return (distance * 2).rounded() / 2
    }

    private func peakLongRun(for race: RaceType, level: FitnessLevel) -> Double {
        switch (race, level) {
        case (.fiveK, .beginner): return 5
        case (.fiveK, .intermediate): return 6
        case (.fiveK, .advanced): return 7
        case (.tenK, .beginner): return 8
        case (.tenK, .intermediate): return 10
        case (.tenK, .advanced): return 12
        case (.halfMarathon, .beginner): return 12
        case (.halfMarathon, .intermediate): return 14
        case (.halfMarathon, .advanced): return 16
        case (.fullMarathon, .beginner): return 18
        case (.fullMarathon, .intermediate): return 20
        case (.fullMarathon, .advanced): return 22
        }
    }

}

// MARK: - Supporting Types

enum TrainingPhase {
    case base, build, peak, taper
}
