// SOCCER LAB haptics: every control has its own feel, named after something on the pitch.
// Same patterns as the web kit (src/ui/game/haptics.ts), played straight on the Taptic Engine.
import CoreHaptics
import UIKit

enum Haptic: String {
    case press, release, kick, latch, unlatch, stud, wall, pop, goal, post, roar, heartbeat, land
}

enum Haptics {
    private enum Impact { case selection, light, soft, medium, rigid, heavy }
    private struct Pulse { let at: Double; let style: Impact; var dur: Double? = nil }

    private static let patterns: [Haptic: [Pulse]] = [
        .press: [Pulse(at: 0, style: .light)],
        .release: [Pulse(at: 0, style: .rigid)],
        .kick: [Pulse(at: 0, style: .heavy), Pulse(at: 55, style: .soft)],
        .latch: [Pulse(at: 0, style: .rigid), Pulse(at: 75, style: .soft)],
        .unlatch: [Pulse(at: 0, style: .soft)],
        .stud: [Pulse(at: 0, style: .selection)],
        .wall: [Pulse(at: 0, style: .rigid), Pulse(at: 45, style: .rigid)],
        .pop: [Pulse(at: 0, style: .soft), Pulse(at: 38, style: .light)],
        .goal: [Pulse(at: 0, style: .light), Pulse(at: 70, style: .medium), Pulse(at: 140, style: .heavy), Pulse(at: 230, style: .soft, dur: 140)],
        .post: [Pulse(at: 0, style: .heavy), Pulse(at: 85, style: .rigid), Pulse(at: 150, style: .light), Pulse(at: 205, style: .selection)],
        .roar: [Pulse(at: 0, style: .soft, dur: 190), Pulse(at: 0, style: .selection), Pulse(at: 50, style: .light), Pulse(at: 95, style: .light),
                Pulse(at: 135, style: .medium), Pulse(at: 170, style: .medium), Pulse(at: 200, style: .heavy), Pulse(at: 330, style: .heavy)],
        .heartbeat: [Pulse(at: 0, style: .medium), Pulse(at: 150, style: .light)],
        .land: [Pulse(at: 0, style: .soft)],
    ]

    private static func feel(_ s: Impact) -> (Float, Float) {
        switch s {
        case .selection: (0.45, 0.9)
        case .light: (0.55, 0.55)
        case .soft: (0.7, 0.08)
        case .medium: (0.8, 0.4)
        case .rigid: (0.9, 1)
        case .heavy: (1, 0.2)
        }
    }

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "sm.haptics") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "sm.haptics") }
    }

    private static let supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private static var engine: CHHapticEngine? = {
        guard supported, let e = try? CHHapticEngine() else { return nil }
        e.playsHapticsOnly = true
        e.isAutoShutdownEnabled = true
        e.resetHandler = { try? e.start() }
        try? e.start()
        return e
    }()

    /// The Taptic Engine lives on its own queue: `engine.start()` (it auto-shuts down when idle) and making a player
    /// block for a moment ? on the main thread that was a hitch on EVERY tap and tab switch (2026-10-28, "snappy").
    private static let queue = DispatchQueue(label: "sm.haptics", qos: .userInteractive)

    /// Build + start the engine at launch, so the first tap doesn't pay for it.
    static func warm() { queue.async { _ = engine } }

    static func play(_ name: Haptic) {
        guard let pulses = patterns[name] else { return }
        queue.async { playNow(pulses) }
    }

    private static func playNow(_ pulses: [Pulse]) {
        guard enabled else { return }
        guard let engine else { return fallback(pulses) }
        let events = pulses.map { p -> CHHapticEvent in
            let (i, s) = feel(p.style)
            let params = [CHHapticEventParameter(parameterID: .hapticIntensity, value: i),
                          CHHapticEventParameter(parameterID: .hapticSharpness, value: s)]
            if let d = p.dur {
                return CHHapticEvent(eventType: .hapticContinuous, parameters: params, relativeTime: p.at / 1000, duration: d / 1000)
            }
            return CHHapticEvent(eventType: .hapticTransient, parameters: params, relativeTime: p.at / 1000)
        }
        do {
            try engine.start()
            try engine.makePlayer(with: CHHapticPattern(events: events, parameters: [])).start(atTime: CHHapticTimeImmediate)
        } catch {
            fallback(pulses)
        }
    }

    private static func fallback(_ pulses: [Pulse]) {
        for p in pulses {
            DispatchQueue.main.asyncAfter(deadline: .now() + p.at / 1000) {
                switch p.style {
                case .selection: UISelectionFeedbackGenerator().selectionChanged()
                case .light: UIImpactFeedbackGenerator(style: .light).impactOccurred()
                case .soft: UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                case .medium: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                case .rigid: UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                case .heavy: UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                }
            }
        }
    }
}
