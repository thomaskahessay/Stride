import Foundation
import CoreLocation

// MARK: - GPX Parser

final class GPXParser: NSObject, XMLParserDelegate {

    private var trackName: String = ""
    private var trackPoints: [GPXTrackPoint] = []
    private var waypointElements: [GPXTrackPoint] = []

    private var currentElement: String = ""
    private var currentCharacters: String = ""
    private var currentLat: Double?
    private var currentLon: Double?
    private var currentElevation: Double?
    private var insideTrack = false
    private var insideTrackSegment = false
    private var insideWaypoint = false

    // MARK: - Public

    func parse(data: Data) throws -> RouteTransferData {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw GPXError.parsingFailed
        }
        return buildTransferData()
    }

    func parse(url: URL) throws -> RouteTransferData {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        return try parse(data: data)
    }

    // MARK: - Build Result

    private func buildTransferData() -> RouteTransferData {
        let polyline = trackPoints.map {
            PolylineCoordinate(latitude: $0.latitude, longitude: $0.longitude)
        }

        // Compute distance from track points
        var totalDistance: Double = 0
        for i in 1..<trackPoints.count {
            let prev = CLLocation(latitude: trackPoints[i - 1].latitude, longitude: trackPoints[i - 1].longitude)
            let curr = CLLocation(latitude: trackPoints[i].latitude, longitude: trackPoints[i].longitude)
            totalDistance += curr.distance(from: prev)
        }

        // Compute elevation gain from positive deltas
        var elevationGain: Double? = nil
        let elevations = trackPoints.compactMap { $0.elevation }
        if elevations.count > 1 {
            var gain: Double = 0
            for i in 1..<elevations.count {
                let delta = elevations[i] - elevations[i - 1]
                if delta > 0 { gain += delta }
            }
            elevationGain = gain
        }

        // Build waypoints from first/last track points
        var waypoints: [RouteWaypoint] = []
        if let first = trackPoints.first {
            waypoints.append(RouteWaypoint(
                latitude: first.latitude,
                longitude: first.longitude,
                order: 0,
                type: .start
            ))
        }
        if trackPoints.count > 1, let last = trackPoints.last {
            let isLoop = isLoopRoute(first: trackPoints.first, last: last)
            waypoints.append(RouteWaypoint(
                latitude: last.latitude,
                longitude: last.longitude,
                order: 1,
                type: isLoop ? .start : .end
            ))
        }

        let isLoop = isLoopRoute(first: trackPoints.first, last: trackPoints.last)

        // Estimate duration at ~6 min/km pace
        let estimatedDuration = (totalDistance / 1000) * 360

        let name = trackName.isEmpty ? "Imported Route" : trackName

        return RouteTransferData(
            name: name,
            distance: totalDistance,
            estimatedDurationSeconds: estimatedDuration,
            elevationGain: elevationGain,
            isLoop: isLoop,
            waypoints: waypoints,
            polylineCoordinates: polyline
        )
    }

    private func isLoopRoute(first: GPXTrackPoint?, last: GPXTrackPoint?) -> Bool {
        guard let first, let last else { return false }
        let start = CLLocation(latitude: first.latitude, longitude: first.longitude)
        let end = CLLocation(latitude: last.latitude, longitude: last.longitude)
        return end.distance(from: start) < 50 // within 50m = loop
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentCharacters = ""

        switch elementName {
        case "trk":
            insideTrack = true
        case "trkseg":
            insideTrackSegment = true
        case "trkpt":
            if let latStr = attributeDict["lat"], let lonStr = attributeDict["lon"],
               let lat = Double(latStr), let lon = Double(lonStr) {
                currentLat = lat
                currentLon = lon
            }
        case "wpt":
            insideWaypoint = true
            if let latStr = attributeDict["lat"], let lonStr = attributeDict["lon"],
               let lat = Double(latStr), let lon = Double(lonStr) {
                currentLat = lat
                currentLon = lon
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentCharacters += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        let trimmed = currentCharacters.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "name":
            if insideTrack && trackName.isEmpty {
                trackName = trimmed
            }
        case "ele":
            currentElevation = Double(trimmed)
        case "trkpt":
            if let lat = currentLat, let lon = currentLon {
                trackPoints.append(GPXTrackPoint(
                    latitude: lat, longitude: lon, elevation: currentElevation
                ))
            }
            currentLat = nil
            currentLon = nil
            currentElevation = nil
        case "wpt":
            if let lat = currentLat, let lon = currentLon {
                waypointElements.append(GPXTrackPoint(
                    latitude: lat, longitude: lon, elevation: currentElevation
                ))
            }
            currentLat = nil
            currentLon = nil
            currentElevation = nil
            insideWaypoint = false
        case "trk":
            insideTrack = false
        case "trkseg":
            insideTrackSegment = false
        default:
            break
        }

        currentCharacters = ""
    }
}

// MARK: - Supporting Types

private struct GPXTrackPoint {
    let latitude: Double
    let longitude: Double
    let elevation: Double?
}

enum GPXError: LocalizedError {
    case parsingFailed

    var errorDescription: String? {
        switch self {
        case .parsingFailed:
            return "Failed to parse GPX file."
        }
    }
}
