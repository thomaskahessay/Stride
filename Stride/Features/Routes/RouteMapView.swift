import SwiftUI
import MapKit

struct RouteMapView: View {
    let locationManager: LocationManager

    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var hasInitiallyCentered = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Map(position: $cameraPosition) {
                UserAnnotation()
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .onAppear {
                locationManager.startTracking()
            }
            .onDisappear {
                locationManager.stopTracking()
            }
            .onChange(of: locationManager.currentLocation) { _, newLocation in
                guard !hasInitiallyCentered, let location = newLocation else { return }
                hasInitiallyCentered = true
                withAnimation {
                    cameraPosition = .region(
                        MKCoordinateRegion(
                            center: location.coordinate,
                            latitudinalMeters: 1000,
                            longitudinalMeters: 1000
                        )
                    )
                }
            }

            // Recentre button
            recentreButton
                .padding(.trailing, .strideMD)
                .padding(.bottom, .strideMD)
        }
        .overlay(alignment: .top) {
            if locationManager.isDenied {
                locationDeniedBanner
            }
        }
        .navigationTitle("Routes")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Recentre Button

    private var recentreButton: some View {
        Button {
            guard let location = locationManager.currentLocation else { return }
            withAnimation {
                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: location.coordinate,
                        latitudinalMeters: 1000,
                        longitudinalMeters: 1000
                    )
                )
            }
        } label: {
            Image(systemName: "location.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.stride.lavenderDeep)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
        }
    }

    // MARK: - Location Denied Banner

    private var locationDeniedBanner: some View {
        HStack(spacing: .strideSM) {
            Image(systemName: "location.slash.fill")
                .foregroundStyle(Color.stride.coral)
            Text(locationManager.locationError ?? "Location access denied.")
                .font(Font.stride.bodyMedium)
        }
        .padding(.strideMD)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: .strideRadiusMD))
        .padding(.horizontal, .strideMD)
        .padding(.top, .strideSM)
    }
}
