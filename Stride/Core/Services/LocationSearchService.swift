import Foundation
import MapKit

@Observable
final class LocationSearchService {

    var searchText = ""
    var results: [MKLocalSearchCompletion] = []
    var isSearching = false

    private let completerDelegate: CompleterDelegate
    private let completer = MKLocalSearchCompleter()

    init() {
        completerDelegate = CompleterDelegate()
        completer.delegate = completerDelegate
        completer.resultTypes = [.address, .pointOfInterest]

        completerDelegate.onUpdate = { [weak self] completions in
            Task { @MainActor in
                self?.results = completions
                self?.isSearching = false
            }
        }
        completerDelegate.onError = { [weak self] in
            Task { @MainActor in
                self?.isSearching = false
            }
        }
    }

    func updateSearch(_ query: String) {
        searchText = query
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        completer.queryFragment = query
    }

    func clear() {
        searchText = ""
        results = []
        isSearching = false
        completer.cancel()
    }

    /// Resolve a completion to a coordinate.
    @MainActor
    func resolve(_ completion: MKLocalSearchCompletion) async -> CLLocationCoordinate2D? {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            return response.mapItems.first?.placemark.coordinate
        } catch {
            return nil
        }
    }
}

// MARK: - Completer Delegate (plain NSObject, no @Observable conflict)

private final class CompleterDelegate: NSObject, MKLocalSearchCompleterDelegate {
    var onUpdate: (([MKLocalSearchCompletion]) -> Void)?
    var onError: (() -> Void)?

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        onUpdate?(completer.results)
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        onError?()
    }
}
