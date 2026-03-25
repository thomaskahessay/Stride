import Foundation

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
