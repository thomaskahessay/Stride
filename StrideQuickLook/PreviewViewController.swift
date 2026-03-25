import UIKit
import QuickLook
import MapKit

class PreviewViewController: UIViewController, QLPreviewingController {

    // MARK: - Stride design colours

    private let strideLavender = UIColor(red: 218/255, green: 195/255, blue: 232/255, alpha: 1.0)
    private let strideDarkText = UIColor.label
    private let strideSecondaryText = UIColor.secondaryLabel

    // MARK: - QLPreviewingController

    func preparePreviewOfFile(at url: URL) async throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let route = try decoder.decode(RouteTransferData.self, from: data)

        let coordinates = route.polylineCoordinates.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }

        // If no polyline, fall back to waypoints
        let renderCoords: [CLLocationCoordinate2D]
        if coordinates.isEmpty {
            renderCoords = route.waypoints.sorted(by: { $0.order < $1.order }).map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            }
        } else {
            renderCoords = coordinates
        }

        guard !renderCoords.isEmpty else {
            showEmptyState(routeName: route.name)
            return
        }

        let mapImage = try await renderMapSnapshot(coordinates: renderCoords)
        buildPreviewUI(mapImage: mapImage, route: route)
    }

    // MARK: - Map Rendering

    private func renderMapSnapshot(coordinates: [CLLocationCoordinate2D]) async throws -> UIImage {
        let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        let rect = polyline.boundingMapRect
        let inset = max(rect.width, rect.height) * 0.2
        let paddedRect = rect.insetBy(dx: -inset, dy: -inset)

        let options = MKMapSnapshotter.Options()
        options.mapRect = paddedRect
        options.size = CGSize(width: view.bounds.width, height: view.bounds.height * 0.6)
        options.traitCollection = view.traitCollection

        let snapshotter = MKMapSnapshotter(options: options)
        let snapshot = try await snapshotter.start()

        return drawPolyline(coordinates, on: snapshot)
    }

    private func drawPolyline(
        _ coords: [CLLocationCoordinate2D],
        on snapshot: MKMapSnapshotter.Snapshot
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: snapshot.image.size)
        return renderer.image { _ in
            snapshot.image.draw(at: .zero)

            let path = UIBezierPath()
            for (index, coord) in coords.enumerated() {
                let point = snapshot.point(for: coord)
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }

            strideLavender.setStroke()
            path.lineWidth = 4.0
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()

            // Start dot
            if let first = coords.first {
                let startPoint = snapshot.point(for: first)
                let dotRect = CGRect(x: startPoint.x - 6, y: startPoint.y - 6, width: 12, height: 12)
                UIColor.systemGreen.setFill()
                UIBezierPath(ovalIn: dotRect).fill()
            }

            // End dot (if not a loop)
            if coords.count > 1, let last = coords.last, let first = coords.first {
                let endPoint = snapshot.point(for: last)
                let startPoint = snapshot.point(for: first)
                let dx = endPoint.x - startPoint.x
                let dy = endPoint.y - startPoint.y
                let pixelDistance = sqrt(dx * dx + dy * dy)
                if pixelDistance > 20 {
                    let dotRect = CGRect(x: endPoint.x - 6, y: endPoint.y - 6, width: 12, height: 12)
                    UIColor.systemRed.setFill()
                    UIBezierPath(ovalIn: dotRect).fill()
                }
            }
        }
    }

    // MARK: - UI Construction

    private func buildPreviewUI(mapImage: UIImage, route: RouteTransferData) {
        let mapImageView = UIImageView(image: mapImage)
        mapImageView.contentMode = .scaleAspectFill
        mapImageView.clipsToBounds = true
        mapImageView.translatesAutoresizingMaskIntoConstraints = false

        let infoPanel = buildInfoPanel(route: route)
        infoPanel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(mapImageView)
        view.addSubview(infoPanel)

        NSLayoutConstraint.activate([
            mapImageView.topAnchor.constraint(equalTo: view.topAnchor),
            mapImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapImageView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.6),

            infoPanel.topAnchor.constraint(equalTo: mapImageView.bottomAnchor),
            infoPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            infoPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            infoPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func buildInfoPanel(route: RouteTransferData) -> UIView {
        let panel = UIView()
        panel.backgroundColor = UIColor.systemBackground

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Route name
        let nameLabel = UILabel()
        nameLabel.text = route.name
        nameLabel.font = .systemFont(ofSize: 22, weight: .bold)
        nameLabel.textColor = strideDarkText
        nameLabel.numberOfLines = 2
        stack.addArrangedSubview(nameLabel)

        // Stats row
        let statsStack = UIStackView()
        statsStack.axis = .horizontal
        statsStack.spacing = 24
        statsStack.alignment = .center

        // Distance
        let distanceKm = route.distance / 1000.0
        let distanceText = String(format: "%.2f km", distanceKm)
        statsStack.addArrangedSubview(makeStatView(icon: "figure.run", value: distanceText))

        // Duration
        let minutes = Int(route.estimatedDurationSeconds) / 60
        let durationText: String
        if minutes >= 60 {
            durationText = String(format: "%dh %dm", minutes / 60, minutes % 60)
        } else {
            durationText = "\(minutes) min"
        }
        statsStack.addArrangedSubview(makeStatView(icon: "clock", value: durationText))

        // Elevation
        if let elevation = route.elevationGain, elevation > 0 {
            let elevText = String(format: "%.0f m", elevation)
            statsStack.addArrangedSubview(makeStatView(icon: "mountain.2", value: elevText))
        }

        // Loop badge
        if route.isLoop {
            statsStack.addArrangedSubview(makeStatView(icon: "arrow.triangle.capsulepath", value: "Loop"))
        }

        stack.addArrangedSubview(statsStack)

        panel.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: panel.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: panel.trailingAnchor, constant: -20),
        ])

        // Divider line at top of panel
        let divider = UIView()
        divider.backgroundColor = strideLavender.withAlphaComponent(0.4)
        divider.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(divider)

        NSLayoutConstraint.activate([
            divider.topAnchor.constraint(equalTo: panel.topAnchor),
            divider.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 2),
        ])

        return panel
    }

    private func makeStatView(icon: String, value: String) -> UIView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center

        let iconView = UIImageView(image: UIImage(systemName: icon))
        iconView.tintColor = strideLavender
        iconView.contentMode = .scaleAspectFit
        iconView.widthAnchor.constraint(equalToConstant: 18).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 18).isActive = true

        let label = UILabel()
        label.text = value
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = strideSecondaryText

        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(label)
        return stack
    }

    // MARK: - Empty State

    private func showEmptyState(routeName: String) {
        let label = UILabel()
        label.text = routeName
        label.font = .systemFont(ofSize: 20, weight: .semibold)
        label.textColor = strideDarkText
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = UILabel()
        subtitle.text = "Stride Route"
        subtitle.font = .systemFont(ofSize: 15, weight: .regular)
        subtitle.textColor = strideSecondaryText
        subtitle.textAlignment = .center
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(label)
        view.addSubview(subtitle)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -12),
            subtitle.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 6),
            subtitle.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
    }
}
