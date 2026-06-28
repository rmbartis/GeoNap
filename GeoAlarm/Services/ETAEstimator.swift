// ETAEstimator.swift
// Pure, testable rolling-average-speed → ETA engine for time-based alarms.
//
// Part of the hybrid time-based-alarm design (docs/time-based-alarms-design.md):
// once the app wakes inside the outer "get close" geofence, it feeds continuous
// location fixes into an ETAEstimator and fires the alarm when the estimated time
// to the destination drops to the requested lead time.
//
// Deliberately has NO UIKit / background dependencies so it can be unit-tested in
// isolation by replaying recorded fixes.

import CoreLocation

struct ETAEstimator {

    // MARK: - Tuning

    /// Fixes with horizontalAccuracy outside [0, accuracyGate) are ignored — the
    /// coarse cell/Wi-Fi wake-up fixes (hundreds–thousands of metres) would corrupt
    /// both the speed average and the distance term. See the GPS accuracy analysis.
    var accuracyGate: CLLocationAccuracy = 50

    /// Sliding window (seconds) over which speed is averaged.
    var window: TimeInterval = 60

    /// Speeds below this (m/s, ≈3.6 km/h) are treated as "stopped" (signal, station),
    /// so ETA is reported as nil rather than exploding toward infinity.
    var minSpeed: CLLocationSpeed = 1.0

    // MARK: - State

    private struct Sample { let t: Date; let loc: CLLocation; let speed: CLLocationSpeed }
    private var samples: [Sample] = []

    // Explicit initializer — the synthesized memberwise init would be private
    // (because `samples` is private) and thus unreachable from the test target.
    init(accuracyGate: CLLocationAccuracy = 50,
         window: TimeInterval = 60,
         minSpeed: CLLocationSpeed = 1.0) {
        self.accuracyGate = accuracyGate
        self.window = window
        self.minSpeed = minSpeed
    }

    // MARK: - Ingest

    /// Feed a new location fix. Low-accuracy fixes are rejected. When the device
    /// doesn't supply a valid Doppler `speed`, it's derived from the distance/time
    /// delta to the previous accepted fix.
    mutating func add(_ loc: CLLocation) {
        guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < accuracyGate else { return }

        let speed: CLLocationSpeed
        if loc.speed >= 0 {
            speed = loc.speed
        } else if let prev = samples.last {
            let dt = loc.timestamp.timeIntervalSince(prev.t)
            speed = dt > 0 ? max(0, loc.distance(from: prev.loc) / dt) : 0
        } else {
            speed = 0
        }

        samples.append(Sample(t: loc.timestamp, loc: loc, speed: speed))
        prune(now: loc.timestamp)
    }

    // MARK: - Estimates

    /// Rolling-average speed (m/s) over the window, or nil if there are no samples.
    var averageSpeed: CLLocationSpeed? {
        guard !samples.isEmpty else { return nil }
        let total = samples.reduce(0.0) { $0 + $1.speed }
        return total / Double(samples.count)
    }

    /// The most recent accepted fix, if any.
    var lastLocation: CLLocation? { samples.last?.loc }

    /// Estimated time (seconds) to `destination` using straight-line (WGS84) distance
    /// ÷ rolling-average speed. Returns nil when stopped or lacking data.
    ///
    /// NOTE: straight-line distance under-estimates real track/road distance, biasing
    /// the alarm early; the GTFS route-distance upgrade is the planned fix (design §10).
    func eta(to destination: CLLocationCoordinate2D) -> TimeInterval? {
        guard let v = averageSpeed, v >= minSpeed, let last = samples.last?.loc else { return nil }
        let dest = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        return last.distance(from: dest) / v
    }

    /// Whether the alarm should fire now: ETA is known and within the lead time.
    func shouldFire(to destination: CLLocationCoordinate2D, leadTimeMinutes: Int) -> Bool {
        guard let eta = eta(to: destination) else { return false }
        return eta <= Double(leadTimeMinutes) * 60
    }

    // MARK: - Internal

    private mutating func prune(now: Date) {
        samples.removeAll { now.timeIntervalSince($0.t) > window }
    }
}
