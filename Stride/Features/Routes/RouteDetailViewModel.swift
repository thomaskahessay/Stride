import Foundation
import SwiftData

enum ExportFormat {
    case stride
    case gpx
}

struct ShareableFile: Identifiable {
    let id = UUID()
    let url: URL
}

@Observable
final class RouteDetailViewModel {
    private let routeService = RouteService()

    var showDeleteConfirmation = false
    var shareItem: ShareableFile?
    var exportError: String?

    func deleteRoute(_ route: Route, modelContext: ModelContext) {
        routeService.deleteRoute(route, modelContext: modelContext)
    }

    func toggleFavorite(_ route: Route) {
        routeService.toggleFavorite(route)
    }

    func exportRoute(_ route: Route, format: ExportFormat) {
        do {
            let url: URL
            switch format {
            case .stride:
                url = try routeService.exportStrideFile(route: route)
            case .gpx:
                url = try routeService.exportGPXFile(route: route)
            }
            shareItem = ShareableFile(url: url)
        } catch {
            exportError = error.localizedDescription
        }
    }

    func formattedDistance(_ meters: Double, unit: UnitSystem) -> String {
        switch unit {
        case .kilometers:
            return String(format: "%.2f km", meters / 1000)
        case .miles:
            return String(format: "%.2f mi", meters / 1609.344)
        }
    }

    func formattedDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return String(format: "%dh %02dm", hours, remainingMinutes)
        }
        return "\(minutes) min"
    }
}
