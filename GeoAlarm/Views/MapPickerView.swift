// MapPickerView.swift
// Interactive map for picking an alarm's center coordinate.
// Tap to drop a pin; "Use My Location" button pins current GPS position.
// Shows the radius circle overlay.

import SwiftUI
import MapKit
import CoreLocation

struct MapPickerView: View {
    @Binding var latitude: Double
    @Binding var longitude: Double
    /// Alarm radius in metres — drives the geofence circle overlay.
    @Binding var radius: Double

    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.languageBundle) private var bundle

    // Internal camera position — starts at automatic (no spinning "finding location" state)
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var pinCoordinate: CLLocationCoordinate2D?

    var body: some View {
        MapReader { proxy in
            Map(position: $cameraPosition) {
                // Show user's current position
                UserAnnotation()

                // Dropped pin + radius circle
                if let coord = pinCoordinate {
                    Annotation("", coordinate: coord) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.title)
                            .foregroundStyle(.red)
                    }

                    MapCircle(center: coord, radius: max(radius, 50))
                        .foregroundStyle(.blue.opacity(0.15))
                        .stroke(.blue.opacity(0.6), lineWidth: 1.5)
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .onTapGesture { screenPoint in
                if let coord = proxy.convert(screenPoint, from: .local) {
                    pinCoordinate = coord
                    latitude      = coord.latitude
                    longitude     = coord.longitude
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                useCurrentLocation()
            } label: {
                Label { Text("Use My Location", bundle: bundle) } icon: { Image(systemName: "location.fill") }
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
                    .shadow(radius: 2)
            }
            .disabled(locationManager.currentLocation == nil)
            .padding([.top, .trailing], 10)
        }
        .overlay(alignment: .bottom) {
            Text(pinCoordinate == nil
                 ? LocalizedStringKey("Tap the map to set alarm location")
                 : LocalizedStringKey("Tap to move the pin"),
                 bundle: bundle)
                .font(.caption)
                .padding(6)
                .background(.ultraThinMaterial)
                .cornerRadius(6)
                .padding(.bottom, 8)
        }
        .onAppear {
            // If editing an existing alarm, center on its coordinate
            if latitude != 0 || longitude != 0 {
                let coord = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                pinCoordinate   = coord
                cameraPosition  = .region(MKCoordinateRegion(
                    center: coord,
                    latitudinalMeters: 1000,
                    longitudinalMeters: 1000
                ))
            }
        }
        // Re-centre when a search result updates the coordinates externally
        .onChange(of: latitude) { _, newLat in
            guard newLat != 0 else { return }
            let coord = CLLocationCoordinate2D(latitude: newLat, longitude: longitude)
            pinCoordinate  = coord
            cameraPosition = .region(MKCoordinateRegion(
                center: coord,
                latitudinalMeters: 1000,
                longitudinalMeters: 1000
            ))
        }
        .onChange(of: longitude) { _, newLon in
            guard newLon != 0 else { return }
            let coord = CLLocationCoordinate2D(latitude: latitude, longitude: newLon)
            pinCoordinate  = coord
            cameraPosition = .region(MKCoordinateRegion(
                center: coord,
                latitudinalMeters: 1000,
                longitudinalMeters: 1000
            ))
        }
    }

    // MARK: - Helpers

    private func useCurrentLocation() {
        guard let loc = locationManager.currentLocation else { return }
        // Reject a stale / inaccurate fix so the pin lands where the user IS, not
        // where they were minutes ago (the cause of alarms centred off-position).
        let age = Date().timeIntervalSince(loc.timestamp)
        guard age < 30, loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 100 else { return }
        let coord      = loc.coordinate
        pinCoordinate  = coord
        latitude       = coord.latitude
        longitude      = coord.longitude
        cameraPosition = .region(MKCoordinateRegion(
            center: coord,
            latitudinalMeters: 1000,
            longitudinalMeters: 1000
        ))
    }
}

#Preview {
    MapPickerView(
        latitude: .constant(40.7580),
        longitude: .constant(-73.9855),
        radius: .constant(300)
    )
    .frame(height: 300)
    .environmentObject(LocationManager())
}
