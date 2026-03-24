import Foundation
import SwiftData

@Observable
final class SavedRoutesViewModel {
    private let routeService = RouteService()

    var routeToDelete: Route?
    var showDeleteConfirmation = false
    var showShareToast = false

    func deleteRoute(_ route: Route, modelContext: ModelContext) {
        routeService.deleteRoute(route, modelContext: modelContext)
    }

    func toggleFavorite(_ route: Route) {
        routeService.toggleFavorite(route)
    }

    func confirmDelete(_ route: Route) {
        routeToDelete = route
        showDeleteConfirmation = true
    }

    func formattedDistance(_ meters: Double, unit: UnitSystem) -> String {
        switch unit {
        case .kilometers:
            return String(format: "%.2f km", meters / 1000)
        case .miles:
            return String(format: "%.2f mi", meters / 1609.344)
        }
    }

    func relativeDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}
