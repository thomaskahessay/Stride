import Foundation
import SwiftData

@Observable
final class RouteImportViewModel {
    var routeData: RouteTransferData?
    var routeName: String = ""
    var errorMessage: String?
    var didSave = false

    func loadRoute(from url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        do {
            let ext = url.pathExtension.lowercased()

            if ext == "gpx" {
                let parser = GPXParser()
                routeData = try parser.parse(url: url)
            } else {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                routeData = try decoder.decode(RouteTransferData.self, from: data)
            }

            routeName = routeData?.name ?? "Imported Route"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveRoute(modelContext: ModelContext) {
        guard var data = routeData else { return }

        // Apply user-edited name
        data = RouteTransferData(
            name: routeName,
            distance: data.distance,
            estimatedDurationSeconds: data.estimatedDurationSeconds,
            elevationGain: data.elevationGain,
            isLoop: data.isLoop,
            waypoints: data.waypoints,
            polylineCoordinates: data.polylineCoordinates,
            segmentPolylines: data.segmentPolylines
        )

        let route = data.toRoute()
        modelContext.insert(route)
        didSave = true
    }
}
