import Foundation
import CoreLocation
import SwiftData

final class RouteService {

    func saveRoute(
        name: String? = nil,
        waypoints: [CLLocationCoordinate2D],
        distance: Double,
        estimatedDuration: Double,
        isLoop: Bool = false,
        modelContext: ModelContext
    ) -> Route {
        let routeWaypoints = waypoints.enumerated().map { index, coord in
            let type: WaypointType
            if index == 0 {
                type = .start
            } else if index == waypoints.count - 1 && !isLoop {
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

        let route = Route(
            name: name,
            distance: distance,
            estimatedDurationSeconds: estimatedDuration,
            waypoints: routeWaypoints,
            isLoop: isLoop
        )
        modelContext.insert(route)
        return route
    }

    func fetchAllRoutes(modelContext: ModelContext) -> [Route] {
        let descriptor = FetchDescriptor<Route>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func deleteRoute(_ route: Route, modelContext: ModelContext) {
        modelContext.delete(route)
    }

    func toggleFavorite(_ route: Route) {
        route.isFavorite.toggle()
        route.updatedAt = Date()
    }

    // MARK: - Export

    func exportStrideFile(route: Route) throws -> URL {
        let transferData = RouteTransferData(from: route)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(transferData)

        let sanitizedName = route.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let fileName = "\(sanitizedName).stride"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: tempURL)
        return tempURL
    }

    func exportGPXFile(route: Route) throws -> URL {
        let coords = route.polylineCoordinates
        let waypoints = route.waypoints.sorted { $0.order < $1.order }

        var gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Stride"
             xmlns="http://www.topografix.com/GPX/1/1">
          <trk>
            <name>\(escapeXML(route.name))</name>
            <trkseg>

        """

        for coord in coords {
            let lat = String(format: "%.6f", coord.latitude)
            let lon = String(format: "%.6f", coord.longitude)
            gpx += "      <trkpt lat=\"\(lat)\" lon=\"\(lon)\"></trkpt>\n"
        }

        gpx += """
            </trkseg>
          </trk>

        """

        for wp in waypoints {
            let lat = String(format: "%.6f", wp.latitude)
            let lon = String(format: "%.6f", wp.longitude)
            gpx += "  <wpt lat=\"\(lat)\" lon=\"\(lon)\"><name>\(escapeXML(wp.type.rawValue))</name></wpt>\n"
        }

        gpx += "</gpx>\n"

        let sanitizedName = route.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let fileName = "\(sanitizedName).gpx"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try gpx.write(to: tempURL, atomically: true, encoding: .utf8)
        return tempURL
    }

    private func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
