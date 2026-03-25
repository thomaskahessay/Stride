import UIKit
import QuickLookThumbnailing
import MapKit

class ThumbnailProvider: QLThumbnailProvider {

    private let strideLavender = UIColor(red: 218/255, green: 195/255, blue: 232/255, alpha: 1.0)

    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        guard let data = try? Data(contentsOf: request.fileURL) else {
            handler(nil, ThumbnailError.fileReadFailed)
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let route = try? decoder.decode(RouteTransferData.self, from: data) else {
            handler(nil, ThumbnailError.decodeFailed)
            return
        }

        var coords = route.polylineCoordinates.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }

        // Fall back to waypoints
        if coords.isEmpty {
            coords = route.waypoints.sorted(by: { $0.order < $1.order }).map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            }
        }

        guard !coords.isEmpty else {
            handler(nil, ThumbnailError.noCoordinates)
            return
        }

        let contextSize = request.maximumSize
        let polyline = MKPolyline(coordinates: coords, count: coords.count)
        let rect = polyline.boundingMapRect
        let inset = max(rect.width, rect.height) * 0.25
        let paddedRect = rect.insetBy(dx: -inset, dy: -inset)

        let options = MKMapSnapshotter.Options()
        options.mapRect = paddedRect
        options.size = contextSize

        let snapshotter = MKMapSnapshotter(options: options)
        snapshotter.start { [strideLavender] snapshot, error in
            guard let snapshot = snapshot else {
                handler(nil, error ?? ThumbnailError.snapshotFailed)
                return
            }

            let reply = QLThumbnailReply(contextSize: contextSize) {
                snapshot.image.draw(in: CGRect(origin: .zero, size: contextSize))

                let path = UIBezierPath()
                for (i, coord) in coords.enumerated() {
                    let point = snapshot.point(for: coord)
                    if i == 0 {
                        path.move(to: point)
                    } else {
                        path.addLine(to: point)
                    }
                }

                strideLavender.setStroke()
                path.lineWidth = max(3.0, contextSize.width / 40)
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.stroke()

                // Green start dot
                if let first = coords.first {
                    let pt = snapshot.point(for: first)
                    let dotSize: CGFloat = max(6, contextSize.width / 20)
                    let dotRect = CGRect(
                        x: pt.x - dotSize / 2,
                        y: pt.y - dotSize / 2,
                        width: dotSize,
                        height: dotSize
                    )
                    UIColor.systemGreen.setFill()
                    UIBezierPath(ovalIn: dotRect).fill()
                }

                return true
            }
            handler(reply, nil)
        }
    }
}

// MARK: - Errors

private enum ThumbnailError: Error {
    case fileReadFailed
    case decodeFailed
    case noCoordinates
    case snapshotFailed
}
