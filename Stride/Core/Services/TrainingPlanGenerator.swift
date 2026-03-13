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

        let longRunByWeek = longRunProgression(profile: profile, entryWeek: plan.entryWeek)
        let easyRunByWeek = easyRunProgression(profile: profile, entryWeek: plan.entryWeek)

        let days = buildWorkoutDays(
            profile: profile,
            plan: plan,
            paceZones: paceZones,
            longRunByWeek: longRunByWeek,
            easyRunByWeek: easyRunByWeek
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
        case (.fullMarathon, .intermediate): return 20
        case (.fullMarathon, .advanced): return 18
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
            to: Calendar.current.startOfDay(for: DateProvider.shared.now)
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
                // Recovery / cutback week — 3:1 build/cutback cycle
                // Volume drops for this week only; next build week resumes
                // from where the previous build cycle left off (standard 3:1)
                mileage[week] = current * 0.75
            } else {
                mileage[week] = current
                // Progress toward peak, capped at 8%
                let next = current * 1.08
                current = min(next, peakMiles)
            }
        }

        return mileage
    }

    private func startingMileage(profile: UserProfile) -> Double {
        // Fallback level base — only used when user has no self-reported mileage
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
        // Anchor to the runner's actual weekly volume; fall back to level base
        // if they haven't reported any mileage
        if profile.currentWeeklyMiles > 0 {
            return profile.currentWeeklyMiles
        }
        return levelBase
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
        paceZones: PaceZones?,
        longRunByWeek: [Int: Double],
        easyRunByWeek: [Int: Double]
    ) -> [WorkoutDay] {
        var days: [WorkoutDay] = []
        let calendar = Calendar.current

        for week in 1...plan.totalWeeks {
            let weekStartOffset = (week - 1) * 7
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

            // Strength goes on any day without a run (base/build only).
            // Prefer rest days first, then any other non-run day.
            let runDays: Set<Weekday> = {
                var s: Set<Weekday> = [profile.preferredLongRunDay]
                if let q = qualityWeekday { s.insert(q) }
                s.formUnion(easyRunWeekdays)
                return s
            }()
            let strengthWeekday: Weekday? = (phase == .base || phase == .build)
                ? weekDays.map(\.weekday).first {
                    !runDays.contains($0)
                }
                : nil

            // --- Compute distances ---
            // Long run from dedicated progression table (already has cutback + cap logic).
            // Only apply the 32km absolute ceiling here.
            let rawLongRun = longRunDistance(weekNumber: week, profile: profile, longRunByWeek: longRunByWeek)
            let longRunDist = min(rawLongRun, 20.0) // 20mi ≈ 32km absolute cap

            // Tempo effort: 5–8km of hard running, scaling with phase.
            // Warmup + cooldown added by the factory method (~3.2km total).
            let hasQuality = qualityWeekday != nil
            let tempoEffortDist: Double
            switch phase {
            case .base:  tempoEffortDist = 3.0   // ~5km
            case .build: tempoEffortDist = 4.0   // ~6.4km
            case .peak:  tempoEffortDist = 5.0   // ~8km
            case .taper: tempoEffortDist = 3.0
            }
            let workoutDist = hasQuality ? tempoEffortDist : 0.0

            // Easy runs: independent progression, distributed by role
            let aerobicEasyDist = easyRunByWeek[week]
                ?? startingEasyRun(for: profile.raceType, level: profile.fitnessLevel)
            let sortedEasyWeekdays = easyRunWeekdays.sorted { $0.rawValue < $1.rawValue }
            let easyDistMap = distributeEasyRunsByRole(
                aerobicDistance: aerobicEasyDist,
                easyWeekdays: sortedEasyWeekdays,
                longRunDay: profile.preferredLongRunDay,
                qualityDay: qualityWeekday
            )

            // Build each day using the pre-determined slot assignments
            // Determine quality session type for this week (needed for long run variant selection)
            let intervalFrequency: Int = (profile.raceType == .fiveK || profile.raceType == .tenK) ? 2 : 3
            let weekHasIntervals = qualityWeekday != nil && week % intervalFrequency == 0
            let isRecoveryWeek = week % 4 == 0

            // Pick long run variant based on phase, week context, and quality session
            let longRunVariant = self.longRunVariant(
                week: week,
                phase: phase,
                isRecoveryWeek: isRecoveryWeek,
                hasIntervalSession: weekHasIntervals,
                raceType: profile.raceType
            )

            for (date, weekday) in weekDays {
                let workoutDay: WorkoutDay

                if weekday == strengthWeekday {
                    workoutDay = makeStrengthDay(date: date, weekNumber: week, weekday: weekday)
                } else if profile.restDays.contains(weekday) {
                    workoutDay = makeRestDay(date: date, weekNumber: week, weekday: weekday)
                } else if weekday == profile.preferredLongRunDay {
                    workoutDay = makeLongRunDay(
                        date: date, weekNumber: week, weekday: weekday,
                        distance: longRunDist, profile: profile,
                        phase: phase, paceZones: paceZones,
                        variant: longRunVariant
                    )
                } else if weekday == qualityWeekday {
                    workoutDay = weekHasIntervals
                        ? makeIntervalDay(date: date, weekNumber: week, weekday: weekday,
                                          distance: workoutDist, profile: profile, paceZones: paceZones)
                        : makeTempoDay(date: date, weekNumber: week, weekday: weekday,
                                       distance: workoutDist, profile: profile, paceZones: paceZones)
                } else if let easyInfo = easyDistMap[weekday] {
                    workoutDay = makeEasyRunDay(
                        date: date, weekNumber: week, weekday: weekday,
                        distance: easyInfo.distance, role: easyInfo.role,
                        profile: profile, paceZones: paceZones
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

    // MARK: - Easy Run Role Assignment

    /// Assign roles by chronological position within the week.
    /// 1 run  → [easy]
    /// 2 runs → [recovery, easy]
    /// 3 runs → [recovery, shortEasy, easy]
    /// 4+ runs → recovery, shortEasy..., easy
    private func assignEasyRunRoles(count: Int) -> [EasyRunRole] {
        switch count {
        case 0: return []
        case 1: return [.easy]
        case 2: return [.recovery, .easy]
        case 3: return [.recovery, .shortEasy, .easy]
        default:
            // First is recovery, last is easy, middle ones are short easy
            var roles: [EasyRunRole] = [.recovery]
            roles += Array(repeating: EasyRunRole.shortEasy, count: count - 2)
            roles.append(.easy)
            return roles
        }
    }

    /// Distribute easy run distances for the week using the progression value
    /// and count-based role assignment. Each role gets a distinct distance.
    private func distributeEasyRunsByRole(
        aerobicDistance: Double,
        easyWeekdays: [Weekday],
        longRunDay: Weekday,
        qualityDay: Weekday?
    ) -> [Weekday: (distance: Double, role: EasyRunRole)] {
        guard !easyWeekdays.isEmpty else { return [:] }

        let roles = assignEasyRunRoles(count: easyWeekdays.count)
        var result: [Weekday: (Double, EasyRunRole)] = [:]

        for (weekday, role) in zip(easyWeekdays, roles) {
            let raw = aerobicDistance * role.weight
            // Apply role-specific floor; ceiling at ~13km (8.1mi)
            let clamped = min(max(raw, role.floorMiles), 8.1)
            result[weekday] = (clamped, role)
        }

        return result
    }

    // MARK: - Long Run Variant Selection

    /// Picks the long run variant based on training phase, week context,
    /// and what quality session is scheduled that week.
    private func longRunVariant(
        week: Int,
        phase: TrainingPhase,
        isRecoveryWeek: Bool,
        hasIntervalSession: Bool,
        raceType: RaceType
    ) -> LongRunVariant {
        // Base and taper: always steady
        guard phase == .build || phase == .peak else { return .steady }

        // Recovery/cutback weeks: always steady (lower stress)
        if isRecoveryWeek { return .steady }

        if phase == .build {
            // Build phase: introduce marathon pace every 3rd non-cutback week,
            // progressive in between. If this week already has intervals,
            // use progressive (lower CNS load than MP blocks).
            if hasIntervalSession {
                return .progressive
            }
            // Marathon pace every 3rd week in build
            return week % 3 == 0 ? .marathonPace : .progressive
        }

        // Peak phase: race-specific simulation — alternate marathon pace
        // and fast finish. Interval weeks get fast finish (less sustained
        // threshold stress when combined with speed work).
        if hasIntervalSession {
            return .fastFinish
        }
        return week % 2 == 0 ? .marathonPace : .fastFinish
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
        distance: Double,
        role: EasyRunRole = .easy,
        profile: UserProfile,
        paceZones: PaceZones?
    ) -> WorkoutDay {
        let duration = estimatedDuration(miles: distance, paceSecPerMile: paceZones?.easyPaceSecPerMile, fallbackMph: 5.5)

        let (workoutType, title, note): (WorkoutType, String, String) = {
            switch role {
            case .recovery:
                return (.recoveryRun,
                        "Recovery Run",
                        "Keep this one genuinely short and slow. Your body is still adapting from yesterday's hard effort. The goal is blood flow, not fitness — if in doubt, go slower.")
            case .shortEasy:
                return (.easyRun,
                        "Short Easy Run",
                        "A shorter easy run today. Keep the legs turning over at a comfortable pace — no need to push the distance. Save your energy for the bigger sessions.")
            case .easy:
                return (.easyRun,
                        "Easy Run",
                        "Today is about building your aerobic base. Run slow enough to hold a conversation. Don't worry about pace — your easy runs make your hard runs possible.")
            }
        }()

        let mainStepLabel: String
        switch role {
        case .recovery:  mainStepLabel = "Recovery Run"
        case .shortEasy: mainStepLabel = "Short Easy Run"
        case .easy:      mainStepLabel = "Easy Run"
        }

        let steps: [WorkoutStep] = [
            WorkoutStep(order: 1, label: "Warm-up", durationMinutes: 5,
                        description: "5 minutes of brisk walking or very slow jogging",
                        targetPaceSecPerMile: paceZones?.recoveryPaceSecPerMile),
            WorkoutStep(order: 2, label: mainStepLabel, distanceMiles: distance,
                        description: "Run at a fully conversational pace — if you can't speak full sentences, slow down",
                        targetPaceSecPerMile: paceZones?.easyPaceSecPerMile),
            WorkoutStep(order: 3, label: "Cool-down", durationMinutes: 5,
                        description: "5 minutes walking + light calf and hip flexor stretches")
        ]

        return WorkoutDay(
            date: date,
            weekNumber: weekNumber,
            dayOfWeek: weekday,
            workoutType: workoutType,
            targetDistanceMiles: distance,
            targetDurationMinutes: duration,
            targetPaceSecPerMile: paceZones?.easyPaceSecPerMile,
            effortLevel: .easy,
            workoutTitle: title,
            coachingNote: note,
            steps: steps
        )
    }

    private func makeLongRunDay(
        date: Date,
        weekNumber: Int,
        weekday: Weekday,
        distance: Double,
        profile: UserProfile,
        phase: TrainingPhase,
        paceZones: PaceZones?,
        variant: LongRunVariant
    ) -> WorkoutDay {
        let duration = estimatedDuration(miles: distance, paceSecPerMile: paceZones?.longRunPaceSecPerMile, fallbackMph: 5.0)

        let units = profile.unitPreference
        let warmupLabel = units == .kilometers ? "Warm-up km" : "Warm-up Mile"
        let warmupDesc = units == .kilometers
            ? "First km very easy — let the body wake up"
            : "First mile very easy — let the body wake up"
        let displayDist = String(format: "%.1f", units.convert(distance))

        let (longRunTitle, coachingNote, steps) = longRunSteps(
            variant: variant,
            distance: distance,
            displayDist: displayDist,
            units: units,
            warmupLabel: warmupLabel,
            warmupDesc: warmupDesc,
            paceZones: paceZones
        )

        return WorkoutDay(
            date: date,
            weekNumber: weekNumber,
            dayOfWeek: weekday,
            workoutType: .longRun,
            targetDistanceMiles: distance,
            targetDurationMinutes: duration,
            targetPaceSecPerMile: paceZones?.longRunPaceSecPerMile,
            effortLevel: variant == .steady ? .easy : .moderate,
            workoutTitle: longRunTitle,
            coachingNote: coachingNote,
            steps: steps
        )
    }

    private func longRunSteps(
        variant: LongRunVariant,
        distance: Double,
        displayDist: String,
        units: UnitSystem,
        warmupLabel: String,
        warmupDesc: String,
        paceZones: PaceZones?
    ) -> (title: String, note: String, steps: [WorkoutStep]) {

        let cooldown = WorkoutStep(
            order: 99, label: "Cool-down", durationMinutes: 10,
            description: "10 minutes walking, then full leg stretching routine — quads, hamstrings, calves, hips"
        )

        switch variant {

        case .steady:
            let title = "\(displayDist) \(units.shortLabel) Long Run"
            let note = "Your long run this week is all about time on feet. Run at a pace where you can chat comfortably. Finish feeling like you had more in the tank."
            let mainDist = max(distance - 1.0, distance * 0.90)
            let steps = [
                WorkoutStep(order: 1, label: warmupLabel, distanceMiles: 1.0,
                            description: warmupDesc,
                            targetPaceSecPerMile: paceZones?.easyPaceSecPerMile),
                WorkoutStep(order: 2, label: "Long Run", distanceMiles: mainDist,
                            description: "Settle into your easy aerobic pace. Focus on consistent effort, not pace.",
                            targetPaceSecPerMile: paceZones?.longRunPaceSecPerMile),
                cooldown.withOrder(3)
            ]
            return (title, note, steps)

        case .progressive:
            let title = "\(displayDist) \(units.shortLabel) Progressive Long Run"
            let note = "Start easy and build pace through each third. The first miles should feel almost too slow. By the final third you'll be running at a moderately hard effort — not racing, but working. This teaches pacing discipline and running strong on tired legs."
            let runDist = distance - 1.0 // subtract warmup mile
            let thirdDist = (runDist / 3.0 * 2).rounded() / 2 // round to nearest 0.5
            let finalThird = runDist - (thirdDist * 2)
            let steps = [
                WorkoutStep(order: 1, label: warmupLabel, distanceMiles: 1.0,
                            description: warmupDesc,
                            targetPaceSecPerMile: paceZones?.easyPaceSecPerMile),
                WorkoutStep(order: 2, label: "Easy Third", distanceMiles: thirdDist,
                            description: "First third at easy conversational pace. Hold back — the work comes later.",
                            targetPaceSecPerMile: paceZones?.longRunPaceSecPerMile),
                WorkoutStep(order: 3, label: "Moderate Third", distanceMiles: thirdDist,
                            description: "Pick up to a moderate effort — still comfortable, but you can feel the pace shift. Breathing is controlled.",
                            targetPaceSecPerMile: paceZones?.easyPaceSecPerMile),
                WorkoutStep(order: 4, label: "Strong Third", distanceMiles: finalThird,
                            description: "Final third at a strong, controlled effort. Not sprinting — think tempo-ish. Finish knowing you could have held it a bit longer.",
                            targetPaceSecPerMile: paceZones?.tempoPaceSecPerMile),
                cooldown.withOrder(5)
            ]
            return (title, note, steps)

        case .marathonPace:
            let title = "\(displayDist) \(units.shortLabel) MP Long Run"
            let note = "This long run has a block of miles at your goal race pace sandwiched between easy running. The easy start warms you into the effort. The race pace block teaches your body what it will feel like on race day. The easy finish lets you recover while still logging miles."
            let mpMiles = min(max(2.0, (distance * 0.35 * 2).rounded() / 2), distance - 4.0) // 35% of distance, min 2mi, leave room for bookends
            let easyBefore = ((distance - mpMiles - 1.0) * 0.6 * 2).rounded() / 2 // 60% of remaining goes before
            let easyAfter = max(1.0, distance - 1.0 - easyBefore - mpMiles)
            let steps = [
                WorkoutStep(order: 1, label: warmupLabel, distanceMiles: 1.0,
                            description: warmupDesc,
                            targetPaceSecPerMile: paceZones?.easyPaceSecPerMile),
                WorkoutStep(order: 2, label: "Easy Miles", distanceMiles: easyBefore,
                            description: "Settle in at easy pace. Let the legs loosen up before the work begins.",
                            targetPaceSecPerMile: paceZones?.longRunPaceSecPerMile),
                WorkoutStep(order: 3, label: "Race Pace Block", distanceMiles: mpMiles,
                            description: "Lock into your goal race pace. Focus on rhythm, breathing, and staying relaxed. This is the centrepiece of the session.",
                            targetPaceSecPerMile: paceZones?.racePaceSecPerMile),
                WorkoutStep(order: 4, label: "Easy Finish", distanceMiles: easyAfter,
                            description: "Back to easy pace. Let the heart rate come down while keeping the legs moving.",
                            targetPaceSecPerMile: paceZones?.longRunPaceSecPerMile),
                cooldown.withOrder(5)
            ]
            return (title, note, steps)

        case .fastFinish:
            let title = "\(displayDist) \(units.shortLabel) Fast Finish Long Run"
            let note = "Run the bulk of this long run easy, then pick up to tempo effort for the final miles. This simulates the mental and physical challenge of pushing hard when fatigued — exactly what race day demands. Don't start the fast finish too early."
            let fastMiles = min(max(2.0, (distance * 0.20 * 2).rounded() / 2), 4.0) // 20% of distance, 2-4mi
            let easyMiles = distance - 1.0 - fastMiles
            let steps = [
                WorkoutStep(order: 1, label: warmupLabel, distanceMiles: 1.0,
                            description: warmupDesc,
                            targetPaceSecPerMile: paceZones?.easyPaceSecPerMile),
                WorkoutStep(order: 2, label: "Easy Miles", distanceMiles: easyMiles,
                            description: "The patient part. Run at a comfortable easy pace and save your energy for the finish.",
                            targetPaceSecPerMile: paceZones?.longRunPaceSecPerMile),
                WorkoutStep(order: 3, label: "Fast Finish", distanceMiles: fastMiles,
                            description: "Time to work. Pick up to tempo effort — comfortably hard. You should feel like you're racing the last stretch. Strong and controlled.",
                            targetPaceSecPerMile: paceZones?.tempoPaceSecPerMile),
                cooldown.withOrder(4)
            ]
            return (title, note, steps)
        }
    }

    private func makeTempoDay(
        date: Date,
        weekNumber: Int,
        weekday: Weekday,
        distance: Double,
        profile: UserProfile,
        paceZones: PaceZones?
    ) -> WorkoutDay {
        let tempoMiles = max(2.0, distance)
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
        distance: Double,
        profile: UserProfile,
        paceZones: PaceZones?
    ) -> WorkoutDay {
        // Scale interval count from the allocated workout distance
        let repDistanceMiles = 0.5 // 800m
        let availableForReps = max(1.0, distance - 2.0) // subtract warmup+cooldown
        let intervalCount = max(4, min(8, Int(availableForReps / repDistanceMiles)))
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

    /// Builds the full long-run progression once, capped at ~2 mi (≈3.2 km) increase
    /// per week, anchored to the user's longest recent run at the entry week.
    func longRunProgression(profile: UserProfile, entryWeek: Int) -> [Int: Double] {
        let totalWeeks = planLength(for: profile.raceType, level: profile.fitnessLevel)
        let peak = peakLongRun(for: profile.raceType, level: profile.fitnessLevel)
        let taperWeeks = taperLength(for: profile.raceType)
        let buildWeeks = totalWeeks - taperWeeks

        // Max week-over-week long run increase: 2 miles ≈ 3.2 km
        let maxWeeklyIncrease: Double = 2.0

        // Anchor start to user's longest recent run (from HealthKit or manual input)
        let formulaStart = peak * 0.45
        let recentLongest = profile.longestRecentRunMiles > 0
            ? profile.longestRecentRunMiles
            : (profile.recentRuns.map(\.distanceMiles).max() ?? 0)
        // Start at the runner's actual longest recent run so the first
        // actionable long run is a natural step up via the increment.
        let anchoredStart = recentLongest > 0
            ? min(recentLongest, peak * 0.85)
            : formulaStart
        let startLong = max(anchoredStart, formulaStart)

        // Count growth weeks from entry week to end of build phase, so the
        // progression is spread across the weeks the user will actually run.
        let effectiveEntry = min(entryWeek, buildWeeks)
        let growthWeeks = (effectiveEntry...buildWeeks).filter { $0 % 4 != 0 }.count
        let idealIncrement = growthWeeks > 1
            ? (peak - startLong) / Double(growthWeeks - 1)
            : 0
        let increment = min(idealIncrement, maxWeeklyIncrease)

        var progression: [Int: Double] = [:]
        var current = startLong

        // Pre-entry weeks get placeholder values (won't be shown but keeps the
        // dictionary complete for any code that indexes by week number).
        for week in 1..<effectiveEntry {
            progression[week] = startLong
        }

        for week in effectiveEntry...totalWeeks {
            if week > buildWeeks {
                // Taper phase — step down from peak
                let taperWeek = week - buildWeeks
                switch taperWeek {
                case 1: progression[week] = peak * 0.75
                case 2: progression[week] = peak * 0.55
                default: progression[week] = peak * 0.40
                }
            } else if week % 4 == 0 {
                // Recovery week — pull back 25%
                progression[week] = (current * 0.75 * 2).rounded() / 2
            } else {
                progression[week] = (current * 2).rounded() / 2
                // Advance for next growth week, capped at peak
                current = min(current + increment, peak)
            }
        }

        return progression
    }

    private func longRunDistance(weekNumber: Int, profile: UserProfile, longRunByWeek: [Int: Double]) -> Double {
        longRunByWeek[weekNumber] ?? peakLongRun(for: profile.raceType, level: profile.fitnessLevel) * 0.45
    }

    private func peakLongRun(for race: RaceType, level: FitnessLevel) -> Double {
        switch (race, level) {
        case (.fiveK, .beginner): return 5
        case (.fiveK, .intermediate): return 6
        case (.fiveK, .advanced): return 7
        case (.tenK, .beginner): return 8
        case (.tenK, .intermediate): return 10
        case (.tenK, .advanced): return 12
        case (.halfMarathon, .beginner): return 10
        case (.halfMarathon, .intermediate): return 12
        case (.halfMarathon, .advanced): return 13
        case (.fullMarathon, .beginner): return 18
        case (.fullMarathon, .intermediate): return 20
        case (.fullMarathon, .advanced): return 22
        }
    }

    // MARK: - Easy Run Progression

    /// Independent easy run progression — NOT derived from weekly mileage.
    /// Returns the easy run (1.0× role) distance per week in miles.
    /// Recovery (0.75×) and short easy (0.85×) are scaled from this value.
    func easyRunProgression(profile: UserProfile, entryWeek: Int) -> [Int: Double] {
        let totalWeeks = planLength(for: profile.raceType, level: profile.fitnessLevel)
        let start = startingEasyRun(for: profile.raceType, level: profile.fitnessLevel)
        let peak = peakEasyRun(for: profile.raceType, level: profile.fitnessLevel)
        let taperWeeks = taperLength(for: profile.raceType)
        let buildWeeks = totalWeeks - taperWeeks

        // Max week-over-week increase: ~0.8km per week
        let maxWeeklyIncrease: Double = 0.5  // ~0.8km

        let effectiveEntry = min(entryWeek, buildWeeks)
        let growthWeeks = (effectiveEntry...buildWeeks).filter { $0 % 4 != 0 }.count
        let idealIncrement = growthWeeks > 1
            ? (peak - start) / Double(growthWeeks - 1)
            : 0
        let increment = min(idealIncrement, maxWeeklyIncrease)

        var progression: [Int: Double] = [:]
        var current = start

        for week in 1..<effectiveEntry {
            progression[week] = start
        }

        for week in effectiveEntry...totalWeeks {
            if week > buildWeeks {
                // Taper — step down from peak
                let taperWeek = week - buildWeeks
                switch taperWeek {
                case 1: progression[week] = peak * 0.75
                case 2: progression[week] = peak * 0.55
                default: progression[week] = peak * 0.40
                }
            } else if week % 4 == 0 {
                // Recovery week — pull back 25%
                progression[week] = (current * 0.75 * 2).rounded() / 2
            } else {
                progression[week] = (current * 2).rounded() / 2
                current = min(current + increment, peak)
            }
        }

        return progression
    }

    /// Starting easy run distance (miles) for the 1.0× (easy) role.
    /// Recovery and short easy runs scale down from this via their weight.
    /// Floors (5km recovery, 4km short easy, 6km easy) catch any values
    /// that would otherwise be too low in early weeks.
    private func startingEasyRun(for race: RaceType, level: FitnessLevel) -> Double {
        switch (race, level) {
        // 5K plans
        case (.fiveK, .beginner):       return 3.7   // 6km
        case (.fiveK, .intermediate):   return 3.7   // 6km
        case (.fiveK, .advanced):       return 4.3   // 7km
        // 10K
        case (.tenK, .beginner):        return 3.7   // 6km
        case (.tenK, .intermediate):    return 4.3   // 7km
        case (.tenK, .advanced):        return 5.0   // 8km
        // Half Marathon
        case (.halfMarathon, .beginner):      return 3.7   // 6km
        case (.halfMarathon, .intermediate):  return 4.3   // 7km
        case (.halfMarathon, .advanced):      return 5.0   // 8km
        // Full Marathon
        case (.fullMarathon, .beginner):      return 3.7   // 6km
        case (.fullMarathon, .intermediate):  return 4.3   // 7km
        case (.fullMarathon, .advanced):      return 5.6   // 9km
        }
    }

    /// Peak aerobic easy run distance (miles). Absolute ceiling ~13km (8.1mi).
    /// Recovery runs at peak will be 0.6× this = ~7.5km, shakeout = ~9km.
    private func peakEasyRun(for race: RaceType, level: FitnessLevel) -> Double {
        switch (race, level) {
        // 5K — easy runs stay short
        case (.fiveK, .beginner):       return 3.5   // ~5.6km
        case (.fiveK, .intermediate):   return 4.0   // ~6.4km
        case (.fiveK, .advanced):       return 5.0   // ~8km
        // 10K
        case (.tenK, .beginner):        return 4.0   // ~6.4km
        case (.tenK, .intermediate):    return 5.0   // ~8km
        case (.tenK, .advanced):        return 6.0   // ~9.6km
        // Half Marathon
        case (.halfMarathon, .beginner):      return 5.0   // ~8km
        case (.halfMarathon, .intermediate):  return 6.0   // ~9.6km
        case (.halfMarathon, .advanced):      return 7.0   // ~11.3km
        // Full Marathon
        case (.fullMarathon, .beginner):      return 6.0   // ~9.6km
        case (.fullMarathon, .intermediate):  return 7.5   // ~12km
        case (.fullMarathon, .advanced):      return 8.0   // ~13km
        }
    }

}

// MARK: - Supporting Types

enum TrainingPhase {
    case base, build, peak, taper
}

/// Determines the structure and pace variation of each week's long run.
enum LongRunVariant {
    /// All easy pace — aerobic foundation
    case steady
    /// Each third progressively faster: easy → moderate → tempo effort
    case progressive
    /// Middle miles at goal race pace, bookended by easy miles
    case marathonPace
    /// Final 2-3 miles at tempo pace after easy volume
    case fastFinish
}

/// Role-based easy run classification.
/// Assigned by position within the week (chronological order),
/// not by adjacency to hard sessions.
enum EasyRunRole {
    /// Post-hard-effort run — shortest of the week
    case recovery
    /// Mid-week shorter easy run
    case shortEasy
    /// Main base-building run — longest easy run of the week
    case easy

    /// Multiplier applied to the week's progression distance.
    var weight: Double {
        switch self {
        case .recovery:  return 0.75
        case .shortEasy: return 0.85
        case .easy:      return 1.0
        }
    }

    /// Minimum distance in miles per role.
    /// Recovery ≥ 4km (2.5mi), Short Easy ≥ 5km (3.1mi), Easy ≥ 6km (3.7mi).
    var floorMiles: Double {
        switch self {
        case .recovery:  return 2.5   // 4km
        case .shortEasy: return 3.1   // 5km
        case .easy:      return 3.7   // 6km
        }
    }
}
