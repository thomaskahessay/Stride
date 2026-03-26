import SwiftUI

struct RouteThumbnail: View {
    let waypoints: [RouteWaypoint]
    var polyline: [PolylineCoordinate] = []
    var isLoop: Bool = false
    var size: CGFloat = 50

    var body: some View {
        Canvas { context, canvasSize in
            // Use road-snapped polyline if available, otherwise waypoints
            let points: [(lat: Double, lon: Double)]
            if !polyline.isEmpty {
                points = polyline.map { (lat: $0.latitude, lon: $0.longitude) }
            } else {
                let sorted = waypoints.sorted { $0.order < $1.order }
                var wp = sorted.map { (lat: $0.latitude, lon: $0.longitude) }
                if isLoop, let first = wp.first {
                    wp.append(first)
                }
                points = wp
            }

            guard points.count >= 2 else { return }

            let lats = points.map(\.lat)
            let lons = points.map(\.lon)

            guard let minLat = lats.min(),
                  let maxLat = lats.max(),
                  let minLon = lons.min(),
                  let maxLon = lons.max() else { return }

            let latRange = maxLat - minLat
            let lonRange = maxLon - minLon
            let padding: CGFloat = 6

            let drawWidth = canvasSize.width - padding * 2
            let drawHeight = canvasSize.height - padding * 2

            func normalize(lat: Double, lon: Double) -> CGPoint {
                let x: CGFloat
                let y: CGFloat
                if lonRange > 0 {
                    x = padding + CGFloat((lon - minLon) / lonRange) * drawWidth
                } else {
                    x = canvasSize.width / 2
                }
                if latRange > 0 {
                    y = padding + CGFloat(1.0 - (lat - minLat) / latRange) * drawHeight
                } else {
                    y = canvasSize.height / 2
                }
                return CGPoint(x: x, y: y)
            }

            var path = Path()
            let first = normalize(lat: points[0].lat, lon: points[0].lon)
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: normalize(lat: point.lat, lon: point.lon))
            }

            context.stroke(
                path,
                with: .color(Color.stride.lavenderDeep),
                lineWidth: 2.5
            )

            // Start dot
            context.fill(
                Path(ellipseIn: CGRect(x: first.x - 3, y: first.y - 3, width: 6, height: 6)),
                with: .color(Color.stride.mint)
            )
        }
        .frame(width: size, height: size)
        .background(Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: .strideRadiusSM, style: .continuous))
    }
}
