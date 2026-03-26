import Foundation
import CoreLocation

/// Fetches elevation data from the Open Elevation API and calculates gain/loss
/// for a set of polyline coordinates.
final class ElevationService {

    /// Result of an elevation query for a route.
    struct ElevationResult {
        /// Total uphill elevation gain in metres.
        let gain: Double
        /// Total downhill elevation loss in metres (positive value).
        let loss: Double
        /// Per-sample elevations in metres (same order as sampled points).
        let elevations: [Double]
    }

    // MARK: - API

    /// Fetch elevation gain for an array of coordinates.
    /// Samples up to `maxSamples` evenly spaced points to keep the request small.
    func fetchElevation(
        for coordinates: [CLLocationCoordinate2D],
        maxSamples: Int = 30
    ) async throws -> ElevationResult {
        let sampled = sampleCoordinates(coordinates, maxSamples: maxSamples)
        guard sampled.count >= 2 else {
            return ElevationResult(gain: 0, loss: 0, elevations: [])
        }

        let elevations = try await queryElevations(for: sampled)
        return calculateGainLoss(from: elevations)
    }

    // MARK: - Sampling

    /// Evenly sample coordinates along the polyline, always including start and end.
    private func sampleCoordinates(
        _ coordinates: [CLLocationCoordinate2D],
        maxSamples: Int
    ) -> [CLLocationCoordinate2D] {
        guard coordinates.count > maxSamples else { return coordinates }

        var sampled: [CLLocationCoordinate2D] = []
        let step = Double(coordinates.count - 1) / Double(maxSamples - 1)

        for i in 0..<maxSamples {
            let index = Int(round(Double(i) * step))
            sampled.append(coordinates[min(index, coordinates.count - 1)])
        }
        return sampled
    }

    // MARK: - API Request

    private struct OpenElevationResponse: Decodable {
        let results: [ElevationPoint]
    }

    private struct ElevationPoint: Decodable {
        let latitude: Double
        let longitude: Double
        let elevation: Double
    }

    private struct OpenElevationRequest: Encodable {
        let locations: [Location]

        struct Location: Encodable {
            let latitude: Double
            let longitude: Double
        }
    }

    private func queryElevations(
        for coordinates: [CLLocationCoordinate2D]
    ) async throws -> [Double] {
        guard let url = URL(string: "https://api.open-elevation.com/api/v1/lookup") else {
            throw ElevationError.invalidURL
        }

        let body = OpenElevationRequest(
            locations: coordinates.map {
                .init(latitude: $0.latitude, longitude: $0.longitude)
            }
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ElevationError.apiError
        }

        let decoded = try JSONDecoder().decode(OpenElevationResponse.self, from: data)
        return decoded.results.map(\.elevation)
    }

    // MARK: - Calculation

    private func calculateGainLoss(from elevations: [Double]) -> ElevationResult {
        var gain: Double = 0
        var loss: Double = 0

        for i in 1..<elevations.count {
            let delta = elevations[i] - elevations[i - 1]
            if delta > 0 {
                gain += delta
            } else {
                loss += abs(delta)
            }
        }

        return ElevationResult(
            gain: gain.rounded(),
            loss: loss.rounded(),
            elevations: elevations
        )
    }
}

// MARK: - Errors

enum ElevationError: LocalizedError {
    case apiError
    case insufficientPoints
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .apiError:
            return "Unable to fetch elevation data. Please try again."
        case .insufficientPoints:
            return "Not enough points to calculate elevation."
        case .invalidURL:
            return "Invalid elevation API URL."
        }
    }
}
