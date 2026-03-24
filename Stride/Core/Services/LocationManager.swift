import Foundation
import CoreLocation

@Observable
final class LocationManager: NSObject {
    static let shared = LocationManager()

    // MARK: - Published State

    var currentLocation: CLLocation?
    var authorizationStatus: CLAuthorizationStatus
    var isTracking = false
    var locationError: String?

    // MARK: - Private

    private let manager = CLLocationManager()

    // MARK: - Init

    private override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    // MARK: - Public API

    /// Requests "When In Use" location permission. Safe to call multiple times.
    func requestAuthorisation() {
        guard authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    /// Begins receiving location updates. Filters inaccurate readings (>20m).
    func startTracking() {
        guard authorizationStatus == .authorizedWhenInUse ||
              authorizationStatus == .authorizedAlways else {
            locationError = "Location permission not granted."
            return
        }
        locationError = nil
        isTracking = true
        manager.startUpdatingLocation()
    }

    /// Stops receiving location updates.
    func stopTracking() {
        isTracking = false
        manager.stopUpdatingLocation()
    }

    // MARK: - Helpers

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Filter out inaccurate readings
        guard let location = locations.last,
              location.horizontalAccuracy <= 20 else { return }
        currentLocation = location
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            locationError = nil
        case .denied:
            locationError = "Location access denied. Enable it in Settings to plan routes."
            stopTracking()
        case .restricted:
            locationError = "Location access is restricted on this device."
            stopTracking()
        case .notDetermined:
            locationError = nil
        @unknown default:
            locationError = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let clError = error as? CLError else { return }
        switch clError.code {
        case .denied:
            locationError = "Location access denied."
            stopTracking()
        case .locationUnknown:
            // Temporary — system will retry automatically
            break
        default:
            locationError = "Location error: \(clError.localizedDescription)"
        }
    }
}
