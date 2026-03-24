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
    var isFavorite: Bool

    init(
        name: String? = nil,
        distance: Double = 0,
        estimatedDurationSeconds: Double = 0,
        elevationGain: Double? = nil,
        waypoints: [RouteWaypoint] = [],
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

// MARK: - WaypointType

enum WaypointType: String, Codable, Sendable {
    case start
    case via
    case end
}
