import Foundation
import SwiftData

@Observable
final class RouteDetailViewModel {
    private let routeService = RouteService()

    var showDeleteConfirmation = false
    var showShareToast = false

    func deleteRoute(_ route: Route, modelContext: ModelContext) {
        routeService.deleteRoute(route, modelContext: modelContext)
    }

    func toggleFavorite(_ route: Route) {
        routeService.toggleFavorite(route)
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
