// This week's ball ? the Plan tab's centrepiece. A real truncated icosahedron (12 pentagons + 20 hexagons = 32
// panels) drawn natively in a Canvas, spinning on the centre spot. Every set you tick stitches one panel on:
// finish the week, finish the ball. Panels fill from the top down in day order (Monday's patch first); today's
// panels still to do pulse green; panels not earned yet are the empty sewing pattern. Drag to spin, tap a panel
// to open its day. The same panel + stitch language (`StitchBorder`, `PanelMark`) is used across the app.
import SwiftUI

// MARK: - geometry

struct V3 {
    var x, y, z: Double
    static func + (a: V3, b: V3) -> V3 { V3(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z) }
    static func - (a: V3, b: V3) -> V3 { V3(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z) }
    static func * (a: V3, k: Double) -> V3 { V3(x: a.x * k, y: a.y * k, z: a.z * k) }
    func dot(_ b: V3) -> Double { x * b.x + y * b.y + z * b.z }
    func cross(_ b: V3) -> V3 { V3(x: y * b.z - z * b.y, y: z * b.x - x * b.z, z: x * b.y - y * b.x) }
    var len: Double { sqrt(dot(self)) }
    var unit: V3 { self * (1 / len) }
    /// Spin about the pole (y), then tip toward the viewer (x).
    func rotated(yaw: Double, pitch: Double) -> V3 {
        let (cy, sy, cp, sp) = (cos(yaw), sin(yaw), cos(pitch), sin(pitch))
        let a = V3(x: x * cy + z * sy, y: y, z: -x * sy + z * cy)
        return V3(x: a.x, y: a.y * cp - a.z * sp, z: a.y * sp + a.z * cp)
    }
}

struct BallPanel {
    let pent: Bool
    let center: V3       // unit normal
    let ring: [V3]       // the panel's outline on the sphere (edges subdivided), inset for the seam
    let stitch: [V3]     // a smaller ring for the stitch line
}

enum BallGeometry {
    /// The 32 panels, ordered from the top pentagon down in rings ? the order they get stitched.
    static let panels: [BallPanel] = {
        let phi = (1 + sqrt(5.0)) / 2
        var v: [V3] = []
        for a in [-1.0, 1] { for b in [-phi, phi] {
            v += [V3(x: 0, y: a, z: b), V3(x: a, y: b, z: 0), V3(x: b, y: 0, z: a)]
        } }
        let n = v.count
        var nb = [[Int]](repeating: [], count: n)
        for i in 0..<n { for j in 0..<n where i != j && abs((v[i] - v[j]).len - 2) < 0.01 { nb[i].append(j) } }
        func cut(_ a: Int, _ b: Int) -> V3 { v[a] + (v[b] - v[a]) * (1.0 / 3) }

        var polys: [(Bool, [V3])] = []
        for i in 0..<n { polys.append((true, nb[i].map { cut(i, $0) })) }
        for i in 0..<n { for j in nb[i] where j > i { for k in nb[i] where k > j && nb[j].contains(k) {
            polys.append((false, [cut(i, j), cut(j, i), cut(j, k), cut(k, j), cut(k, i), cut(i, k)]))
        } } }

        // Put a pentagon on the pole: rotate so vertex 0's direction becomes +y.
        let top = v[0].unit
        let axis = top.cross(V3(x: 0, y: 1, z: 0))
        let ang = acos(max(-1, min(1, top.y)))
        func toPole(_ p: V3) -> V3 {
            guard axis.len > 1e-6 else { return p }
            let k = axis.unit, c = cos(ang), s = sin(ang)
            return p * c + k.cross(p) * s + k * (k.dot(p) * (1 - c))
        }

        let built: [BallPanel] = polys.map { pent, pts in
            let raw = pts.map(toPole)
            let c = raw.reduce(V3(x: 0, y: 0, z: 0), +).unit
            // Sort corners around the centre so every outline winds the same way.
            let ref = (raw[0] - c * raw[0].dot(c)).unit
            let side = c.cross(ref)
            let sorted = raw.sorted {
                let a = $0 - c * $0.dot(c), b = $1 - c * $1.dot(c)
                return atan2(a.dot(side), a.dot(ref)) < atan2(b.dot(side), b.dot(ref))
            }
            func ring(_ inset: Double) -> [V3] {
                var out: [V3] = []
                let m = sorted.count, steps = 5
                for i in 0..<m {
                    let a = sorted[i], b = sorted[(i + 1) % m]
                    for s in 0..<steps {
                        let p = (a + (b - a) * (Double(s) / Double(steps))).unit
                        out.append((c + (p - c) * inset).unit)
                    }
                }
                return out
            }
            return BallPanel(pent: pent, center: c, ring: ring(0.94), stitch: ring(0.8))
        }
        // Rings from the top down, then around ? a patch that grows like it's being sewn.
        return built.sorted {
            let ta = (acos($0.center.y) * 180 / .pi / 8).rounded(), tb = (acos($1.center.y) * 180 / .pi / 8).rounded()
            if ta != tb { return ta < tb }
            return atan2($0.center.z, $0.center.x) < atan2($1.center.z, $1.center.x)
        }
    }()
}

// MARK: - state

enum PanelState: Equatable { case stitched, next, missed, empty }

struct WeekBallModel: Equatable {
    var states: [PanelState]
    var days: [String?]          // the day each panel belongs to
    var stitched: Int { states.filter { $0 == .stitched }.count }
    static let count = 32
}

extension AppStore {
    /// Share the 32 panels between this week's training days (by sets), then stitch each day's done share.
    var weekBall: WeekBallModel {
        let n = WeekBallModel.count
        let days = DAYS.filter { !items($0).isEmpty && state($0) != .before }
        let totals = days.map { Double(totalSets($0)) }
        let sum = totals.reduce(0, +)
        guard sum > 0 else { return WeekBallModel(states: Array(repeating: .empty, count: n), days: Array(repeating: nil, count: n)) }
        // Largest remainder, so the shares always add up to 32.
        let exact = totals.map { $0 / sum * Double(n) }
        var share = exact.map { Int($0) }
        for i in exact.indices.sorted(by: { exact[$0] - Double(share[$0]) > exact[$1] - Double(share[$1]) }).prefix(n - share.reduce(0, +)) {
            share[i] += 1
        }
        var states: [PanelState] = [], owner: [String?] = []
        for (i, d) in days.enumerated() {
            let s = state(d)
            let got = s == .done ? share[i] : Int((Double(share[i]) * progress(d)).rounded(.down))
            let rest: PanelState = s == .today ? .next : s == .missed ? .missed : .empty
            states += Array(repeating: .stitched, count: got) + Array(repeating: rest, count: share[i] - got)
            owner += Array(repeating: d, count: share[i])
        }
        return WeekBallModel(states: states, days: owner)
    }
}

// MARK: - the ball

struct WeekBall: View {
    let model: WeekBallModel
    var size: CGFloat = 250
    var interactive = true
    var onTapDay: ((String) -> Void)? = nil

    @State private var spin = Spin()
    @State private var drag: CGSize = .zero
    @State private var appeared = Date()
    @State private var popAt: [Int: Date] = [:]
    @State private var shown: [PanelState] = []

    private struct Spin {
        var yaw0 = 0.6, t0 = Date(), vel = 0.0, tilt = 0.0, tiltAt = Date()
        static let auto = 0.32, tau = 0.9
        func yaw(_ t: Date) -> Double {
            let dt = t.timeIntervalSince(t0)
            return yaw0 + Self.auto * dt + vel * Self.tau * (1 - exp(-dt / Self.tau))
        }
        func pitch(_ t: Date) -> Double { 0.26 + tilt * exp(-t.timeIntervalSince(tiltAt) / 0.35) }
    }

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date
            let r = Double(size) / 2
            let yaw = spin.yaw(t) + Double(drag.width) / r
            let pitch = max(-0.2, min(0.95, spin.pitch(t) + Double(drag.height) / r * 0.6))
            Canvas { ctx, sz in draw(ctx, sz, t: t, yaw: yaw, pitch: pitch) }
                .frame(width: size, height: size)
                .offset(y: CGFloat(sin(t.timeIntervalSinceReferenceDate * 1.6)) * 3)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(interactive ? spinGesture : nil)
        .simultaneousGesture(interactive ? tapGesture : nil)
        .onAppear {
            shown = model.states
            appeared = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 + Double(model.stitched) * 0.035) {
                if model.stitched > 0 { Haptics.play(.pop) }
            }
        }
        .onChange(of: model) { _, m in
            let now = Date()
            for i in m.states.indices where m.states[i] == .stitched && shown[safe: i] != .stitched { popAt[i] = now }
            if m.stitched > shown.filter({ $0 == .stitched }).count { Haptics.play(.pop) }
            shown = m.states
        }
        .accessibilityElement()
        .accessibilityLabel("This week's ball: \(model.stitched) of \(WeekBallModel.count) panels stitched")
    }

    // MARK: drawing

    private func draw(_ ctx: GraphicsContext, _ sz: CGSize, t: Date, yaw: Double, pitch: Double) {
        let r = Double(sz.width) / 2 - 3
        let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
        let light = V3(x: -0.45, y: 0.62, z: 0.64).unit
        let pulse = 0.5 + 0.5 * sin(t.timeIntervalSinceReferenceDate * 4)
        func project(_ p: V3) -> CGPoint { CGPoint(x: c.x + p.x * r, y: c.y - p.y * r) }

        let disc = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        ctx.fill(disc, with: .color(C.charInk))  // the seams

        let panels = BallGeometry.panels
        let order = panels.indices
            .map { ($0, panels[$0].center.rotated(yaw: yaw, pitch: pitch)) }
            .filter { $0.1.z > -0.12 }
            .sorted { $0.1.z < $1.1.z }

        for (i, n) in order {
            let p = panels[i]
            let state = (i < model.states.count ? model.states[i] : .empty)
            // Intro: panels stitch on one after another; a new stitch pops.
            let intro = t.timeIntervalSince(appeared) - 0.25 - Double(i) * 0.035
            let isStitched = state == .stitched && intro > 0
            let since = popAt[i].map { t.timeIntervalSince($0) } ?? (state == .stitched ? intro : 9)
            let pop = since >= 0 && since < 0.45 ? sin(since / 0.45 * .pi) * (1 - since / 0.45) : 0
            let lift = 1 + pop * 0.12

            var path = Path()
            for (k, q) in p.ring.enumerated() {
                let s = project(q.rotated(yaw: yaw, pitch: pitch) * lift)
                k == 0 ? path.move(to: s) : path.addLine(to: s)
            }
            path.closeSubpath()

            let diffuse = max(0, n.dot(light))
            let shade = (0.5 + 0.6 * diffuse) * (0.72 + 0.28 * max(0, n.z))
            let base: RGB = switch (isStitched, state) {
            case (true, _): p.pent ? RGB(0x0F5FE0) : RGB(0xF2F6FF)
            case (_, .next): RGB(0x16264D)
            case (_, .missed): RGB(0x0A1226)
            default: RGB(0x101C3D)
            }
            ctx.fill(path, with: .color(base.scaled(isStitched ? shade : shade * 0.9 + 0.08)))
            if pop > 0 { ctx.fill(path, with: .color(.white.opacity(pop * 0.8))) }

            // Stitch line: thread on stitched panels, the dashed sewing pattern on empty ones.
            guard n.z > 0.15 else { continue }
            var st = Path()
            for (k, q) in p.stitch.enumerated() {
                let s = project(q.rotated(yaw: yaw, pitch: pitch) * lift)
                k == 0 ? st.move(to: s) : st.addLine(to: s)
            }
            st.closeSubpath()
            let fade = min(1, (n.z - 0.15) / 0.3)
            if isStitched {
                ctx.stroke(st, with: .color((p.pent ? Color.white : C.charInk).opacity(0.22 * fade)),
                           style: StrokeStyle(lineWidth: 1.3, lineCap: .round, dash: [2.2, 3.2]))
            } else if state == .next {
                ctx.fill(path, with: .color(C.brand.opacity(0.10 + 0.14 * pulse)))
                ctx.stroke(path, with: .color(C.brand.opacity((0.55 + 0.45 * pulse) * fade)), lineWidth: 2.2)
                ctx.stroke(st, with: .color(C.brandHi.opacity(0.6 * fade)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [2.5, 3.5]))
            } else if state == .empty {
                ctx.stroke(st, with: .color(C.creme.opacity(0.13 * fade)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [2.5, 3.5]))
            }
        }

        // Sphere light: a soft highlight top-left, a darker rim, the chunky ink outline.
        ctx.drawLayer { l in
            l.clip(to: disc)
            l.fill(disc, with: .radialGradient(Gradient(colors: [.white.opacity(0.28), .white.opacity(0)]),
                                               center: CGPoint(x: c.x - r * 0.38, y: c.y - r * 0.45), startRadius: 0, endRadius: r * 0.75))
            l.fill(disc, with: .radialGradient(Gradient(stops: [.init(color: .clear, location: 0.62), .init(color: .black.opacity(0.42), location: 1)]),
                                               center: c, startRadius: 0, endRadius: r))
        }
        ctx.stroke(disc, with: .color(C.charInk), lineWidth: 3.5)
    }

    // MARK: gestures

    private var spinGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { drag = $0.translation }
            .onEnded { g in
                let now = Date()
                let r = Double(size) / 2
                spin.yaw0 = spin.yaw(now) + Double(g.translation.width) / r
                spin.t0 = now
                spin.vel = max(-14, min(14, Double(g.predictedEndTranslation.width - g.translation.width) / r * 2.2))
                spin.tilt = spin.pitch(now) - 0.26 + Double(g.translation.height) / r * 0.6
                spin.tilt = max(-0.45, min(0.69, spin.tilt))
                spin.tiltAt = now
                drag = .zero
                Haptics.play(.stud)
            }
    }

    private var tapGesture: some Gesture {
        SpatialTapGesture().onEnded { e in
            guard let onTapDay else { return }
            let t = Date()
            let r = Double(size) / 2 - 3
            let yaw = spin.yaw(t), pitch = spin.pitch(t)
            let c = CGPoint(x: size / 2, y: size / 2)
            let hit = BallGeometry.panels.indices
                .map { ($0, BallGeometry.panels[$0].center.rotated(yaw: yaw, pitch: pitch)) }
                .filter { $0.1.z > 0 }
                .sorted { $0.1.z > $1.1.z }
                .first { i, _ in
                    var path = Path()
                    for (k, q) in BallGeometry.panels[i].ring.enumerated() {
                        let p = q.rotated(yaw: yaw, pitch: pitch)
                        let s = CGPoint(x: c.x + p.x * r, y: c.y - p.y * r)
                        k == 0 ? path.move(to: s) : path.addLine(to: s)
                    }
                    return path.contains(e.location)
                }
            if let (i, _) = hit, let d = model.days[safe: i] ?? nil {
                Haptics.play(.press)
                onTapDay(d)
            }
        }
    }
}

private struct RGB {
    let r, g, b: Double
    init(_ hex: UInt32) { r = Double((hex >> 16) & 0xFF) / 255; g = Double((hex >> 8) & 0xFF) / 255; b = Double(hex & 0xFF) / 255 }
    func scaled(_ k: Double) -> Color { Color(red: min(1, r * k), green: min(1, g * k), blue: min(1, b * k)) }
}

// MARK: - the pitch it sits on

/// The centre circle in perspective and the halfway line ? the ball sits on the centre spot.
struct CentreSpot: View {
    var width: CGFloat = 340
    var body: some View {
        Canvas { ctx, s in
            let mid = CGPoint(x: s.width / 2, y: s.height / 2)
            var line = Path()
            line.move(to: CGPoint(x: 0, y: mid.y))
            line.addLine(to: CGPoint(x: s.width, y: mid.y))
            ctx.stroke(line, with: .linearGradient(Gradient(colors: [.white.opacity(0), .white.opacity(0.09), .white.opacity(0)]),
                                                   startPoint: .zero, endPoint: CGPoint(x: s.width, y: 0)), lineWidth: 2)
            let circle = Path(ellipseIn: CGRect(x: mid.x - width / 2, y: mid.y - width * 0.12, width: width, height: width * 0.24))
            ctx.stroke(circle, with: .color(.white.opacity(0.09)), lineWidth: 2)
            ctx.fill(Path(ellipseIn: CGRect(x: mid.x - 60, y: mid.y - 11, width: 120, height: 22)), with: .color(.black.opacity(0.5)))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - the shared language (used across the app)

/// A stitched seam just inside a shape's edge ? the ball's thread, on any card.
struct StitchBorder<S: InsettableShape>: View {
    let shape: S
    var color: Color = C.creme
    var opacity: Double = 0.14
    var inset: CGFloat = 6
    var body: some View {
        shape.inset(by: inset)
            .stroke(color.opacity(opacity), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [3, 4.5]))
            .allowsHitTesting(false)
    }
}

extension View {
    /// The ball's stitched seam around a card.
    func stitched(_ radius: CGFloat, color: Color = C.creme, opacity: Double = 0.14, inset: CGFloat = 6) -> some View {
        overlay(StitchBorder(shape: RoundedRectangle(cornerRadius: max(0, radius), style: .continuous), color: color, opacity: opacity, inset: inset))
    }
}

/// One ball panel as a mark ? a hexagon (or pentagon) filled, pulsing or empty. Replaces dots and pills.
struct PanelMark: View {
    var state: PanelState = .stitched
    var pent = false
    var size: CGFloat = 18
    var body: some View {
        let shape = PanelShape(sides: pent ? 5 : 6)
        ZStack {
            switch state {
            case .stitched:
                shape.fill(pent ? C.brandMid : C.creme)
                shape.inset(by: size * 0.2).stroke((pent ? Color.white : C.charInk).opacity(0.3),
                                                    style: StrokeStyle(lineWidth: 1, dash: [1.5, 2]))
            case .next:
                shape.fill(C.brand.opacity(0.18))
                shape.stroke(C.brand, lineWidth: 1.8)
            case .missed, .empty:
                shape.fill(C.char800)
                shape.inset(by: size * 0.2).stroke(C.creme.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [1.5, 2]))
            }
            shape.stroke(C.charInk, lineWidth: state == .next ? 0 : 1.6)
        }
        .frame(width: size, height: size)
    }
}

struct PanelShape: InsettableShape {
    var sides = 6
    var amount: CGFloat = 0
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2 - amount
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        for i in 0..<sides {
            let a = Double(i) / Double(sides) * 2 * .pi - .pi / 2
            let pt = CGPoint(x: c.x + CGFloat(cos(a)) * r, y: c.y + CGFloat(sin(a)) * r)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath()
        return p
    }
    func inset(by a: CGFloat) -> PanelShape { var s = self; s.amount += a; return s }
}
