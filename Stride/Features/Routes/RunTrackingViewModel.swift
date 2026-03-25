import Foundation
import CoreLocation
import MapKit

@Observable
final class RunTrackingViewModel {

    // MARK: - Constants

    /// Distance threshold (meters) — user is considered "at the start" within this radius.
    static let startProximityThreshold: Double = 200

    // MARK: - Dependencies

    private let locationManager: LocationManager
    private let routeDistance: Double
    private let unitSystem: UnitSystem
    private let startCoordinate: CLLocationCoordinate2D?
    private let isLoop: Bool

    // MARK: - Proximity State

    /// Distance in meters from the user's current position to the route start.
    var distanceToStart: Double?

    /// Whether the user is close enough to the start to begin the run.
    var isNearStart: Bool {
        guard let distance = distanceToStart else { return false }
        return distance <= Self.startProximityThreshold
    }

    // MARK: - Tracking State

    var isTracking = false
    var distanceCovered: Double = 0
    var elapsedSeconds: TimeInterval = 0
    var currentPace: Double? // seconds per km

    // MARK: - Summary State

    var showSummary = false
    private(set) var summaryDistance: Double = 0
    private(set) var summaryDuration: TimeInterval = 0
    private(set) var summaryPace: Double?

    // MARK: - Private

    private var recentLocations: [CLLocation] = []
    private var lastTrackedLocation: CLLocation?
    private var startTime: Date?
    private var timer: Timer?

    // MARK: - Init

    init(
        locationManager: LocationManager,
        routeDistance: Double,
        unitSystem: UnitSystem,
        startCoordinate: CLLocationCoordinate2D?,
        isLoop: Bool
    ) {
        self.locationManager = locationManager
        self.routeDistance = routeDistance
        self.unitSystem = unitSystem
        self.startCoordinate = startCoordinate
        self.isLoop = isLoop

        // Calculate initial distance to start
        updateDistanceToStart(from: locationManager.currentLocation)
    }

    // MARK: - Public API

    func startRun() {
        isTracking = true
        distanceCovered = 0
        elapsedSeconds = 0
        currentPace = nil
        recentLocations = []
        lastTrackedLocation = locationManager.currentLocation
        startTime = Date()
        showSummary = false

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stopRun() {
        isTracking = false
        timer?.invalidate()
        timer = nil

        summaryDistance = distanceCovered
        summaryDuration = elapsedSeconds
        summaryPace = elapsedSeconds > 0 && distanceCovered > 0
            ? (elapsedSeconds / distanceCovered) * 1000
            : nil
        showSummary = true
    }

    func dismissSummary() {
        showSummary = false
    }

    /// Call from the view whenever locationManager.currentLocation changes.
    func locationDidUpdate(_ location: CLLocation) {
        updateDistanceToStart(from: location)

        guard isTracking else { return }

        if let last = lastTrackedLocation {
            let delta = location.distance(from: last)
            // Ignore jumps > 50m (GPS glitch) or tiny movements < 1m
            if delta > 1 && delta < 50 {
                distanceCovered += delta
            }
        }
        lastTrackedLocation = location

        // Keep a rolling 30-second window for pace calculation
        recentLocations.append(location)
        let cutoff = Date().addingTimeInterval(-30)
        recentLocations.removeAll { $0.timestamp < cutoff }
        updatePace()
    }

    // MARK: - Formatting

    var formattedDistance: String {
        switch unitSystem {
        case .kilometers:
            return String(format: "%.2f km", distanceCovered / 1000)
        case .miles:
            return String(format: "%.2f mi", distanceCovered / 1609.344)
        }
    }

    var progressText: String {
        let covered: String
        let total: String
        switch unitSystem {
        case .kilometers:
            covered = String(format: "%.1f", distanceCovered / 1000)
            total = String(format: "%.1f km", routeDistance / 1000)
        case .miles:
            covered = String(format: "%.1f", distanceCovered / 1609.344)
            total = String(format: "%.1f mi", routeDistance / 1609.344)
        }
        return "\(covered) of \(total)"
    }

    var formattedPace: String {
        guard let pace = currentPace else { return "--:--" }
        let unit = unitSystem == .kilometers ? "/km" : "/mi"
        let paceForUnit = unitSystem == .miles ? pace * 1.60934 : pace
        let minutes = Int(paceForUnit) / 60
        let seconds = Int(paceForUnit) % 60
        return String(format: "%d:%02d%@", minutes, seconds, unit)
    }

    var formattedElapsed: String {
        let minutes = Int(elapsedSeconds) / 60
        let seconds = Int(elapsedSeconds) % 60
        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return String(format: "%d:%02d:%02d", hours, remainingMinutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    var formattedSummaryPace: String {
        guard let pace = summaryPace else { return "--:--" }
        let unit = unitSystem == .kilometers ? "/km" : "/mi"
        let paceForUnit = unitSystem == .miles ? pace * 1.60934 : pace
        let minutes = Int(paceForUnit) / 60
        let seconds = Int(paceForUnit) % 60
        return String(format: "%d:%02d%@", minutes, seconds, unit)
    }

    var formattedSummaryDistance: String {
        switch unitSystem {
        case .kilometers:
            return String(format: "%.2f km", summaryDistance / 1000)
        case .miles:
            return String(format: "%.2f mi", summaryDistance / 1609.344)
        }
    }

    var formattedSummaryDuration: String {
        let minutes = Int(summaryDuration) / 60
        let seconds = Int(summaryDuration) % 60
        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return String(format: "%dh %02dm %02ds", hours, remainingMinutes, seconds)
        }
        return String(format: "%dm %02ds", minutes, seconds)
    }

    /// Whether the start-proximity gate should be shown.
    var needsNavigateToStart: Bool {
        !isNearStart
    }

    var formattedDistanceToStart: String {
        guard let distance = distanceToStart else { return "—" }
        switch unitSystem {
        case .kilometers:
            if distance < 1000 {
                return String(format: "%.0f m away", distance)
            }
            return String(format: "%.1f km away", distance / 1000)
        case .miles:
            let miles = distance / 1609.344
            if miles < 0.1 {
                let feet = distance * 3.28084
                return String(format: "%.0f ft away", feet)
            }
            return String(format: "%.1f mi away", miles)
        }
    }

    /// Opens Apple Maps with walking directions to the route start.
    func openDirectionsToStart() {
        guard let coord = startCoordinate else { return }
        let placemark = MKPlacemark(coordinate: coord)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = "Route Start"
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
        ])
    }

    // MARK: - Private

    private func updateDistanceToStart(from location: CLLocation?) {
        guard let location, let startCoord = startCoordinate else {
            distanceToStart = nil
            return
        }
        let startLocation = CLLocation(latitude: startCoord.latitude, longitude: startCoord.longitude)
        distanceToStart = location.distance(from: startLocation)
    }

    private func tick() {
        guard let start = startTime else { return }
        elapsedSeconds = Date().timeIntervalSince(start)
    }

    private func updatePace() {
        guard recentLocations.count >= 2,
              let first = recentLocations.first,
              let last = recentLocations.last else {
            return
        }

        let timeDelta = last.timestamp.timeIntervalSince(first.timestamp)
        guard timeDelta > 5 else { return } // need at least 5s of data

        var windowDistance: Double = 0
        for i in 1..<recentLocations.count {
            windowDistance += recentLocations[i].distance(from: recentLocations[i - 1])
        }

        guard windowDistance > 0 else { return }

        // pace in seconds per km
        currentPace = (timeDelta / windowDistance) * 1000
    }
}
