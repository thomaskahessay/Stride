import SwiftUI

struct RouteThumbnail: View {
    let waypoints: [RouteWaypoint]
    var size: CGFloat = 50

    var body: some View {
        Canvas { context, canvasSize in
            guard waypoints.count >= 2 else { return }

            let sorted = waypoints.sorted { $0.order < $1.order }
            let lats = sorted.map(\.latitude)
            let lons = sorted.map(\.longitude)

            guard let minLat = lats.min(),
                  let maxLat = lats.max(),
                  let minLon = lons.min(),
                  let maxLon = lons.max() else { return }

            let latRange = maxLat - minLat
            let lonRange = maxLon - minLon
            let padding: CGFloat = 6

            let drawWidth = canvasSize.width - padding * 2
            let drawHeight = canvasSize.height - padding * 2

            func normalize(_ wp: RouteWaypoint) -> CGPoint {
                let x: CGFloat
                let y: CGFloat
                if lonRange > 0 {
                    x = padding + CGFloat((wp.longitude - minLon) / lonRange) * drawWidth
                } else {
                    x = canvasSize.width / 2
                }
                if latRange > 0 {
                    // Flip Y — latitude increases upward
                    y = padding + CGFloat(1.0 - (wp.latitude - minLat) / latRange) * drawHeight
                } else {
                    y = canvasSize.height / 2
                }
                return CGPoint(x: x, y: y)
            }

            var path = Path()
            let first = normalize(sorted[0])
            path.move(to: first)
            for wp in sorted.dropFirst() {
                path.addLine(to: normalize(wp))
            }

            context.stroke(
                path,
                with: .color(Color.stride.lavenderDeep),
                lineWidth: 2.5
            )

            // Start dot
            let startPoint = normalize(sorted[0])
            context.fill(
                Path(ellipseIn: CGRect(x: startPoint.x - 3, y: startPoint.y - 3, width: 6, height: 6)),
                with: .color(Color.stride.mint)
            )
        }
        .frame(width: size, height: size)
        .background(Color.stride.lavenderLight.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: .strideRadiusSM, style: .continuous))
    }
}
