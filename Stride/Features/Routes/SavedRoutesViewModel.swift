import Foundation
import SwiftData

enum RouteSortOption: String, CaseIterable, Identifiable {
    case newest = "Newest"
    case oldest = "Oldest"
    case nameAZ = "Name (A-Z)"
    case nameZA = "Name (Z-A)"
    case shortestDistance = "Shortest"
    case longestDistance = "Longest"

    var id: String { rawValue }
}

@Observable
final class SavedRoutesViewModel {
    private let routeService = RouteService()

    var routeToDelete: Route?
    var showDeleteConfirmation = false
    var showShareToast = false
    var searchText = ""
    var sortOption: RouteSortOption = .newest

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

    func filteredAndSorted(_ routes: [Route]) -> [Route] {
        var result = routes

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { $0.name.lowercased().contains(query) }
        }

        result.sort { a, b in
            switch sortOption {
            case .newest:
                return a.updatedAt > b.updatedAt
            case .oldest:
                return a.updatedAt < b.updatedAt
            case .nameAZ:
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .nameZA:
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedDescending
            case .shortestDistance:
                return a.distance < b.distance
            case .longestDistance:
                return a.distance > b.distance
            }
        }

        return result
    }

    func favoriteRoutes(from routes: [Route]) -> [Route] {
        filteredAndSorted(routes.filter { $0.isFavorite })
    }

    func nonFavoriteRoutes(from routes: [Route]) -> [Route] {
        filteredAndSorted(routes.filter { !$0.isFavorite })
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
