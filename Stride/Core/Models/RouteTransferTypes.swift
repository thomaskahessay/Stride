import Foundation
import UniformTypeIdentifiers

// MARK: - Custom UTType

extension UTType {
    static let strideRoute = UTType(exportedAs: "com.stride.route")
}

// MARK: - Route Transfer Data (Codable, decoupled from SwiftData)

struct RouteTransferData: Codable {
    let version: Int
    let name: String
    let distance: Double
    let estimatedDurationSeconds: Double
    let elevationGain: Double?
    let isLoop: Bool
    let waypoints: [RouteWaypoint]
    let polylineCoordinates: [PolylineCoordinate]
    let segmentPolylines: [String: [PolylineCoordinate]]
    let createdAt: Date

    init(
        name: String,
        distance: Double,
        estimatedDurationSeconds: Double,
        elevationGain: Double?,
        isLoop: Bool,
        waypoints: [RouteWaypoint],
        polylineCoordinates: [PolylineCoordinate],
        segmentPolylines: [String: [PolylineCoordinate]] = [:],
        createdAt: Date = Date()
    ) {
        self.version = 1
        self.name = name
        self.distance = distance
        self.estimatedDurationSeconds = estimatedDurationSeconds
        self.elevationGain = elevationGain
        self.isLoop = isLoop
        self.waypoints = waypoints
        self.polylineCoordinates = polylineCoordinates
        self.segmentPolylines = segmentPolylines
        self.createdAt = createdAt
    }

}

// MARK: - Identifiable URL wrapper for sheet presentation

struct ImportableURL: Identifiable {
    let id = UUID()
    let url: URL
}
