// MAP tab (2026-11-08): where a session was played. One quick location fix when a session starts (and again at the
// end), rounded to ~100 m so no exact address is ever saved or sent. Only "while using the app" ? never in the
// background. `onMap` (Map tab ? filter menu ? "My sessions on the map", 2026-11-08 v2): off = my sessions get no dot,
// for me or my teammates (no spot is sent with the team post).
import CoreLocation
import Observation

@Observable
@MainActor
final class SessionSpot: NSObject, CLLocationManagerDelegate {
    static let shared = SessionSpot()

    struct Spot: Equatable { let lat: Double; let lng: Double }

    /// The last rounded fix (nil = location off / not known yet).
    private(set) var here: Spot?
    private(set) var status: CLAuthorizationStatus
    var onMap: Bool = UserDefaults.standard.object(forKey: "sm.map.share") as? Bool ?? true {
        didSet { UserDefaults.standard.set(onMap, forKey: "sm.map.share") }
    }

    private let manager = CLLocationManager()

    override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var allowed: Bool { status == .authorizedWhenInUse || status == .authorizedAlways }

    /// Ask once (the system shows its prompt the first time only), then take one fix.
    func refresh() {
        if status == .notDetermined { manager.requestWhenInUseAuthorization() }
        else if allowed { manager.requestLocation() }
    }

    /// ~100 m grid: enough to show the park, not the house.
    static func round(_ c: CLLocationCoordinate2D) -> Spot {
        Spot(lat: (c.latitude * 1000).rounded() / 1000, lng: (c.longitude * 1000).rounded() / 1000)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        let s = m.authorizationStatus
        Task { @MainActor in
            self.status = s
            if self.allowed { self.manager.requestLocation() }
        }
    }
    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        guard let c = locs.last?.coordinate else { return }
        Task { @MainActor in self.here = Self.round(c) }
    }
    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {}
}
