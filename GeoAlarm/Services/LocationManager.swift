// LocationManager.swift
// Wraps CLLocationManager; publishes authorization status and current location.
// Handles region monitoring callbacks and forwards events to AlarmManager.

import Foundation
import CoreLocation
import Combine

@MainActor
/// Thin wrapper around CLLocationManager, designed to be injected via @EnvironmentObject.
final class LocationManager: NSObject, ObservableObject {

    // MARK: - Published state
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentLocation: CLLocation?
    @Published var lastError: Error?

    /// True when location hardware is unavailable — e.g. airplane mode with
    /// GPS disabled.  Distinct from authorization denial: the user has granted
    /// permission but the OS can't produce a fix right now.
    @Published var isLocationUnavailable: Bool = false

    // MARK: - Internals
    private let manager: CLLocationManager

    /// Closure called when a region event fires. Set by AlarmManager.
    var onRegionEntered: ((String) -> Void)?
    var onRegionExited:  ((String) -> Void)?

    /// Closure called on every location fix. Set by AlarmManager to feed the
    /// ETA engine while a time-based alarm is in its final-approach window.
    var onLocationUpdate: ((CLLocation) -> Void)?

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

    // MARK: - Continuous background tracking (time-based alarms)

    /// Enable continuous background location updates for the final-approach ETA
    /// tracking of a time-based alarm. Requires the "location" UIBackgroundMode
    /// (present) and Always authorization. Higher battery cost — only call while
    /// approaching a time-based alarm's destination, and pair with `stopContinuousUpdates()`.
    func startContinuousUpdates() {
        // `allowsBackgroundLocationUpdates = true` throws an NSException (crash) unless
        // UIBackgroundModes contains "location" AND the app has Always authorization.
        // Guard both so a misconfigured build/permission state degrades to foreground-
        // only tracking instead of crashing.
        let bgModes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        let authorized = authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse
        let canBackground = bgModes.contains("location") && authorized
        if canBackground {
            manager.allowsBackgroundLocationUpdates = true
            manager.pausesLocationUpdatesAutomatically = false
            DebugLogger.shared.log("Continuous background location updates ENABLED (time-based approach)", category: "Location")
        } else {
            DebugLogger.shared.log("Background location NOT enabled (UIBackgroundModes contains location=\(bgModes.contains("location")), auth=\(authorizationStatus.debugDescription)) — foreground-only ETA tracking", category: "Location")
        }
        manager.startUpdatingLocation()
    }

    /// Drop the background-update privilege so updates suspend again in the
    /// background (foreground streaming continues for the map/current location).
    func stopContinuousUpdates() {
        manager.allowsBackgroundLocationUpdates = false
        DebugLogger.shared.log("Continuous background location updates DISABLED", category: "Location")
    }

    // MARK: - Region monitoring

    func startMonitoring(region inputRegion: CLCircularRegion) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            print("⚠️ Region monitoring unavailable on this device.")
            DebugLogger.shared.log("Region monitoring unavailable on this device — cannot monitor '\(inputRegion.identifier)'", category: "Location")
            return
        }
        // Clamp to the OS maximum so a large time-based outer ring can't be rejected.
        var region = inputRegion
        let maxDist = manager.maximumRegionMonitoringDistance
        if maxDist > 0, inputRegion.radius > maxDist {
            region = CLCircularRegion(center: inputRegion.center, radius: maxDist, identifier: inputRegion.identifier)
            region.notifyOnEntry = inputRegion.notifyOnEntry
            region.notifyOnExit  = inputRegion.notifyOnExit
            DebugLogger.shared.log("Region '\(inputRegion.identifier)' radius \(Int(inputRegion.radius))m clamped to OS max \(Int(maxDist))m", category: "Location")
        }
        manager.startMonitoring(for: region)
        DebugLogger.shared.log("Start monitoring region: id=\(region.identifier) center=(\(region.center.latitude),\(region.center.longitude)) radius=\(Int(region.radius))m notifyOnEntry=\(region.notifyOnEntry) notifyOnExit=\(region.notifyOnExit) totalMonitored=\(manager.monitoredRegions.count + 1)", category: "Location")
    }

    func stopMonitoring(region: CLCircularRegion) {
        manager.stopMonitoring(for: region)
        DebugLogger.shared.log("Stop monitoring region: id=\(region.identifier) remainingMonitored=\(max(0, manager.monitoredRegions.count - 1))", category: "Location")
    }

    func stopMonitoringAll() {
        let count = manager.monitoredRegions.count
        manager.monitoredRegions.forEach { manager.stopMonitoring(for: $0) }
        DebugLogger.shared.log("Stopped monitoring all \(count) region(s)", category: "Location")
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
        let status = manager.authorizationStatus
        DispatchQueue.main.async {
            self.authorizationStatus = status
        }
        DebugLogger.shared.log("Authorization changed → \(status.debugDescription) accuracyAuthorization=\(manager.accuracyAuthorization.debugDescription)", category: "Location")
        // Auto-start location once permission granted
        if status == .authorizedAlways || status == .authorizedWhenInUse {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        DispatchQueue.main.async {
            self.currentLocation = loc
            // A fresh fix means hardware is working — clear any unavailable flag.
            self.isLocationUnavailable = false
            // Feed the ETA engine (no-op unless a time-based alarm is approaching).
            self.onLocationUpdate?(loc)
        }
        // Log only occasionally (every ~100 m change) to avoid flooding the file
        DebugLogger.shared.log("Location fix: (\(String(format: "%.5f", loc.coordinate.latitude)), \(String(format: "%.5f", loc.coordinate.longitude))) accuracy=\(Int(loc.horizontalAccuracy))m speed=\(Int(loc.speed))m/s", category: "Location")
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let clError = error as? CLError

        DispatchQueue.main.async {
            self.lastError = error

            // kCLErrorLocationUnknown fires when the OS cannot determine a
            // position — the most common cause is airplane mode with GPS off.
            // kCLErrorDenied fires if the user revokes permission at the OS level.
            // We surface isLocationUnavailable for these so the UI can warn.
            switch clError?.code {
            case .locationUnknown, .network:
                // Only flag unavailable if we actually have permission;
                // avoids double-warning alongside the denial banner.
                if self.authorizationStatus == .authorizedAlways ||
                   self.authorizationStatus == .authorizedWhenInUse {
                    self.isLocationUnavailable = true
                }
                // Transient — breadcrumb only; not worth a non-fatal report.
                CrashReporter.log("Location unavailable: \(error.localizedDescription)")
            default:
                // Unexpected location failure — surface in Firebase Console.
                CrashReporter.record(error, context: "LocationManager")
            }
        }
        DebugLogger.shared.log("Location error: \(error.localizedDescription) clErrorCode=\(clError?.code.rawValue.description ?? "n/a")", category: "Location")
        print("❌ LocationManager error: \(error.localizedDescription)")
    }

    // MARK: Region events

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        print("📍 Entered region: \(region.identifier)")
        DebugLogger.shared.log("📍 Region ENTERED: id=\(region.identifier)", category: "Location")
        DispatchQueue.main.async {
            self.onRegionEntered?(region.identifier)
        }
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        print("📍 Exited region: \(region.identifier)")
        DebugLogger.shared.log("📍 Region EXITED: id=\(region.identifier)", category: "Location")
        DispatchQueue.main.async {
            self.onRegionExited?(region.identifier)
        }
    }

    func locationManager(_ manager: CLLocationManager,
                         monitoringDidFailFor region: CLRegion?,
                         withError error: Error) {
        let clError = error as? CLError
        let id = region?.identifier ?? "unknown"
        print("❌ Region monitoring failed for \(id): \(error.localizedDescription)")
        DebugLogger.shared.log("Region monitoring FAILED: id=\(id) error='\(error.localizedDescription)' clErrorCode=\(clError?.code.rawValue.description ?? "n/a")", category: "Location")
        DispatchQueue.main.async {
            self.lastError = error
        }
    }

    func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        print("✅ Now monitoring region: \(region.identifier)")
        DebugLogger.shared.log("Monitoring confirmed by OS: id=\(region.identifier) totalMonitoredByOS=\(manager.monitoredRegions.count)", category: "Location")
    }
}

// MARK: - Debug description helpers

private extension CLAuthorizationStatus {
    var debugDescription: String {
        switch self {
        case .notDetermined:       return "notDetermined"
        case .restricted:          return "restricted"
        case .denied:              return "denied"
        case .authorizedAlways:    return "authorizedAlways"
        case .authorizedWhenInUse: return "authorizedWhenInUse"
        @unknown default:          return "unknown(\(rawValue))"
        }
    }
}

private extension CLAccuracyAuthorization {
    var debugDescription: String {
        switch self {
        case .fullAccuracy:    return "fullAccuracy"
        case .reducedAccuracy: return "reducedAccuracy"
        @unknown default:      return "unknown(\(rawValue))"
        }
    }
}
