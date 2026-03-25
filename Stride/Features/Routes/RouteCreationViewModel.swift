import Foundation
import MapKit
import SwiftData

@Observable
final class RouteCreationViewModel {

    // MARK: - State

    var waypoints: [RouteWaypoint] = []
    var isCreating = false
    var isLoopClosed = false
    /// Number of segment direction requests currently in flight.
    private var loadingSegmentCount = 0

    var isLoadingSegment: Bool { loadingSegmentCount > 0 }
    var isLoadingElevation = false
    var elevationGain: Double?
    var routeError: String?

    /// Non-nil when editing an existing route.
    var editingRoute: Route?

    /// True when in edit mode (vs create mode).
    var isEditing: Bool { editingRoute != nil }

    // MARK: - Location Search

    let searchService = LocationSearchService()
    var isSearchExpanded = false
    var isResolvingSearch = false

    // MARK: - Segment Cache

    /// Cached MKRoute for each segment (keyed by "fromOrder-toOrder").
    /// When the loop is closed, the closing segment uses key "loop".
    private var segmentRoutes: [String: MKRoute] = [:]

    /// Tracks whether a segment fell back to straight-line.
    private var straightLineFallbacks: Set<String> = []

    /// Cached polyline coordinates restored from a saved route (used until MKDirections replaces them).
    private var restoredSegmentPolylines: [String: [CLLocationCoordinate2D]] = [:]

    /// Per-segment debounce work items for directions requests.
    private var pendingDirectionsWork: [String: DispatchWorkItem] = [:]

    /// Debounce work item for elevation requests.
    private var pendingElevationWork: DispatchWorkItem?

    /// Service for fetching elevation data.
    private let elevationService = ElevationService()

    // MARK: - Computed — Polyline Coordinates

    /// Returns the full set of coordinates for display, preferring road-snapped
    /// segments where available, falling back to straight lines.
    var polylineCoordinates: [[CLLocationCoordinate2D]] {
        let sorted = waypoints.sorted { $0.order < $1.order }
        guard sorted.count >= 2 else { return [] }

        var segments: [[CLLocationCoordinate2D]] = []

        for i in 1..<sorted.count {
            let key = segmentKey(from: sorted[i - 1].order, to: sorted[i].order)
            if let route = segmentRoutes[key] {
                segments.append(route.polyline.coordinates)
            } else if let restored = restoredSegmentPolylines[key] {
                segments.append(restored)
            } else {
                // Straight-line fallback
                let from = CLLocationCoordinate2D(latitude: sorted[i - 1].latitude, longitude: sorted[i - 1].longitude)
                let to = CLLocationCoordinate2D(latitude: sorted[i].latitude, longitude: sorted[i].longitude)
                segments.append([from, to])
            }
        }

        if isLoopClosed, let first = sorted.first, let last = sorted.last {
            let key = "loop"
            if let route = segmentRoutes[key] {
                segments.append(route.polyline.coordinates)
            } else if let restored = restoredSegmentPolylines[key] {
                segments.append(restored)
            } else {
                let from = CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude)
                let to = CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude)
                segments.append([from, to])
            }
        }

        return segments
    }

    /// Flat list of all coordinates for simple polyline rendering.
    var flatPolylineCoordinates: [CLLocationCoordinate2D] {
        polylineCoordinates.flatMap { $0 }
    }

    // MARK: - Computed — Distance

    /// True when the user has not yet modified any segments since loading.
    private var hasModifiedSegments = false

    var totalDistanceMeters: Double {
        // If editing and nothing has changed, use the exact saved distance.
        if let saved = editingRoute?.distance, !hasModifiedSegments {
            return saved
        }

        let sorted = waypoints.sorted { $0.order < $1.order }
        guard sorted.count >= 2 else { return 0 }

        var total: Double = 0

        for i in 1..<sorted.count {
            let key = segmentKey(from: sorted[i - 1].order, to: sorted[i].order)
            if let route = segmentRoutes[key] {
                total += route.distance
            } else if let restored = restoredSegmentPolylines[key], restored.count >= 2 {
                total += distanceAlongCoordinates(restored)
            } else {
                let from = CLLocation(latitude: sorted[i - 1].latitude, longitude: sorted[i - 1].longitude)
                let to = CLLocation(latitude: sorted[i].latitude, longitude: sorted[i].longitude)
                total += from.distance(from: to)
            }
        }

        if isLoopClosed, let first = sorted.first, let last = sorted.last {
            if let route = segmentRoutes["loop"] {
                total += route.distance
            } else if let restored = restoredSegmentPolylines["loop"], restored.count >= 2 {
                total += distanceAlongCoordinates(restored)
            } else {
                let from = CLLocation(latitude: last.latitude, longitude: last.longitude)
                let to = CLLocation(latitude: first.latitude, longitude: first.longitude)
                total += from.distance(from: to)
            }
        }

        return total
    }

    /// Sum the distance along a sequence of coordinates (road-snapped polyline).
    private func distanceAlongCoordinates(_ coords: [CLLocationCoordinate2D]) -> Double {
        var total: Double = 0
        for i in 1..<coords.count {
            let from = CLLocation(latitude: coords[i - 1].latitude, longitude: coords[i - 1].longitude)
            let to = CLLocation(latitude: coords[i].latitude, longitude: coords[i].longitude)
            total += from.distance(from: to)
        }
        return total
    }

    var formattedDistance: String {
        let km = totalDistanceMeters / 1000
        if km < 1 {
            return String(format: "%0.0f m", totalDistanceMeters)
        }
        return String(format: "%.2f km", km)
    }

    var hasStraightLineFallback: Bool {
        !straightLineFallbacks.isEmpty
    }

    var canCloseLoop: Bool {
        waypoints.count >= 2 && !isLoopClosed
    }

    var canUndo: Bool {
        !waypoints.isEmpty
    }

    // MARK: - Actions

    func startCreating() {
        isCreating = true
        waypoints = []
        isLoopClosed = false
        segmentRoutes = [:]
        straightLineFallbacks = []
        routeError = nil
        elevationGain = nil
        isLoadingElevation = false
        loadingSegmentCount = 0
        hasModifiedSegments = false
    }

    func stopCreating() {
        isCreating = false
        editingRoute = nil
        waypoints = []
        isLoopClosed = false
        segmentRoutes = [:]
        straightLineFallbacks = []
        routeError = nil
        elevationGain = nil
        isLoadingElevation = false
        loadingSegmentCount = 0
        hasModifiedSegments = false
        pendingDirectionsWork.values.forEach { $0.cancel() }
        pendingDirectionsWork = [:]
        pendingElevationWork?.cancel()
        searchService.clear()
        isSearchExpanded = false
    }

    // MARK: - Edit Mode

    /// Load an existing route for editing.
    func loadRoute(_ route: Route) {
        editingRoute = route
        isCreating = true
        isLoopClosed = route.isLoop
        segmentRoutes = [:]
        straightLineFallbacks = []
        restoredSegmentPolylines = [:]
        routeError = nil

        waypoints = route.waypoints.sorted { $0.order < $1.order }

        // Restore saved segment polylines if available
        let savedSegments = route.segmentPolylines
        if !savedSegments.isEmpty {
            for (key, coords) in savedSegments {
                restoredSegmentPolylines[key] = coords.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                }
            }
        } else {
            // Fallback: re-request directions if no saved segments
            for i in 1..<waypoints.count {
                let from = waypoints[i - 1]
                let to = waypoints[i]
                let key = segmentKey(from: from.order, to: to.order)
                requestDirectionsDebounced(
                    from: CLLocationCoordinate2D(latitude: from.latitude, longitude: from.longitude),
                    to: CLLocationCoordinate2D(latitude: to.latitude, longitude: to.longitude),
                    key: key
                )
            }
            if isLoopClosed, let first = waypoints.first, let last = waypoints.last {
                requestDirectionsDebounced(
                    from: CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude),
                    to: CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude),
                    key: "loop"
                )
            }
        }
    }

    /// Move a waypoint to a new position and recalculate affected segments.
    func moveWaypoint(id: UUID, to coordinate: CLLocationCoordinate2D) {
        guard let index = waypoints.firstIndex(where: { $0.id == id }) else { return }
        hasModifiedSegments = true

        waypoints[index] = RouteWaypoint(
            id: waypoints[index].id,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            order: waypoints[index].order,
            type: waypoints[index].type
        )

        let sorted = waypoints.sorted { $0.order < $1.order }
        guard let sortedIndex = sorted.firstIndex(where: { $0.id == id }) else { return }

        // Recalculate segment before this waypoint
        if sortedIndex > 0 {
            let prev = sorted[sortedIndex - 1]
            let current = sorted[sortedIndex]
            let key = segmentKey(from: prev.order, to: current.order)
            segmentRoutes.removeValue(forKey: key)
            restoredSegmentPolylines.removeValue(forKey: key)
            straightLineFallbacks.remove(key)
            requestDirectionsDebounced(
                from: CLLocationCoordinate2D(latitude: prev.latitude, longitude: prev.longitude),
                to: CLLocationCoordinate2D(latitude: current.latitude, longitude: current.longitude),
                key: key
            )
        }

        // Recalculate segment after this waypoint
        if sortedIndex < sorted.count - 1 {
            let current = sorted[sortedIndex]
            let next = sorted[sortedIndex + 1]
            let key = segmentKey(from: current.order, to: next.order)
            segmentRoutes.removeValue(forKey: key)
            restoredSegmentPolylines.removeValue(forKey: key)
            straightLineFallbacks.remove(key)
            requestDirectionsDebounced(
                from: CLLocationCoordinate2D(latitude: current.latitude, longitude: current.longitude),
                to: CLLocationCoordinate2D(latitude: next.latitude, longitude: next.longitude),
                key: key
            )
        }

        // Recalculate loop segment if applicable
        if isLoopClosed, let first = sorted.first, let last = sorted.last,
           (sortedIndex == 0 || sortedIndex == sorted.count - 1) {
            segmentRoutes.removeValue(forKey: "loop")
            restoredSegmentPolylines.removeValue(forKey: "loop")
            straightLineFallbacks.remove("loop")
            requestDirectionsDebounced(
                from: CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude),
                to: CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude),
                key: "loop"
            )
        }
    }

    /// Remove a waypoint by ID and recalculate surrounding segments.
    func removeWaypoint(id: UUID) {
        guard let index = waypoints.firstIndex(where: { $0.id == id }) else { return }
        hasModifiedSegments = true
        guard waypoints.count > 2 else {
            routeError = "A route needs at least 2 waypoints."
            return
        }

        let sorted = waypoints.sorted { $0.order < $1.order }
        guard let sortedIndex = sorted.firstIndex(where: { $0.id == id }) else { return }
        let removed = sorted[sortedIndex]

        // Build a map from old waypoint ID to old order (before removal)
        let oldOrderByID = Dictionary(uniqueKeysWithValues: sorted.map { ($0.id, $0.order) })

        // Remove old segments connected to this waypoint
        if sortedIndex > 0 {
            let key = segmentKey(from: sorted[sortedIndex - 1].order, to: removed.order)
            segmentRoutes.removeValue(forKey: key)
            restoredSegmentPolylines.removeValue(forKey: key)
            straightLineFallbacks.remove(key)
        }
        if sortedIndex < sorted.count - 1 {
            let key = segmentKey(from: removed.order, to: sorted[sortedIndex + 1].order)
            segmentRoutes.removeValue(forKey: key)
            restoredSegmentPolylines.removeValue(forKey: key)
            straightLineFallbacks.remove(key)
        }

        waypoints.remove(at: index)

        // Re-number waypoints
        let resorted = waypoints.sorted { $0.order < $1.order }
        waypoints = resorted.enumerated().map { i, wp in
            RouteWaypoint(
                id: wp.id,
                latitude: wp.latitude,
                longitude: wp.longitude,
                order: i,
                type: i == 0 ? .start : (i == resorted.count - 1 ? .end : .via)
            )
        }

        // Re-key surviving segment caches from old order keys to new order keys
        let newOrderByID = Dictionary(uniqueKeysWithValues: waypoints.map { ($0.id, $0.order) })
        let newSorted = waypoints.sorted { $0.order < $1.order }

        var updatedSegmentRoutes: [String: MKRoute] = [:]
        var updatedRestoredPolylines: [String: [CLLocationCoordinate2D]] = [:]
        var updatedFallbacks: Set<String> = []

        for i in 1..<newSorted.count {
            let prevID = newSorted[i - 1].id
            let currID = newSorted[i].id
            guard let oldPrevOrder = oldOrderByID[prevID],
                  let oldCurrOrder = oldOrderByID[currID] else { continue }
            let oldKey = segmentKey(from: oldPrevOrder, to: oldCurrOrder)
            let newKey = segmentKey(from: newSorted[i - 1].order, to: newSorted[i].order)

            if let route = segmentRoutes[oldKey] {
                updatedSegmentRoutes[newKey] = route
            }
            if let restored = restoredSegmentPolylines[oldKey] {
                updatedRestoredPolylines[newKey] = restored
            }
            if straightLineFallbacks.contains(oldKey) {
                updatedFallbacks.insert(newKey)
            }
        }

        // Preserve loop segment (key doesn't depend on order)
        if let loopRoute = segmentRoutes["loop"] {
            updatedSegmentRoutes["loop"] = loopRoute
        }
        if let loopRestored = restoredSegmentPolylines["loop"] {
            updatedRestoredPolylines["loop"] = loopRestored
        }
        if straightLineFallbacks.contains("loop") {
            updatedFallbacks.insert("loop")
        }

        segmentRoutes = updatedSegmentRoutes
        restoredSegmentPolylines = updatedRestoredPolylines
        straightLineFallbacks = updatedFallbacks

        // Request directions for the newly connected segment (where the gap was)
        if sortedIndex > 0 && sortedIndex < newSorted.count {
            let prev = newSorted[sortedIndex - 1]
            let next = newSorted[sortedIndex]
            let key = segmentKey(from: prev.order, to: next.order)
            requestDirectionsDebounced(
                from: CLLocationCoordinate2D(latitude: prev.latitude, longitude: prev.longitude),
                to: CLLocationCoordinate2D(latitude: next.latitude, longitude: next.longitude),
                key: key
            )
        }
    }

    /// Update the existing route in SwiftData.
    func updateRoute(_ route: Route) {
        let paceSecondsPerMeter = 5.5 * 60.0 / 1000.0
        route.distance = totalDistanceMeters
        route.estimatedDurationSeconds = totalDistanceMeters * paceSecondsPerMeter
        route.isLoop = isLoopClosed
        route.waypoints = waypoints.sorted { $0.order < $1.order }
        route.polylineCoordinates = flatPolylineCoordinates.map {
            PolylineCoordinate(latitude: $0.latitude, longitude: $0.longitude)
        }
        route.segmentPolylines = currentSegmentPolylines
        route.updatedAt = Date()
    }

    /// Save current waypoints as a new route copy.
    func saveAsNewRoute(name: String, modelContext: ModelContext) -> Route {
        let sorted = waypoints.sorted { $0.order < $1.order }
        let coordinates = sorted.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        let paceSecondsPerMeter = 5.5 * 60.0 / 1000.0
        let estimatedDuration = totalDistanceMeters * paceSecondsPerMeter

        let routeWaypoints = coordinates.enumerated().map { index, coord in
            let type: WaypointType
            if index == 0 {
                type = .start
            } else if index == coordinates.count - 1 && !isLoopClosed {
                type = .end
            } else {
                type = .via
            }
            return RouteWaypoint(
                latitude: coord.latitude,
                longitude: coord.longitude,
                order: index,
                type: type
            )
        }

        let polyline = flatPolylineCoordinates.map {
            PolylineCoordinate(latitude: $0.latitude, longitude: $0.longitude)
        }
        let newRoute = Route(
            name: name,
            distance: totalDistanceMeters,
            estimatedDurationSeconds: estimatedDuration,
            waypoints: routeWaypoints,
            isLoop: isLoopClosed
        )
        newRoute.polylineCoordinates = polyline
        newRoute.segmentPolylines = currentSegmentPolylines
        modelContext.insert(newRoute)
        return newRoute
    }

    /// Resolve a search result and add it as a waypoint. Returns the coordinate for map centering.
    @MainActor
    func selectSearchResult(_ completion: MKLocalSearchCompletion) async -> CLLocationCoordinate2D? {
        isResolvingSearch = true
        defer { isResolvingSearch = false }

        guard let coordinate = await searchService.resolve(completion) else {
            routeError = "Could not find location."
            return nil
        }

        addWaypoint(at: coordinate)
        searchService.clear()
        isSearchExpanded = false
        return coordinate
    }

    func addWaypoint(at coordinate: CLLocationCoordinate2D) {
        guard isCreating, !isLoopClosed else { return }
        hasModifiedSegments = true
        let type: WaypointType = waypoints.isEmpty ? .start : .via
        let waypoint = RouteWaypoint(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            order: waypoints.count,
            type: type
        )
        waypoints.append(waypoint)

        // Request directions for the new segment (if we have at least 2 waypoints)
        if waypoints.count >= 2 {
            let fromWaypoint = waypoints[waypoints.count - 2]
            let toWaypoint = waypoint
            let key = segmentKey(from: fromWaypoint.order, to: toWaypoint.order)
            requestDirectionsDebounced(
                from: CLLocationCoordinate2D(latitude: fromWaypoint.latitude, longitude: fromWaypoint.longitude),
                to: CLLocationCoordinate2D(latitude: toWaypoint.latitude, longitude: toWaypoint.longitude),
                key: key
            )
        }
    }

    func undoLastWaypoint() {
        guard !waypoints.isEmpty else { return }
        if isLoopClosed {
            isLoopClosed = false
            segmentRoutes.removeValue(forKey: "loop")
            straightLineFallbacks.remove("loop")
            return
        }

        let removed = waypoints.removeLast()
        // Remove the segment that connected to this waypoint
        if !waypoints.isEmpty {
            let key = segmentKey(from: waypoints.last?.order ?? 0, to: removed.order)
            segmentRoutes.removeValue(forKey: key)
            straightLineFallbacks.remove(key)
        }
        routeError = nil
    }

    func clearWaypoints() {
        waypoints = []
        isLoopClosed = false
        segmentRoutes = [:]
        straightLineFallbacks = []
        restoredSegmentPolylines = [:]
        routeError = nil
        pendingDirectionsWork.values.forEach { $0.cancel() }
        pendingDirectionsWork = [:]
        pendingElevationWork?.cancel()
    }

    func closeLoop() {
        guard canCloseLoop else { return }
        hasModifiedSegments = true
        isLoopClosed = true

        guard let first = waypoints.first, let last = waypoints.last else { return }
        requestDirectionsDebounced(
            from: CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude),
            to: CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude),
            key: "loop"
        )
    }

    /// Builds a dictionary of segment polylines from current state for persistence.
    var currentSegmentPolylines: [String: [PolylineCoordinate]] {
        let sorted = waypoints.sorted { $0.order < $1.order }
        var result: [String: [PolylineCoordinate]] = [:]

        for i in 1..<sorted.count {
            let key = segmentKey(from: sorted[i - 1].order, to: sorted[i].order)
            if let route = segmentRoutes[key] {
                result[key] = route.polyline.coordinates.map {
                    PolylineCoordinate(latitude: $0.latitude, longitude: $0.longitude)
                }
            } else if let restored = restoredSegmentPolylines[key] {
                result[key] = restored.map {
                    PolylineCoordinate(latitude: $0.latitude, longitude: $0.longitude)
                }
            }
        }

        if isLoopClosed {
            let key = "loop"
            if let route = segmentRoutes[key] {
                result[key] = route.polyline.coordinates.map {
                    PolylineCoordinate(latitude: $0.latitude, longitude: $0.longitude)
                }
            } else if let restored = restoredSegmentPolylines[key] {
                result[key] = restored.map {
                    PolylineCoordinate(latitude: $0.latitude, longitude: $0.longitude)
                }
            }
        }

        return result
    }

    // MARK: - Elevation

    var formattedElevation: String {
        if isLoadingElevation { return "Calculating..." }
        guard let gain = elevationGain else { return "" }
        return String(format: "%.0f m gain", gain)
    }

    /// Fetch elevation gain for the current polyline. Call before saving.
    @MainActor
    func fetchElevation() async {
        let coords = flatPolylineCoordinates
        guard coords.count >= 2 else {
            elevationGain = nil
            return
        }

        isLoadingElevation = true
        do {
            let result = try await elevationService.fetchElevation(for: coords)
            elevationGain = result.gain
        } catch {
            // Non-fatal — elevation is optional, route still saves
            elevationGain = nil
        }
        isLoadingElevation = false
    }

    /// Debounced elevation fetch — called after segments finish loading.
    func fetchElevationDebounced() {
        pendingElevationWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.fetchElevation()
            }
        }
        pendingElevationWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    // MARK: - MKDirections

    private func segmentKey(from: Int, to: Int) -> String {
        "\(from)-\(to)"
    }

    private func requestDirectionsDebounced(
        from source: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        key: String
    ) {
        pendingDirectionsWork[key]?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingDirectionsWork.removeValue(forKey: key)
            Task { @MainActor in
                await self.fetchDirections(from: source, to: destination, key: key)
            }
        }
        pendingDirectionsWork[key] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    @MainActor
    private func fetchDirections(
        from source: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        key: String
    ) async {
        // Skip if already cached
        guard segmentRoutes[key] == nil else { return }

        loadingSegmentCount += 1
        routeError = nil

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: source))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .walking

        let directions = MKDirections(request: request)

        do {
            let response = try await directions.calculate()
            if let route = response.routes.first {
                segmentRoutes[key] = route
                straightLineFallbacks.remove(key)
            } else {
                straightLineFallbacks.insert(key)
            }
        } catch {
            straightLineFallbacks.insert(key)
            if let mkError = error as? MKError {
                switch mkError.code {
                case .directionsNotFound:
                    routeError = "No walking route found for this segment."
                case .placemarkNotFound:
                    routeError = "Could not locate one of the waypoints."
                default:
                    routeError = "Route unavailable — using straight line."
                }
            } else {
                routeError = "Network unavailable — using straight line."
            }
        }

        loadingSegmentCount = max(loadingSegmentCount - 1, 0)
        fetchElevationDebounced()
    }
}

// MARK: - MKPolyline Coordinate Extraction

private extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}
