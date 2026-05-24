// MapPickerView.swift
// Interactive map for picking an alarm's center coordinate.
// Long-press to drop a pin; shows the radius circle overlay.

import SwiftUI
import MapKit

struct MapPickerView: View {
    @Binding var latitude: Double
    @Binding var longitude: Double

    // Internal camera position — starts at the user's current location
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var pinCoordinate: CLLocationCoordinate2D?

    var body: some View {
        MapReader { proxy in
            Map(position: $cameraPosition) {
                // Show user's current position
                UserAnnotation()

                // Dropped pin
                if let coord = pinCoordinate {
                    Annotation("", coordinate: coord) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.title)
                            .foregroundStyle(.red)
                    }
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
        .overlay(alignment: .bottom) {
            Text(pinCoordinate == nil
                 ? "Tap the map to set alarm location"
                 : "Tap to move the pin")
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
    }
}

#Preview {
    MapPickerView(
        latitude: .constant(40.7580),
        longitude: .constant(-73.9855)
    )
    .frame(height: 300)
}
