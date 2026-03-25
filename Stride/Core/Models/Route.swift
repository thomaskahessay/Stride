import Foundation
import SwiftData

// MARK: - Route

@Model
final class Route {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var distance: Double // meters
    var estimatedDurationSeconds: Double
    var elevationGain: Double?
    var waypointsData: Data?
    var polylineData: Data?
    var segmentPolylinesData: Data?
    var isLoop: Bool
    var isFavorite: Bool

    init(
        name: String? = nil,
        distance: Double = 0,
        estimatedDurationSeconds: Double = 0,
        elevationGain: Double? = nil,
        waypoints: [RouteWaypoint] = [],
        isLoop: Bool = false,
        isFavorite: Bool = false
    ) {
        let now = Date()
        self.id = UUID()
        self.name = name ?? Route.defaultName(for: now)
        self.createdAt = now
        self.updatedAt = now
        self.distance = distance
        self.estimatedDurationSeconds = estimatedDurationSeconds
        self.elevationGain = elevationGain
        self.isLoop = isLoop
        self.isFavorite = isFavorite
        self.waypoints = waypoints
    }

    var waypoints: [RouteWaypoint] {
        get {
            guard let data = waypointsData else { return [] }
            return (try? JSONDecoder().decode([RouteWaypoint].self, from: data)) ?? []
        }
        set {
            waypointsData = try? JSONEncoder().encode(newValue)
        }
    }

    /// The road-snapped polyline coordinates for rendering.
    /// Falls back to waypoint coordinates if no polyline was saved.
    var polylineCoordinates: [PolylineCoordinate] {
        get {
            guard let data = polylineData else { return [] }
            return (try? JSONDecoder().decode([PolylineCoordinate].self, from: data)) ?? []
        }
        set {
            polylineData = try? JSONEncoder().encode(newValue)
        }
    }

    /// Per-segment polylines keyed by segment key (e.g. "0-1", "loop").
    /// Used to restore road-snapped segments when editing.
    var segmentPolylines: [String: [PolylineCoordinate]] {
        get {
            guard let data = segmentPolylinesData else { return [:] }
            return (try? JSONDecoder().decode([String: [PolylineCoordinate]].self, from: data)) ?? [:]
        }
        set {
            segmentPolylinesData = try? JSONEncoder().encode(newValue)
        }
    }

    private static func defaultName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return "Run — \(formatter.string(from: date))"
    }
}

// MARK: - RouteWaypoint

struct RouteWaypoint: Codable, Identifiable, Sendable {
    var id: UUID
    var latitude: Double
    var longitude: Double
    var order: Int
    var type: WaypointType

    init(
        id: UUID = UUID(),
        latitude: Double,
        longitude: Double,
        order: Int,
        type: WaypointType
    ) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.order = order
        self.type = type
    }
}

// MARK: - PolylineCoordinate

struct PolylineCoordinate: Codable, Sendable {
    var latitude: Double
    var longitude: Double
}

// MARK: - WaypointType

enum WaypointType: String, Codable, Sendable {
    case start
    case via
    case end
}
