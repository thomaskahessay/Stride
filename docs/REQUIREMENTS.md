# Stride — Product Requirements Document

**Version:** 1.0
**Last updated:** March 2026
**Scope:** v1 — TestFlight launch

---

## 1. Product Vision

Stride is a free, personal-use iOS running app that generates and manages structured training plans for road races. It onboards the user once, understands their fitness level and schedule, builds a personalised plan, and guides them through every workout day — from the first easy run to race day.

The design philosophy: a Runna-quality experience, minus the paywall.

---

## 2. Target Users

| Persona | Description |
|---|---|
| **Primary** | Runner training for a specific road race (marathon, half, 10K, 5K), needs structure and accountability |
| **Sarah (the girlfriend)** | Intermediate runner, ~90 days from a full marathon in May, currently using Strava, Apple Watch user |
| **Future users** | Anyone from beginner to experienced who trains for a timed road race |

Onboarding adapts the experience for all levels — the plan generated is specific to the individual.

---

## 3. Supported Race Types (v1)

- 5K (3.1 miles)
- 10K (6.2 miles)
- Half Marathon (13.1 miles)
- Full Marathon (26.2 miles)

Custom distance: deferred to v2.

---

## 4. Functional Requirements

### 4.1 Onboarding

**FR-01** The app shall show a full-screen onboarding flow on first launch only.
**FR-02** Onboarding shall collect the following inputs in order:
  1. Runner's first name
  2. Race type (5K / 10K / Half / Full)
  3. Race date (date picker, must be ≥ 4 weeks in the future)
  4. Fitness level: Beginner / Intermediate / Advanced (with descriptions)
  5. Current weekly mileage (numeric slider, 0–60 miles)
  6. Preferred long run day (day of week picker)
  7. Rest days (multi-select days of week — cannot conflict with long run day)
  8. Days available to train per week (3, 4, or 5)
  9. Recent race time (optional — for finish time projection): race distance + finish time
  10. Plan preview — suggested entry week + ability to adjust ±3 weeks

**FR-03** The app shall auto-calculate the suggested starting week based on: race date → count back → match current date to the appropriate training phase.
**FR-04** The user shall be able to manually shift the suggested entry week forward or backward before confirming.
**FR-05** On confirmation, the app shall generate the full training plan and persist it.
**FR-06** Onboarding shall not be shown again after completion. A "Restart / Edit Plan" option shall exist in Settings.

---

### 4.2 Training Plan Generation

**FR-07** The system shall generate a complete day-by-day training plan from the user's start date through race day, based on all onboarding inputs.
**FR-08** Plans shall be periodised into four phases: Base → Build → Peak → Taper.
**FR-09** Weekly mileage shall increase no more than 10% week-over-week (hard cap).
**FR-10** The plan shall include the following workout types:
  - Easy / Recovery Run
  - Long Run
  - Tempo Run
  - Interval / Speed Work
  - Strength Day (labelled only — no exercise detail in v1)
  - Rest Day
**FR-11** Long runs shall be scheduled on the user's preferred long run day.
**FR-12** Rest days shall be placed on the user's selected rest days.
**FR-13** Plans shall adapt to 3, 4, or 5 training days per week.
**FR-14** Beginner plans shall use run/walk intervals for easy and long runs early in the base phase.
**FR-15** The plan shall include a taper phase of 2–3 weeks before race day.

---

### 4.3 Dashboard (Home)

**FR-16** The dashboard shall be the default landing screen after onboarding.
**FR-17** The dashboard shall display the following panels:
  - **Race countdown card:** race name, days remaining, large number
  - **Today's workout card:** workout type, distance, duration target, effort level — with "Start" and "Log" CTAs
  - **Weekly progress card:** miles completed vs. target this week, horizontal progress bar
  - **Streak badge:** current consecutive active days
**FR-18** Rest day panel shall display a recovery or motivation tip instead of a workout card.
**FR-19** The dashboard shall refresh data every time the app foregrounds.

---

### 4.4 Training Calendar

**FR-20** The calendar view shall show a monthly calendar grid.
**FR-21** Each day shall be colour-coded by workout type (or rest/empty).
**FR-22** Tapping a day shall open a workout detail sheet.
**FR-23** Completed workouts shall show a checkmark indicator on the calendar.
**FR-24** Past missed workouts shall show a distinct visual state (faded / strikethrough).
**FR-25** The calendar shall default to the current month and allow forward/back navigation.

---

### 4.5 Workout Detail

**FR-26** Workout detail shall display:
  - Workout name and type badge
  - Target distance and estimated duration
  - Effort level (e.g. "Easy — conversational pace", "Tempo — comfortably hard")
  - Step-by-step structure (e.g. "1mi warm-up → 4mi at tempo → 1mi cool-down")
  - Coaching note — purpose of the workout in plain language
**FR-27** The detail screen shall have a prominent "Log Workout" button.
**FR-28** If a HealthKit workout is detected for that day, the log form shall be pre-filled.

---

### 4.6 Workout Logging

**FR-29** The log workout sheet shall allow input of:
  - Actual distance (pre-filled from HealthKit if available)
  - Duration / time (pre-filled from HealthKit if available)
  - Effort rating (RPE 1–10 scale with descriptive labels)
  - Notes (optional free text, max 500 chars)
**FR-30** Saving a log shall mark the `WorkoutDay` as completed.
**FR-31** A celebration animation (confetti) shall play when a long run or milestone workout is logged.
**FR-32** Logging shall be allowed for past workouts (up to 7 days back).

---

### 4.7 HealthKit Integration

**FR-33** The app shall request HealthKit read authorisation on first launch (after onboarding).
**FR-34** On app foreground, the app shall query HealthKit for running workouts in the last 48 hours.
**FR-35** Matching workouts (by date) shall be offered as pre-fill data in the log form — user must confirm.
**FR-36** HealthKit data used: workout distance, duration, average heart rate (if available).
**FR-37** Strava data shall be accessed indirectly — Strava syncs to Apple Health, Stride reads from Health.
**FR-38** The app shall NOT write any data to HealthKit in v1.

---

### 4.8 Progress & Stats

**FR-39** The progress view shall display:
  - Weekly mileage bar chart (last 8 weeks)
  - Total miles logged this training block
  - Plan completion percentage
  - Current streak (consecutive days with logged activity)
  - Upcoming race countdown (mirrored from dashboard)
  - Projected finish time card
**FR-40** Projected finish time shall be calculated using the Riegel formula from the most recent time trial entry.
**FR-41** If no time trial exists, the finish time card shall prompt the user to add one.
**FR-42** The projected finish time shall update whenever a new time trial is entered.

---

### 4.9 Push Notifications

**FR-43** The app shall request notification permission after onboarding completes.
**FR-44** Daily workout reminder: fires at user-configured time, skipped on rest days.
**FR-45** Weekly summary: fires every Sunday at 8:00 PM — "You ran X miles this week. Y workouts completed."
**FR-46** Motivational nudge: if a scheduled workout day passes with no log, send a gentle nudge the following morning.
**FR-47** All notifications are local (UNUserNotificationCenter) — no server required.
**FR-48** User shall be able to toggle each notification type and change reminder time in Settings.

---

### 4.10 Profile & Settings

**FR-49** Profile view shall show: name, race type, race date, current plan week.
**FR-50** Settings shall allow:
  - Edit notification preferences (types + time)
  - Edit units (miles / km)
  - View plan summary / regenerate plan
  - Reset all data (with confirmation)
**FR-51** Units (miles/km) shall apply consistently across the entire app.

---

## 5. Non-Functional Requirements

**NFR-01 Performance:** App launch to dashboard in < 1 second on iPhone 14 or later.
**NFR-02 Offline-first:** All core functionality works with no internet connection.
**NFR-03 Storage:** All data stored locally via SwiftData. No server, no accounts.
**NFR-04 Privacy:** No analytics, no crash reporting, no third-party SDKs in v1. HealthKit data never leaves the device.
**NFR-05 Accessibility:** Support Dynamic Type (all text scales). Support VoiceOver labels on interactive elements.
**NFR-06 iOS compatibility:** iOS 18.0 minimum deployment target.
**NFR-07 Orientation:** Portrait only.
**NFR-08 Resilience:** No force unwraps. Graceful handling of missing or incomplete data throughout.

---

## 6. Out of Scope for v1

| Feature | Notes |
|---|---|
| GPS live tracking | Architecture accommodates it — deferred to v2 |
| Active run coaching mode (audio cues) | v2 |
| Apple Watch companion app | v2 |
| Custom race distances | v2 |
| Strava OAuth / direct API | v2 — use HealthKit bridge instead |
| iCloud sync | Architecture ready — add CloudKit sync in v2 |
| Social features (sharing, leaderboards) | v3+ |
| Paid/subscription model | v3+ |
| Android | Never (Swift-only) |

---

## 7. User Stories

### Onboarding
- As a new user, I want to tell the app my race date and fitness level so it builds a plan that matches where I am in my training.
- As a mid-training runner, I want to see a suggested starting week with the option to adjust it so the plan meets me where I actually am.

### Daily use
- As a runner, I want to open the app and immediately see today's workout so I don't have to navigate to find it.
- As a runner, I want to see how many days until my race every time I open the app so I feel the momentum building.

### Logging
- As an Apple Watch user, I want my run data to auto-populate the log form so I don't have to manually type in my distance and time.
- As a runner, I want to rate how hard a workout felt so the app can track my training load.

### Progress
- As a runner, I want to see my projected finish time based on my recent training so I know if I'm on track for my goal.
- As a runner, I want to see a weekly mileage chart so I can see my fitness building over time.

### Plan management
- As a runner, I want to view my entire training calendar so I can plan my week ahead.
- As a runner, I want to regenerate my plan if my race date changes or I take time off.
