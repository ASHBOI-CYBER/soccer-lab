// The streak is a FIRE (2026-10-26, user: "replace the streak icon with a 3d fire that animates really well and is
// interactive because people think of streak as fire"). A raymarched 3D flame (StreakFire.metal) + embers.
//   heat  = how much streak time is left (1 = just trained, the flame shrinks as the 3-day window runs down)
//   It is NEVER out (2026-10-26, user: "the streak should never have no flame, that is terrible") ? a 0-day streak is a
//   small low flame; the shader's grey-smoke `dead` mode is no longer used.
// Touch it: TAP = it flares up and spits embers; DRAG = it leans after your finger and twists round (it's a real
// volume, so you see it from the side); let go and it springs back and wobbles.
import SwiftUI

struct StreakFire: View {
    /// The same shader with stand-in values ? compiled at launch so Stats/Profile don't stall the first time (App.swift).
    static var shader: Shader {
        ShaderLibrary.streakFire(.float2(1, 1), .float(0), .float(1), .float(0), .float(0), .float(0), .float(0))
    }
    var heat: Double = 1
    private let dead = false
    var size: CGFloat = 220
    var interactive = true

    @State private var flareAt: Date = .distantPast
    @State private var flares = 0
    // drag ? lean + spin; on release both spring back in closed form (no per-frame state)
    @State private var dragX: CGFloat?
    @State private var baseSpin = 0.0
    @State private var releaseAt: Date = .distantPast
    @State private var releaseLean = 0.0
    @State private var releaseSpin = 0.0
    @State private var spinVel = 0.0
    @State private var lastDrag: (x: CGFloat, t: Date)?

    var body: some View {
        TimelineView(.animation) { tl in
            let now = tl.date
            let t = now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2000)
            let sinceFlare = now.timeIntervalSince(flareAt)
            let flare = sinceFlare < 4 ? exp(-sinceFlare * 1.5) * (1 - exp(-sinceFlare * 14)) : 0
            let (lean, spin) = motion(now)
            ZStack {
                // the warm pool of light on the ground
                Ellipse()
                    .fill(RadialGradient(colors: [dead ? C.muted.opacity(0.18) : Color(hex: 0xFF8A1E).opacity(0.38 + 0.3 * flare),
                                                  .clear], center: .center, startRadius: 0, endRadius: size * 0.42))
                    .frame(width: size * 0.95, height: size * 0.2)
                    .offset(y: size * 0.34)
                    .blur(radius: 3)
                Rectangle()
                    .fill(.white)
                    .colorEffect(ShaderLibrary.streakFire(.float2(size, size), .float(t),
                                                          .float(max(0, min(1, heat))), .float(flare),
                                                          .float(lean), .float(spin), .float(dead ? 1 : 0)))
                    .frame(width: size, height: size)
                // sparks get a canvas 2× the fire, so they fly free instead of stopping at the fire's square
                Embers(time: t, size: size, dead: dead, heat: heat, flare: flare, burst: sinceFlare, seed: flares, lean: lean)
                    .frame(width: size * 2, height: size * 2)
                    .allowsHitTesting(false)
            }
            .frame(width: size, height: size)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(interactive ? drag : nil)   // simultaneous: the page still scrolls
        .simultaneousGesture(interactive ? TapGesture().onEnded { stoke() } : nil)
        .accessibilityHidden(true)
    }

    private func stoke() {
        flareAt = Date()
        flares += 1
        Haptics.play(dead ? .stud : .roar)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { v in
                let now = Date()
                if dragX == nil { baseSpin = currentSpin(now); Haptics.play(.press) }
                if let l = lastDrag {
                    let dt = now.timeIntervalSince(l.t)
                    if dt > 0.001 { spinVel = Double(v.translation.width - l.x) / dt * 0.012 }
                }
                lastDrag = (v.translation.width, now)
                dragX = v.translation.width
            }
            .onEnded { v in
                let now = Date()
                releaseLean = leanFor(v.translation.width)
                releaseSpin = baseSpin + Double(v.translation.width) * 0.02
                releaseAt = now
                dragX = nil
                lastDrag = nil
                Haptics.play(.release)
            }
    }

    private func leanFor(_ x: CGFloat) -> Double { Double(max(-1, min(1, x / (size * 0.55)))) }

    private func currentSpin(_ now: Date) -> Double {
        let s = now.timeIntervalSince(releaseAt)
        // spin keeps coasting after release, slowing down
        return releaseSpin + spinVel * (1 - exp(-s * 1.6)) / 1.6
    }

    /// (lean, spin) right now: follows the finger while dragging, springs back + wobbles after.
    private func motion(_ now: Date) -> (Double, Double) {
        if let x = dragX { return (leanFor(x), baseSpin + Double(x) * 0.02) }
        let s = now.timeIntervalSince(releaseAt)
        let lean = s < 4 ? releaseLean * exp(-s * 3.2) * cos(s * 11) : 0
        return (lean, currentSpin(now))
    }
}

/// Sparks drifting up out of the flame. Deterministic per ember (seeded by its index), so no per-frame state:
/// a steady trickle + a burst on every tap.
private struct Embers: View {
    let time: Double
    let size: CGFloat
    let dead: Bool
    let heat: Double
    let flare: Double
    let burst: Double     // seconds since the last tap
    let seed: Int
    let lean: Double

    var body: some View {
        Canvas { ctx, sz in
            let base = CGPoint(x: sz.width / 2, y: sz.height / 2 + size * 0.3)   // the flame's foot
            let S = Double(size)
            func rnd(_ i: Int, _ k: Int) -> Double {
                let v = sin(Double(i) * 12.9898 + Double(k) * 78.233) * 43758.5453
                return v - floor(v)
            }
            func spark(_ p: CGPoint, r: CGFloat, life: Double, hot: Bool) {
                let a = max(0, 1 - life)
                let col = hot ? (life < 0.35 ? Color(hex: 0xFFF0B0) : life < 0.7 ? C.gold : Color(hex: 0xFF7A1A))
                              : Color(hex: 0xB0A89A)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 2.2, y: p.y - r * 2.2, width: r * 4.4, height: r * 4.4)),
                         with: .color(col.opacity(0.18 * a)))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(col.opacity(a)))
            }
            // steady trickle
            let count = dead ? 4 : Int(7 + 7 * heat)
            for i in 0..<count {
                let period = 1.6 + rnd(i, 1) * 1.4
                let life = ((time + rnd(i, 2) * period) / period).truncatingRemainder(dividingBy: 1)
                let rise = life * S * (dead ? 0.35 : 0.62 + 0.15 * heat)
                let x0 = (rnd(i, 3) - 0.5) * S * 0.28
                let wig = sin(time * (2 + rnd(i, 4) * 3) + Double(i)) * 9 * life
                let drift = lean * rise * rise / S * 0.6
                let p = CGPoint(x: base.x + x0 + wig + drift, y: base.y - 20 - rise)
                spark(p, r: CGFloat(1 + rnd(i, 5) * 1.6) * size / 220, life: life, hot: !dead)
            }
            // tap burst: embers thrown up and out, falling back under gravity
            if burst < 2.2 {
                let n = dead ? 6 : 18
                for i in 0..<n {
                    let k = seed * 31 + i
                    let ang = -Double.pi / 2 + (rnd(k, 6) - 0.5) * 2.2
                    let speed = (180 + rnd(k, 7) * 260) * S / 220 * (dead ? 0.45 : 1)
                    let tt = burst * (0.8 + rnd(k, 8) * 0.4)
                    let x = base.x + CGFloat(cos(ang) * speed * tt)
                    // split in steps: Swift 6.4 (Xcode 27) can't type-check it as one line
                    let throwUp: Double = sin(ang) * speed * tt
                    let fall: Double = 260 * tt * tt * S / 220
                    let top: CGFloat = base.y - size * 0.25
                    let y = top + CGFloat(throwUp + fall)
                    spark(CGPoint(x: x, y: y), r: CGFloat(1.2 + rnd(k, 9) * 1.8) * size / 220, life: burst / 2.2, hot: !dead)
                }
            }
        }
        .blendMode(.plusLighter)
    }
}
