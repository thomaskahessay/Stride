# Stride — Design System

**Version:** 1.0
**Style:** Glassmorphism · Pastel Lavender · iOS-native · Gender-neutral · Motivational

---

## 1. Colour Palette

### Primary colours
| Token | Hex | Usage |
|---|---|---|
| `lavender` | `#DAC3E8` | Primary accent — buttons, progress bars, highlights, badges |
| `lavenderDeep` | `#B89FCC` | Pressed states, borders on glass cards, chart fills |
| `lavenderLight` | `#EDE0F5` | Subtle tints, secondary backgrounds, tag backgrounds |
| `lavenderGlow` | `#F3ECFA` | Card background tint, onboarding step backgrounds |

### Gradient (background)
```swift
// Applied to the root ZStack background
LinearGradient(
    colors: [Color.stride.lavenderLight, Color.white],
    startPoint: .top,
    endPoint: .bottom
)
```

On cards, a secondary glass-specific gradient:
```swift
LinearGradient(
    colors: [Color.white.opacity(0.6), Color.stride.lavenderGlow.opacity(0.4)],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)
```

### Neutral colours
| Token | Usage |
|---|---|
| `textPrimary` | `.primary` (adapts to light/dark) |
| `textSecondary` | `.secondary` |
| `surface` | `Color(.systemBackground)` |
| `surfaceElevated` | `Color(.secondarySystemBackground)` |

### Workout type accent colours
| Workout Type | Colour |
|---|---|
| Easy Run | `Color.stride.mint` (`#6FCF97`) |
| Long Run | `Color.stride.lavender` (`#DAC3E8`) |
| Tempo Run | `Color.stride.warmOrange` (`#F2994A`) |
| Intervals | `Color.stride.coral` (`#EB5757`) |
| Strength | `Color.stride.sky` (`#56CCF2`) |
| Rest | `Color(.systemGray4)` |

All workout accent colours must have a `.opacity(0.15)` fill variant for card backgrounds.

---

## 2. Typography

Stride uses **SF Pro** exclusively (system font). Never import custom fonts.

| Token | SwiftUI | Usage |
|---|---|---|
| `displayLarge` | `.largeTitle.bold()` | Race countdown number, hero numbers |
| `displayMedium` | `.title.bold()` | Section headers, onboarding step title |
| `headingMedium` | `.title2.semibold()` | Card titles |
| `headingSmall` | `.title3.semibold()` | Subsection labels |
| `bodyLarge` | `.body` | Primary body text |
| `bodyMedium` | `.subheadline` | Secondary body, card descriptions |
| `caption` | `.caption` | Labels, timestamps, metadata |
| `label` | `.caption2.semibold()` | Badges, tags |

### Line spacing and weight
- Use `.fontWeight(.semibold)` for any heading that needs to stand out without `.bold()`
- Long-form coaching notes: `.body` with `.lineSpacing(4)`

---

## 3. Glassmorphism Card Spec

All cards in Stride use a consistent glass card style.

### Standard Glass Card
```swift
// GlassCard.swift
struct GlassCard<Content: View>: View {
    var content: () -> Content

    var body: some View {
        content()
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.5),
                                        Color.stride.lavenderGlow.opacity(0.3)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
                    }
            }
            .shadow(color: Color.stride.lavenderDeep.opacity(0.12), radius: 12, x: 0, y: 4)
    }
}
```

### Card variants
| Variant | Corner Radius | Padding | Usage |
|---|---|---|---|
| Standard | 20pt | 16pt | Dashboard cards, progress cards |
| Compact | 14pt | 12pt | Calendar day cells, badges |
| Hero | 24pt | 20pt | Today's workout card, race countdown |
| Sheet | 24pt (top) | 20pt | Bottom sheets, modals |

---

## 4. Component Specs

### Primary Button (`StrideButton`)
```
Background: Color.stride.lavender (filled) / clear (outline variant)
Text: White (filled) / lavender (outline)
Corner radius: 14pt
Height: 54pt
Font: .body.bold()
Shadow: lavenderDeep.opacity(0.25), radius 8
Pressed state: scale(0.97) + brightness(-0.05)
```

### Secondary Button
```
Background: Color.stride.lavenderLight
Text: Color.stride.lavenderDeep
Corner radius: 14pt
Height: 48pt
```

### Workout Type Badge (`WorkoutTypeBadge`)
```
Background: workoutType.accentColor.opacity(0.15)
Border: workoutType.accentColor.opacity(0.4), 1pt
Text: workoutType.accentColor, .caption.semibold()
Padding: H:10pt V:5pt
Corner radius: 8pt (pill)
```

### RPE Picker
```
Layout: horizontal row of 10 circles (1–10)
Selected: filled lavender circle, white number
Unselected: thin border, gray number
Sizes: 36pt diameter
Labels below: "Easy", "Moderate", "Hard", "Max" at positions 1, 4, 7, 10
```

### Progress Bar
```
Background: Color.stride.lavenderLight
Fill: Color.stride.lavender (animated)
Height: 8pt
Corner radius: 4pt
```

---

## 5. Spacing System

Base unit: **8pt**

| Token | Value | Usage |
|---|---|---|
| `xs` | 4pt | Tight internal padding |
| `sm` | 8pt | Compact spacing between elements |
| `md` | 16pt | Standard card padding, section gaps |
| `lg` | 24pt | Section-level gaps |
| `xl` | 32pt | Major section dividers, hero padding |
| `xxl` | 48pt | Full-screen layouts, onboarding steps |

---

## 6. Iconography

Use SF Symbols exclusively. Never use custom icon assets in v1.

| Context | SF Symbol |
|---|---|
| Home tab | `house.fill` |
| Calendar tab | `calendar` |
| Progress tab | `chart.bar.fill` |
| Profile tab | `person.circle.fill` |
| Log workout FAB | `plus.circle.fill` |
| Easy Run | `figure.run` |
| Long Run | `figure.run.circle.fill` |
| Tempo | `flame.fill` |
| Intervals | `bolt.fill` |
| Strength | `dumbbell.fill` |
| Rest | `moon.fill` |
| Checkmark | `checkmark.circle.fill` |
| Streak | `fire` (custom tint: orange) |
| Heart rate | `heart.fill` |
| Distance | `road.lanes` |
| Duration | `clock.fill` |

---

## 7. Animation Guidelines

### Transitions
- Tab switches: `.easeInOut(duration: 0.2)`
- Sheet presentation: default SwiftUI sheet animation
- Card appear: `.opacity` + `.offset(y: 20)` with `.easeOut(duration: 0.3)`

### Micro-interactions
- Button tap: `scaleEffect(0.97)` on press, spring back on release
- Workout complete toggle: `checkmark.circle.fill` with `.spring(response: 0.4, dampingFraction: 0.6)`
- Progress bar fill: `.animation(.easeInOut(duration: 0.8))`

### Celebration (Long Run / Milestone completion)
Trigger `ConfettiView` overlay when:
- A long run is logged
- The user completes their first workout of the week
- Plan completion hits 25%, 50%, 75%, 100%

```swift
// ConfettiView: uses particle emitter or a lightweight confetti package
// Colours: lavender, lavenderDeep, white, soft gold
// Duration: 2.5 seconds, then auto-dismiss
// Haptic: UINotificationFeedbackGenerator(.success)
```

### Haptics
- Workout logged: `.success` feedback
- Long run complete: `.success` + second `.success` after 0.3s (double tap feel)
- Plan generated: `.success`
- Button tap (primary): `.light` impact
- Error/warning: `.warning`

---

## 8. Onboarding Visual Style

Each onboarding step:
```
Full screen ZStack
├── Background: lavenderLight → white gradient
├── Top: Large SF Symbol (step-specific, lavender tinted)
├── Title: .displayMedium, centered
├── Subtitle: .bodyMedium, .secondary, centered
├── Input area: GlassCard (hero variant)
└── CTA: StrideButton full width, pinned to bottom
```

Progress indicator: horizontal dot/pill row at the top. Active step = lavender pill, others = gray dots.

---

## 9. Logo & App Icon Direction

**Concept:** A stylised footstep or abstract "S" in motion — suggesting forward momentum.

**Recommended approach:**
- Geometric sans-serif "S" with a running stride implied (slight upward arc or speed lines)
- OR: two overlapping footprint impressions forming a path forward
- Colour: lavender (#DAC3E8) on white for the icon, reversed (white on lavender) for dark contexts

**App icon:** Lavender gradient background, white geometric "S" or footstep mark centred.

**Wordmark:** "Stride" in SF Pro Display Bold, tracking +2, all lowercase preferred for approachability.

---

## 10. Dark Mode

Stride supports system dark mode automatically via:
- `.ultraThinMaterial` adapts to dark mode
- All colours use semantic colours (`.primary`, `.secondary`, `Color(.systemBackground)`) where possible
- Custom colours (`Color.stride.*`) need dark mode variants defined in the asset catalog

Dark mode gradient:
```swift
// Dark mode background gradient
LinearGradient(
    colors: [Color(hex: "#1E1A2E"), Color(hex: "#0F0F1A")],  // deep purple-black
    startPoint: .top,
    endPoint: .bottom
)
```

Glass cards in dark mode: `.ultraThinMaterial` naturally handles this — the lavender tint becomes a subtle glow.
