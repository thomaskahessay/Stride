# Stride — Training Plan Generation Logic

**Version:** 1.0

This document specifies the exact algorithm used by `TrainingPlanGenerator` to produce a personalised training plan.

---

## 1. Plan Structure Overview

Every plan is divided into four phases:

| Phase | Purpose | Typical % of plan |
|---|---|---|
| **Base** | Build aerobic foundation, mostly easy running | 30% |
| **Build** | Introduce tempo and intervals, increase mileage | 35% |
| **Peak** | Highest mileage weeks, race-specific work | 20% |
| **Taper** | Reduce volume, stay sharp, arrive fresh | 15% |

---

## 2. Plan Lengths by Race Type

| Race | Beginner | Intermediate | Advanced |
|---|---|---|---|
| 5K | 8 weeks | 8 weeks | 6 weeks |
| 10K | 10 weeks | 10 weeks | 8 weeks |
| Half Marathon | 16 weeks | 14 weeks | 12 weeks |
| Full Marathon | 20 weeks | 18 weeks | 16 weeks |

---

## 3. Entry Point Calculation

When a user's race date is within the standard plan length (i.e., they're mid-training):

```
planStartDate = raceDate − (totalPlanWeeks × 7 days)
suggestedEntryWeek = ceil((today − planStartDate) / 7)
```

**Example:**
- Race date: May 25, 2026
- Intermediate marathon plan = 18 weeks
- planStartDate = Jan 26, 2026
- Today = March 10, 2026
- Days elapsed = 43
- suggestedEntryWeek = ceil(43 / 7) = **week 7**

The user is shown week 7 as the suggestion. They can adjust ±3 weeks.

If `today < planStartDate`, the user starts at week 1 as normal.
If `today > planStartDate + (totalPlanWeeks × 7)`, the race is too soon — show a warning and use a condensed 4-week plan.

---

## 4. Weekly Mileage Progression

### Base weekly mileage by fitness level

| Fitness Level | 5K start | 10K start | HM start | FM start |
|---|---|---|---|---|
| Beginner | 8 mi/wk | 10 mi/wk | 15 mi/wk | 20 mi/wk |
| Intermediate | 15 mi/wk | 20 mi/wk | 25 mi/wk | 30 mi/wk |
| Advanced | 25 mi/wk | 30 mi/wk | 35 mi/wk | 40 mi/wk |

The starting mileage is also clamped to the user's reported `currentWeeklyMiles`:
```
effectiveStart = max(levelStart, currentWeeklyMiles × 0.9)
```
This prevents shocking a runner who's already at a higher base.

### Progression rule (10% cap)
```
weekMiles[n] = weekMiles[n-1] × 1.10   // max 10% increase
```

### Recovery weeks
Every 4th week is a recovery week — mileage drops by ~20%:
```
if weekNumber % 4 == 0:
    weekMiles[n] = weekMiles[n-1] × 0.80
```

### Peak mileage targets

| Race | Beginner | Intermediate | Advanced |
|---|---|---|---|
| 5K | 25 mi/wk | 35 mi/wk | 45 mi/wk |
| 10K | 30 mi/wk | 40 mi/wk | 55 mi/wk |
| Half Marathon | 35 mi/wk | 45 mi/wk | 60 mi/wk |
| Full Marathon | 40 mi/wk | 55 mi/wk | 70 mi/wk |

### Taper (last 2–3 weeks)
```
Taper week 1: peakMiles × 0.75
Taper week 2: peakMiles × 0.60
Taper week 3 (race week): peakMiles × 0.40
```

---

## 5. Weekly Workout Distribution

### Days-per-week templates

#### 3 days/week
| Day slot | Workout |
|---|---|
| Short weekday | Easy Run |
| Mid weekday | Quality (Tempo or Intervals, alternating) |
| Long run day | Long Run |

#### 4 days/week
| Day slot | Workout |
|---|---|
| Short weekday 1 | Easy Run |
| Quality day | Tempo or Intervals (alternating by week) |
| Short weekday 2 | Easy Run |
| Long run day | Long Run |

#### 5 days/week
| Day slot | Workout |
|---|---|
| Short weekday 1 | Easy Run |
| Quality day | Tempo or Intervals |
| Midweek medium | Easy/Moderate Run |
| Short weekday 2 | Recovery Run |
| Long run day | Long Run |

Remaining days (up to 7) are filled with **Rest Days** or **Strength Days**.

### Strength day placement
- 1 strength day per week during Base phase
- 1 strength day per week during Build phase (optional — only if days allow)
- No strength days during Peak or Taper
- Placed on a non-running day adjacent to a rest day

### Quality day rotation (by phase)

| Phase | Week type | Quality workout |
|---|---|---|
| Base | All weeks | Easy runs only — no quality for beginners; light strides for intermediate/advanced |
| Build | Odd weeks | Tempo Run |
| Build | Even weeks | Intervals |
| Peak | Odd weeks | Tempo Run |
| Peak | Even weeks | Intervals / Race-pace work |
| Taper | All weeks | Short tempo or easy — no hard intervals |

---

## 6. Workout Distance Allocation

### Long run progression (Full Marathon example)

| Plan Week | Beginner | Intermediate | Advanced |
|---|---|---|---|
| 1 | 8 mi | 10 mi | 12 mi |
| 4 | 10 mi | 13 mi | 15 mi |
| 8 | 13 mi | 16 mi | 18 mi |
| 12 | 16 mi | 18 mi | 20 mi |
| 14–15 | 18 mi | 20 mi | 22 mi |
| 16 (peak) | 18 mi | 20 mi | 22 mi |
| Taper −2 | 14 mi | 16 mi | 18 mi |
| Taper −1 | 10 mi | 12 mi | 14 mi |
| Race week | 6 mi | 8 mi | 10 mi |

### Easy run distance
```
easyRunMiles = weeklyMiles × 0.20   // ~20% of weekly mileage per easy run
```

### Tempo run distance
```
tempoMiles = weeklyMiles × 0.15     // ~15% of weekly mileage
```
Tempo is broken into: `warmupMiles(1) + tempoMiles + cooldownMiles(1)`

### Interval workout structure
By phase and fitness:
```
// Example: Build phase, intermediate
8 × 400m at 5K effort, with 90 sec jog recovery
// Or:
4 × 1 mile at 10K effort, with 2 min jog recovery
```

---

## 7. Workout Step Generation

Each `WorkoutDay` has a `steps: [WorkoutStep]` array. Steps are generated based on workout type:

### Easy Run
```
Step 1: "Warm-up" — 5 min easy walk or very slow jog
Step 2: "Main Run" — [distance] at easy, conversational pace
Step 3: "Cool-down" — 5 min walk + light stretching
```

### Long Run
```
Step 1: "Warm-up" — 1 mile easy
Step 2: "Long Run" — [distance − 2 mi] at easy/aerobic pace
Step 3: "Final Mile" — last mile slightly faster (optional push)
Step 4: "Cool-down" — 10 min walk + full stretch
```

### Tempo Run
```
Step 1: "Warm-up" — 1 mile easy jog
Step 2: "Tempo Effort" — [tempo miles] at comfortably hard pace
Step 3: "Cool-down" — 1 mile easy jog
```

### Intervals
```
Step 1: "Warm-up" — 1 mile easy + 4 strides
Step 2: "Intervals" — [N × distance] at hard effort, [recovery] between
Step 3: "Cool-down" — 1 mile easy
```

### Strength Day
```
Step 1: "Today's Focus" — 20–30 min runner's strength routine
(No exercise detail in v1 — link to description in coaching note)
```

### Rest Day
No steps. Coaching note only (recovery tip).

---

## 8. Coaching Notes (by workout type + phase)

These are stored on `WorkoutDay.coachingNote` as plain text strings, generated at plan creation time.

### Easy Run
> "Today is about recovery and aerobic base building. Run slow enough to hold a conversation. Don't worry about pace — effort is everything. Your easy runs are what make your hard runs possible."

### Long Run (Base phase)
> "Your long run this week is all about time on feet. Run at a pace where you could chat comfortably. Don't push the last miles — finish feeling like you had more in the tank."

### Long Run (Peak phase)
> "This is your peak long run — one of the most important sessions in your plan. Run the first two-thirds easy, then pick up slightly for the final portion. This teaches your body to run strong on tired legs."

### Tempo Run
> "Tempo runs build your lactate threshold — the pace you can sustain for a long time. Aim for 'comfortably hard': you can speak a few words but not full sentences. This should feel controlled, not desperate."

### Intervals
> "Today's intervals build speed and running economy. Each rep should feel hard — around 8/10 effort. The rest is real rest — walk or jog slowly so you can hit the next rep with the same quality."

### Rest Day
> "Rest is training. Your body gets stronger during recovery, not during the run. Use today to sleep well, eat well, and stay off your feet where possible."

---

## 9. Finish Time Projection — Riegel Formula

### Formula
```
T2 = T1 × (D2 / D1)^1.06
```

### Inputs
- `T1`: user's recent finish time in seconds (e.g. 5K in 28:00 = 1680s)
- `D1`: distance of known race (e.g. 5K = 3.1 miles)
- `D2`: target race distance (e.g. Full Marathon = 26.2 miles)
- `T2`: projected finish time

### Example
```
T1 = 1680s (28:00 5K)
D1 = 3.1 miles
D2 = 26.2 miles

T2 = 1680 × (26.2 / 3.1)^1.06
   = 1680 × (8.452)^1.06
   = 1680 × 9.68
   = 16,262 seconds
   ≈ 4 hours 31 minutes
```

### Display
Show as `HH:MM:SS` or `Xh Xm`.
Show "based on your [distance] on [date]" as a subtitle.
Add a qualifier: *"This is an estimate based on current fitness. It will improve as you train."*

### When to update
- User enters a new time trial in Progress view
- The projected time is recalculated immediately and persisted to `UserProfile.recentRaceTime`

---

## 10. Plan Validation Rules

Before persisting a generated plan, validate:

1. ✅ At least 1 rest day per week
2. ✅ Long run never placed on a user-marked rest day
3. ✅ No two quality workouts (tempo/intervals) on consecutive days
4. ✅ Easy run the day after a long run (or rest)
5. ✅ Weekly mileage increase never exceeds 10% (except taper reductions)
6. ✅ Total plan days matches (raceDate − planStartDate) in days
7. ✅ Race day itself is not a workout (it's the race)
