// LocationManager.swift
// Wraps CLLocationManager; publishes authorization status and current location.
// Handles region monitoring callbacks and forwards events to AlarmManager.

import Foundation
internal import CoreLocation
import Combine

/// Thin wrapper around CLLocationManager, designed to be injected via @EnvironmentObject.
final class LocationManager: NSObject, ObservableObject {

    // MARK: - Published state
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentLocation: CLLocation?
    @Published var lastError: Error?

    // MARK: - Internals
    private let manager: CLLocationManager

    /// Closure called when a region event fires. Set by AlarmManager.
    var onRegionEntered: ((String) -> Void)?
    var onRegionExited:  ((String) -> Void)?

    // MARK: - Init

    override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = manager.authorizationStatus
    }

    // MARK: - Public API

    /// Request "Always" permission (required for background region monitoring).
    func requestAlwaysAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    /// Start streaming location updates (used for the map picker).
    func startUpdatingLocation() {
        manager.startUpdatingLocation()
    }

    func stopUpdatingLocation() {
        manager.stopUpdatingLocation()
    }

    // MARK: - Region monitoring

    func startMonitoring(region: CLCircularRegion) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            print("⚠️ Region monitoring unavailable on this device.")
            return
        }
        manager.startMonitoring(for: region)
    }

    func stopMonitoring(region: CLCircularRegion) {
        manager.stopMonitoring(for: region)
    }

    func stopMonitoringAll() {
        manager.monitoredRegions.forEach { manager.stopMonitoring(for: $0) }
    }

    /// Returns all currently monitored region identifiers.
    var monitoredRegionIDs: Set<String> {
        Set(manager.monitoredRegions.map(\.identifier))
    }

    /// Maximum number of regions iOS will monitor simultaneously (system limit = 20).
    var regionMonitoringCapacity: Int {
        // Reserve a few slots for the OS itself
        return 18
    }
}

// MARK: - CLLocationManagerDelegate
extension LocationManager: CLLocationManagerDelegate {

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
        }
        // Auto-start location once permission granted
        if manager.authorizationStatus == .authorizedAlways ||
           manager.authorizationStatus == .authorizedWhenInUse {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        DispatchQueue.main.async {
            self.currentLocation = locations.last
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.lastError = error
        }
        print("❌ LocationManager error: \(error.localizedDescription)")
    }

    // MARK: Region events

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        print("📍 Entered region: \(region.identifier)")
        DispatchQueue.main.async {
            self.onRegionEntered?(region.identifier)
        }
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        print("📍 Exited region: \(region.identifier)")
        DispatchQueue.main.async {
            self.onRegionExited?(region.identifier)
        }
    }

    func locationManager(_ manager: CLLocationManager,
                         monitoringDidFailFor region: CLRegion?,
                         withError error: Error) {
        print("❌ Region monitoring failed for \(region?.identifier ?? "unknown"): \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.lastError = error
        }
    }

    func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        print("✅ Now monitoring region: \(region.identifier)")
    }
}
