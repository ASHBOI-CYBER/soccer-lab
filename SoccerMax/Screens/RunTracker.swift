// LIVE RUN (SOCCER LAB, 2026-11-12). GPS tracking for fitness work: distance, time, pace, top speed and the route on
// a map. Location is used only while a run is on, stays on the phone, and is never sent to the server. Tracking
// keeps going with the screen locked (the "location" background mode); iOS shows its blue indicator while it does.
import CoreLocation
import MapKit
import Observation
import SwiftUI

struct RunLog: Codable, Identifiable, Hashable {
    var id = UUID()
    var date = Date()
    var meters: Double
    var seconds: Double
    /// Fastest moment, metres per second.
    var topSpeed: Double

    var km: Double { meters / 1000 }
    /// Minutes per kilometre, nil for a run too short to say.
    var pace: Double? { meters >= 50 ? (seconds / 60) / (meters / 1000) : nil }
}

enum RunFormat {
    static func distance(_ meters: Double) -> String { String(format: "%.2f", meters / 1000) }
    static func time(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.down))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) : String(format: "%02d:%02d", s / 60, s % 60)
    }
    static func pace(_ minPerKm: Double?) -> String {
        guard let p = minPerKm, p.isFinite, p > 0, p < 60 else { return "--:--" }
        let total = Int((p * 60).rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
    static func speed(_ mps: Double) -> String { String(format: "%.1f", max(0, mps) * 3.6) }
}

@MainActor @Observable
final class RunTracker: NSObject, CLLocationManagerDelegate {
    static let shared = RunTracker()

    enum Phase { case idle, running, paused }
    private(set) var phase: Phase = .idle
    private(set) var meters: Double = 0
    private(set) var seconds: Double = 0
    private(set) var speed: Double = 0
    private(set) var topSpeed: Double = 0
    private(set) var route: [CLLocationCoordinate2D] = []
    /// Location is switched off for the app in Settings.
    private(set) var denied = false
    /// No usable GPS fix yet (indoors, or just started).
    private(set) var searching = true

    private let manager = CLLocationManager()
    private var last: CLLocation?
    private var resumedAt: Date?
    private var banked: Double = 0
    private var ticker: Timer?

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 3
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
    }

    var pace: Double? { meters >= 50 ? (seconds / 60) / (meters / 1000) : nil }

    func start() {
        meters = 0; seconds = 0; speed = 0; topSpeed = 0; route = []; last = nil; banked = 0
        searching = true
        let status = manager.authorizationStatus
        denied = status == .denied || status == .restricted
        if status == .notDetermined { manager.requestWhenInUseAuthorization() }
        resume()
    }

    func resume() {
        guard phase != .running else { return }
        phase = .running
        resumedAt = Date()
        last = nil                       // don't count the gap while paused as distance
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func pause() {
        guard phase == .running else { return }
        tick()
        banked = seconds
        resumedAt = nil
        phase = .paused
        speed = 0
        stopUpdates()
    }

    /// Ends the run and hands back what was recorded.
    func finish() -> RunLog {
        if phase == .running { tick() }
        let log = RunLog(meters: meters, seconds: seconds, topSpeed: topSpeed)
        phase = .idle
        resumedAt = nil
        stopUpdates()
        return log
    }

    private func stopUpdates() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        ticker?.invalidate()
        ticker = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func tick() {
        guard let t = resumedAt else { return }
        seconds = banked + Date().timeIntervalSince(t)
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        Task { @MainActor in self.authorization(s) }
    }

    private func authorization(_ s: CLAuthorizationStatus) {
        denied = s == .denied || s == .restricted
        if phase == .running, s == .authorizedWhenInUse || s == .authorizedAlways { manager.startUpdatingLocation() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in self.take(locations) }
    }

    private func take(_ locations: [CLLocation]) {
        guard phase == .running else { return }
        for loc in locations {
            // skip poor fixes and stale ones: they add distance that was never run
            guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy <= 30, abs(loc.timestamp.timeIntervalSinceNow) < 10 else { continue }
            searching = false
            if let prev = last {
                let d = loc.distance(from: prev)
                let dt = loc.timestamp.timeIntervalSince(prev.timestamp)
                // a jump faster than any person runs is a GPS glitch, not movement
                if dt > 0, d / dt < 12 {
                    meters += d
                    let v = loc.speed >= 0 ? loc.speed : d / dt
                    speed = v
                    if v > topSpeed, v < 12 { topSpeed = v }
                    route.append(loc.coordinate)
                }
            } else {
                route.append(loc.coordinate)
            }
            last = loc
        }
        if route.count > 4000 { route = stride(from: 0, to: route.count, by: 2).map { route[$0] } }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let off = (error as? CLError)?.code == .denied
        Task { @MainActor in if off { self.denied = true } }
    }
}

// MARK: - the run screen

struct RunView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var run = RunTracker.shared
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    // test builds: `-route tab:training:runsaved` shows the summary with a made-up run (nothing is saved)
    @State private var done: RunLog? = DebugRoute.parts.contains("runsaved") ? RunLog(meters: 5230, seconds: 1684, topSpeed: 6.4) : nil
    @State private var confirmEnd = false

    var body: some View {
        ZStack {
            AppBackground()
            if let done { summary(done) } else { live }
        }
        .onAppear { if run.phase == .idle, done == nil { run.start() } }
        .confirmationDialog("End this run?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End and save") { end() }
            Button("Keep going", role: .cancel) {}
        }
    }

    private var live: some View {
        VStack(spacing: 16) {
            HStack {
                Disp("LIVE RUN", size: 28)
                Spacer()
                Text(run.phase == .paused ? "PAUSED" : run.searching ? "FINDING GPS…" : "TRACKING")
                    .font(F.round(13, .bold)).kerning(1.2)
                    .foregroundStyle(run.phase == .paused ? C.gold : run.searching ? C.muted : C.brandHi)
            }
            .padding(.top, 8)

            Map(position: $camera) {
                UserAnnotation()
                if run.route.count > 1 { MapPolyline(coordinates: run.route).stroke(C.brand, lineWidth: 5) }
            }
            .frame(height: 230)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(C.line, lineWidth: 1))

            if run.denied {
                VStack(spacing: 8) {
                    Text("Location is off for Soccer Lab, so distance can't be measured.")
                        .font(F.round(14, .semibold)).foregroundStyle(C.gold).multilineTextAlignment(.center)
                    Button("Open Settings") {
                        if let u = URL(string: UIApplication.openSettingsURLString) { openURL(u) }
                    }
                    .font(F.round(15, .bold)).foregroundStyle(C.brandHi)
                }
            }

            VStack(spacing: 2) {
                Disp(RunFormat.distance(run.meters), size: 76)
                Text("KILOMETRES").font(F.round(13, .bold)).kerning(1.4).foregroundStyle(C.muted)
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: 10) {
                stat("TIME", RunFormat.time(run.seconds))
                stat("PACE /KM", RunFormat.pace(run.pace))
                stat("KM/H", RunFormat.speed(run.speed))
            }

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                Button(run.phase == .paused ? "RESUME" : "PAUSE") {
                    if run.phase == .paused { run.resume() } else { run.pause() }
                }
                .buttonStyle(.game(.charcoal))
                Button("FINISH") { confirmEnd = true }
                    .buttonStyle(.game(.brand))
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(F.round(24, .bold)).foregroundStyle(C.creme).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(F.round(11, .bold)).kerning(1.1).foregroundStyle(C.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(C.char800))
        .accessibilityElement(children: .combine)
    }

    private func summary(_ r: RunLog) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "flag.checkered").font(.system(size: 50, weight: .bold)).foregroundStyle(C.brand)
            Disp("RUN SAVED", size: 34)
            VStack(spacing: 2) {
                Disp(RunFormat.distance(r.meters), size: 64)
                Text("KILOMETRES").font(F.round(13, .bold)).kerning(1.4).foregroundStyle(C.muted)
            }
            HStack(spacing: 10) {
                stat("TIME", RunFormat.time(r.seconds))
                stat("PACE /KM", RunFormat.pace(r.pace))
                stat("TOP KM/H", RunFormat.speed(r.topSpeed))
            }
            Spacer()
            Button("DONE") { dismiss() }.buttonStyle(.gameLarge(.brand, feel: .kick))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func end() {
        let log = run.finish()
        // a run under 20 seconds is a mis-tap: nothing is saved
        if log.seconds >= 20 {
            Lab.shared.add(run: log)
            let k = dateKey(Date())
            store.trained[k] = (store.trained[k] ?? 0) + log.seconds / 60
            Haptics.play(.goal)
            withAnimation(.snappy) { done = log }
        } else {
            dismiss()
        }
    }
}
