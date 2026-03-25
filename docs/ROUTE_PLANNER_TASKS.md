# Phase 1: Running Route Planner — Claude Code Task Breakdown

> **Revised to match the Stride codebase** — all patterns, naming, architecture, and constraints aligned with `CLAUDE.md` and the existing code.

## How to use this document

Each task below is a standalone prompt for Claude Code. Work through them in order — each builds on the previous. After each task, build and test before moving to the next.

---

## Task 0: Pre-Flight Check

Before starting, give Claude Code this context:

```
Review the Stride project structure and familiarise yourself with:
- The MVVM architecture (Views → ViewModels → Services → Models)
- The SwiftData @Model classes in Core/Models/Models.swift
- The TabView + FAB navigation in ContentView.swift
- The @Observable macro pattern used for all ViewModels (NOT ObservableObject)
- The DesignSystem.swift colour tokens (Color.stride.*)
- The existing service classes in Core/Services/ (e.g. TrainingPlanGenerator)
- The ModelContainer registration in StrideApp.swift

Summarise what you find so we can plan the route planner integration.
```

**Why this matters:** Claude Code will give better results throughout the entire phase if it understands the app's conventions — `@Observable` (not `ObservableObject`), `Color.stride.*` tokens, SwiftData models, dependency injection via init, and the existing tab structure.

---

## Task 1: Location Permission & Core Location Manager

```
Create a LocationManager in Stride/Core/Services/LocationManager.swift.

Requirements:
1. Use @Observable (NOT ObservableObject/@Published — see CLAUDE.md)
2. Request "When In Use" location permission
3. Publish the user's current CLLocation as a property
4. Use kCLActivityTypeFitness for activity type
5. Filter out locations with horizontalAccuracy > 20 meters
6. Provide startTracking() and stopTracking() methods
7. Handle all CLLocationManagerDelegate cases including permission denied
8. Expose an authorizationStatus property so views can react to denied/restricted states

Also update Info.plist with:
- NSLocationWhenInUseUsageDescription: "Used to show your position on the map and plan running routes"

Do NOT add NSLocationAlwaysAndWhenInUseUsageDescription — we only need "when in use" for v1 (no background tracking).

Follow the existing service patterns in Core/Services/ — plain Swift class, no global singletons, designed to be injected via init.
```

**Test checkpoint:** Run on a physical device. Permission prompt should appear. After granting, print location to console to confirm updates flow.

---

## Task 2: Map View with User Location

```
Create a RouteMapView in Stride/Features/Routes/RouteMapView.swift using the iOS 18+ SwiftUI Map API.

Requirements:
1. Accept a LocationManager instance via init (dependency injection)
2. Show the user's current location on the map
3. Centre on the user's location when the view first appears
4. Default zoom: ~500m radius (neighbourhood scale)
5. Add a "recentre" button that animates back to the user's position
6. Use MKStandardMapConfiguration with .mutedStandard style

Integration:
- Add a new "Routes" tab to the TabView in ContentView.swift
- Insert it between the "Plan" and "Progress" tabs
- Use the systemImage "map.fill" and label "Routes"
- Update the Tab enum to include a .routes case
- The Routes tab should show RouteMapView as its root inside a NavigationStack
- Inject LocationManager from the tab level, not created inside the view

Use Color.stride.* tokens for any custom UI. Follow the existing view patterns
(e.g. DashboardView receives profile via init).
```

**Test checkpoint:** You should see the map on the Routes tab, centred on your location with the blue dot. Recentre button works after panning.

---

## Task 3: Route Data Model

```
Create SwiftData models for route persistence in Stride/Core/Models/Route.swift.

Route (@Model class):
- id: UUID
- name: String (default: "Run — " + formatted date)
- createdAt: Date
- updatedAt: Date
- distance: Double (meters)
- estimatedDurationSeconds: Double
- elevationGain: Double? (nil until calculated)
- waypointsData: Data? (encoded [RouteWaypoint] — use the same JSON-in-Data pattern as WorkoutDay.stepsData)
- isFavorite: Bool

RouteWaypoint (value type, Codable — NOT a @Model):
- id: UUID
- latitude: Double
- longitude: Double
- order: Int
- type: WaypointType enum (start, via, end)

Note: Store waypoints as encoded JSON in waypointsData (like WorkoutDay stores steps in stepsData). This avoids a separate SwiftData relationship for coordinate data that changes as a unit. Provide a computed `waypoints` property that encodes/decodes, matching the existing pattern.

Do NOT use Google Polyline encoding — keep it simple with the JSON-in-Data pattern already used throughout the codebase.

Register Route.self in the ModelContainer in StrideApp.swift (add it to the existing `ModelContainer(for:)` call).

Create a RouteService in Stride/Core/Services/RouteService.swift with:
- saveRoute(name:, waypoints: [CLLocationCoordinate2D], distance:, estimatedDuration:) -> Route
- fetchAllRoutes(modelContext:) -> [Route]
- deleteRoute(_:, modelContext:)
- toggleFavorite(_:)

Pass ModelContext via method parameters (consistent with how other services work).
```

**Test checkpoint:** Write a quick test or preview that creates a route with hardcoded coordinates, saves it, fetches it back, and prints the distance. Confirm no SwiftData errors.

---

## Task 4: Tap-to-Place Waypoints

```
Add route creation interaction to RouteMapView.

Requirements:
1. Add a "Create Route" mode toggle button. When active:
   - Tapping the map places a waypoint annotation at that location
   - First tap = start point (green marker)
   - Subsequent taps = via points (use Color.stride.lavenderDeep markers)
   - Show the waypoint order number on each marker

2. As waypoints are added:
   - Draw a MapPolyline connecting them in order
   - Display the running total distance on screen (straight-line for now)
   - Style: 4pt width, Color.stride.lavenderDeep

3. Add "Undo" button — removes the last waypoint
4. Add "Clear" button — removes all waypoints
5. Add "Close Loop" button (appears after 2+ waypoints) — connects last waypoint back to start, calculates total loop distance

Use MapReader and its proxy to convert tap gestures to coordinates.

IMPORTANT: Use the iOS 18+ Map API (Map, MapPolyline, Annotation, MapReader).
Do NOT use MKMapView via UIViewRepresentable.

Extract route creation state into a RouteCreationViewModel (@Observable class) in
Stride/Features/Routes/RouteCreationViewModel.swift — keep the view free of logic.
```

**Test checkpoint:** Tap around on the map. Pins appear with a connecting line. Distance updates. Undo removes the last pin. Close Loop draws back to start.

---

## Task 5: Road-Snapped Distance Calculation

```
Replace straight-line distance with actual road distance using MKDirections.

Requirements:
1. When waypoints are placed, request MKDirections between consecutive waypoints:
   - transportType = .walking (gives road-snapped routes for free)

2. Replace the straight-line MapPolyline with the actual route polyline from MKDirections
3. Update total distance with the sum of all segment distances
4. Cache MKRoute responses — only request the new segment when adding a point

5. Edge cases:
   - MKDirections rate limiting: debounce rapid requests (0.3s delay)
   - Route not found: show an alert, keep straight-line fallback for that segment
   - Loading state: show a subtle spinner while directions are fetched
   - Network unavailable: fall back to straight-line with a note to the user

Put the MKDirections logic in RouteCreationViewModel, not in the view.

Note: MKDirections is free and uses Apple's routing service — no API key needed.
This DOES require network access, which is an exception to the "no networking" rule
in CLAUDE.md — MKDirections is a native MapKit API, not a third-party backend.
```

**Test checkpoint:** Place waypoints along roads. The line should follow the actual road path. Distance should match what you'd expect from a maps app.

---

## Task 6: Route Info Panel

```
Add a route information panel to the route creation flow.

Requirements:
1. Create a bottom sheet (use .sheet with presentationDetents([.fraction(0.25), .medium]))
   that shows:
   - Total distance (formatted per user's unitPreference from UserProfile — km or mi)
   - Estimated time (based on 5:30/km default pace — or use the user's zone2 pace if set)
   - Number of waypoints
   - Elevation: show "—" placeholder (Phase 2)

2. Panel updates in real-time as waypoints are added/removed
3. "Save Route" button at the bottom:
   - Prompt for route name (pre-filled with "Run — [today's date]")
   - Save via RouteService
   - Show confirmation, exit creation mode

4. Style with the existing design system:
   - Use .ultraThinMaterial + Color.stride.lavenderLight tint for the panel background
   - Use StrideButton style for the save button if one exists, otherwise match existing button patterns
   - 20pt corner radius on cards (per CLAUDE.md design rules)

Pass UserProfile into the route feature so unit preferences are respected.
```

**Test checkpoint:** Create a route, check the info panel shows correct numbers, save it, and confirm it persists after restarting the app.

---

## Task 7: Saved Routes List

```
Create a SavedRoutesView in Stride/Features/Routes/SavedRoutesView.swift.

Requirements:
1. Use SwiftData @Query to list all saved routes, sorted by most recent first
2. Each row shows:
   - Route name
   - Distance (formatted per unitPreference)
   - Date created (relative: "Today", "Yesterday", "Mar 15")
   - A small route thumbnail: decode the stored waypoints and draw as a simplified
     Path in a ~50x50pt Canvas, normalised to fit the bounds
   - Favorite indicator (star icon, Color.stride.lavenderDeep when active)

3. Swipe actions:
   - Left: delete (with confirmation alert)
   - Right: toggle favorite

4. Tapping a route navigates to a RouteDetailView that:
   - Shows the route on a full map (decode waypoints, display polyline)
   - Shows route info (distance, estimated time)
   - "Edit" and "Delete" buttons
   - "Share" button (placeholder — just show "Coming soon" toast)

5. Navigation structure:
   - The Routes tab root should be SavedRoutesView (not the map)
   - NavigationStack with a toolbar button to enter route creation (opens RouteMapView)
   - NavigationLink from each row to RouteDetailView

Create a SavedRoutesViewModel (@Observable) and RouteDetailViewModel (@Observable)
for the respective views. Apply glassmorphism card style (.ultraThinMaterial) to list rows
to match the app's visual language.
```

**Test checkpoint:** Save 2–3 routes. Confirm they appear in the list with correct distances and thumbnails. Tap through to detail, delete one, favourite another.

---

## Task 8: Edit Existing Routes

```
Add the ability to edit a saved route.

Requirements:
1. From RouteDetailView, "Edit" opens RouteMapView in edit mode:
   - Pre-populate with the route's saved waypoints
   - Show the existing polyline
   - Centre/zoom the map to fit the entire route

2. In edit mode:
   - Drag existing waypoints to new positions (use draggable Annotations)
   - When dragged, recalculate MKDirections for affected segments only
   - Tap to add new waypoints at the end
   - Long-press a waypoint for a context menu with "Remove"
   - Distance and route info update in real-time

3. Save options:
   - "Save" overwrites the existing Route (same SwiftData record)
   - "Save as New" creates a copy
   - "Cancel" discards changes

The drag interaction should use MapKit's annotation drag support.
Keep all logic in RouteCreationViewModel — add an `editingRoute: Route?` property
to distinguish create vs edit mode.
```

**Test checkpoint:** Open a saved route, drag a waypoint. The route line should update through the new position. Save and confirm changes persist.

---

## Task 9: Live Position During Route View

```
When viewing a saved route in RouteDetailView, show the user's live position.

Requirements:
1. Start LocationManager tracking when the detail view appears
2. Show the user's position on the map alongside the route polyline
3. Add a "Start Run" button that enters active tracking mode:
   - Follow-the-user camera mode
   - Show current pace (rolling 30-second window from CLLocation updates)
   - Show distance covered so far
   - Show progress: "1.2 of 5.0 km" (respect unitPreference)
   - Optionally colour the covered portion of the route differently

4. "Stop Run" ends tracking and shows a simple summary

This is a basic follow-the-route mode — we are NOT recording the GPS track as a
separate entity (that's a future feature).

Stop location tracking in .onDisappear to preserve battery.

Create a RunTrackingViewModel (@Observable) for the active tracking state.
Inject LocationManager — do not create a new one.
```

**Test checkpoint:** Open a saved route near you. Tap "Start Run" and walk a short segment. Position tracks, distance/pace update.

---

## Task 10: Polish & Edge Cases

```
Review the entire route planner feature and address:

1. Empty states:
   - No saved routes: friendly empty state with "Create your first route" CTA
   - No location permission: explanation + button to open Settings (UIApplication.openSettings)

2. Error handling:
   - MKDirections failures: graceful fallback with user-visible message
   - Poor location accuracy: subtle indicator
   - SwiftData save failures: alert the user

3. Performance:
   - Routes with 20+ waypoints: ensure map doesn't lag on polyline redraws
   - MKDirections: debounce during rapid waypoint placement or dragging

4. UX polish:
   - Haptic feedback when placing waypoints (.sensoryFeedback(.impact(weight: .light)))
   - Smooth animations on polyline updates
   - Confirm before discarding unsaved changes (if user taps back with waypoints placed)
   - Show map scale bar and compass when rotated

5. Accessibility:
   - VoiceOver labels on all map controls and waypoint annotations
   - Dynamic Type support on the route info panel and route list

6. Design consistency:
   - All colours use Color.stride.* tokens — no hardcoded hex
   - Cards use glassmorphism style (.ultraThinMaterial + lavender tint + 20pt radius)
   - Typography uses system font (SF Pro) only
   - Spacing follows 16pt base / 8pt multiples

Test the full flow end-to-end: create → save → list → detail → edit → save → start run → stop.
```

**Test checkpoint:** Run through the full flow on a physical device. Everything should feel solid and visually consistent with the rest of Stride.

---

## Phase 1 Complete Checklist

- [x] Location permission granted and tracking works on physical device
- [x] Map displays on the Routes tab with user location
- [x] Can tap to place waypoints in creation mode
- [x] Polyline follows actual roads (MKDirections snapping)
- [x] Distance calculates correctly (respects user's unit preference)
- [x] Can undo / clear waypoints
- [x] Can close loop back to start (isLoop persisted on Route model)
- [x] Route info panel shows distance and estimated time
- [x] Routes save to SwiftData and persist across app launches
- [x] Route.self registered in ModelContainer in StrideApp.swift
- [x] Saved routes list displays with thumbnails (road-snapped polylines)
- [x] Can tap into route detail view (road-snapped polylines displayed)
- [x] Can edit an existing route (drag waypoints, add/remove)
- [x] Road-snapped polylines persist and restore on save/edit (polylineData + segmentPolylinesData)
- [ ] Live position shows when viewing a route
- [ ] Basic "Start Run" mode with distance tracking
- [ ] Empty states and error handling are in place
- [x] No crashes on the happy path
- [x] All ViewModels use @Observable (not ObservableObject)
- [x] All colours use Color.stride.* tokens
- [ ] No third-party dependencies added

---

## Tips for Working with Claude Code on This

1. **After each task, commit.** If a later task breaks something, you can easily roll back.

2. **Build frequently.** "Build the project and fix any errors" is a great follow-up prompt.

3. **Test on device** for Tasks 1, 2, 5, 9. The simulator's GPS simulation is limited. For other tasks, the simulator works.

4. **If Claude generates `ObservableObject` / `@Published`**, redirect: "Use @Observable macro, not ObservableObject — see CLAUDE.md."

5. **If Claude generates UIViewRepresentable MapKit code**, redirect: "Use the iOS 18+ SwiftUI Map API with MapReader, not UIViewRepresentable."

6. **If Claude uses hardcoded colours**, redirect: "Use Color.stride.* tokens from DesignSystem.swift — no hardcoded hex in views."

7. **If a task gets stuck**, break it into sub-tasks. Example for Task 5: "First get MKDirections working between two hardcoded points and print the result" → then "Integrate with the waypoint placement flow."

8. **Share errors verbatim.** Paste the full Xcode error rather than describing it.

---

## File Placement Summary

```
Stride/
├── StrideApp.swift                          ← register Route.self in ModelContainer
├── ContentView.swift                        ← add Routes tab
│
├── Core/
│   ├── Models/
│   │   └── Route.swift                      ← Route @Model + RouteWaypoint value type
│   └── Services/
│       ├── LocationManager.swift            ← @Observable, CLLocationManagerDelegate
│       └── RouteService.swift               ← CRUD operations for Route
│
└── Features/
    └── Routes/
        ├── SavedRoutesView.swift            ← list of saved routes (tab root)
        ├── SavedRoutesViewModel.swift       ← @Observable
        ├── RouteMapView.swift               ← map + waypoint placement
        ├── RouteCreationViewModel.swift     ← @Observable, create/edit logic
        ├── RouteDetailView.swift            ← view a single route
        ├── RouteDetailViewModel.swift       ← @Observable
        ├── RunTrackingViewModel.swift       ← @Observable, live run tracking
        └── Components/
            ├── RouteInfoPanel.swift          ← bottom sheet with route stats
            ├── RouteThumbnail.swift          ← small path rendering for list rows
            └── WaypointAnnotation.swift      ← custom map annotation view
```
