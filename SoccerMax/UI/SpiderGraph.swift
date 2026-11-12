// PROFILE spider graph (2026-10-27). The user: "replace [the card] instead with just a spider graph with the player's
// name or pfp pic (whichever they put down) in the middle. Then, a little less stats but based on training and
// onboarding. Make the UI super good."
//   START = the six stats from onboarding (CardMath) ? a dashed creme outline.
//   NOW   = START + what training added: every ticked set of a drill feeds the stats that drill trains
//           (`Drill.stats`), with diminishing returns ? the green web that grows.
// In the middle: the profile photo, or the first name on grass. Tap a stat to see where it came from.
import SwiftUI

// MARK: - the maths

struct SpiderStats: Equatable {
    var start: [String: Int]
    var now: [String: Int]
    var sets: [String: Int]          // sets trained that fed each stat
    var gain: [String: Int] { Dictionary(uniqueKeysWithValues: STATS.map { ($0, (now[$0] ?? 0) - (start[$0] ?? 0)) }) }
    var totalGain: Int { gain.values.reduce(0, +) }
    var best: String { STATS.max { (now[$0] ?? 0) < (now[$1] ?? 0) }! }

    /// Points a stat gains from N sets: +4 at 10 sets, +8 at 30, +12 at 70 ? capped at +18.
    static func boost(_ sets: Int) -> Int { min(18, Int((4 * log2(1 + Double(sets) / 10)).rounded())) }
}

extension AppStore {
    var spider: SpiderStats {
        let start = CardMath.card(answers).stats
        var sets: [String: Int] = [:]
        for day in log.values {
            for (id, n) in day where n > 0 && Library.shared.has(id) {
                for s in Library.shared.drill(id).stats where STATS.contains(s) { sets[s, default: 0] += n }
            }
        }
        var now = start
        for k in STATS { now[k] = min(99, (start[k] ?? 0) + SpiderStats.boost(sets[k] ?? 0)) }
        return SpiderStats(start: start, now: now, sets: sets)
    }

    #if DEBUG
    /// DEBUG `profile:spider`: a few weeks of ticked sets so the web has grown.
    func seedSpiderDemo() {
        let picks = ["toe-taps", "cone-slalom", "wall-passes", "speed-dribble", "juggling", "figure-8", "weak-foot-laces", "front-plank", "repeat-sprints"]
        var l: [String: [String: Int]] = [:]
        for back in 0..<24 where back % 2 == 0 || back % 5 == 0 {
            let k = dateKey(addDays(Date(), -back))
            for (i, id) in picks.enumerated() where (back + i) % 3 != 0 { l[k, default: [:]][id] = 2 + (back + i) % 3 }
        }
        log = l
    }
    #endif
}

// MARK: - the card

struct SpiderCard: View {
    @Environment(AppStore.self) private var store
    @State private var focus: String?

    var body: some View {
        let sp = store.spider
        VStack(spacing: 0) {
            header(sp)
            SpiderGraph(stats: sp, center: center, focus: $focus)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .padding(.top, 4)
            footer(sp)
                .frame(height: 44)
                .animation(.snappy, value: focus)
        }
        .padding(.horizontal, 14).padding(.top, 16).padding(.bottom, 12)
        .gameCard(padding: 0, radius: 28)
    }

    private var center: SpiderCenter {
        if let img = store.avatar { return .photo(img) }
        return .name(store.answers.firstName)
    }

    private func header(_ sp: SpiderStats) -> some View {
        let ovr = CardMath.overall(sp.now, store.answers.position)
        return HStack(alignment: .center, spacing: 10) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Disp("\(ovr)", size: 34, color: C.brand)
                    .contentTransition(.numericText())
                Text("OVR · \(store.answers.position)").font(F.round(14, .bold)).foregroundStyle(C.muted)
            }
            Spacer(minLength: 8)
            gainPill(ovr - CardMath.overall(sp.start, store.answers.position))
        }
        .padding(.horizontal, 6)
        .accessibilityElement(children: .combine)
    }

    private func gainPill(_ g: Int) -> some View {
        HStack(spacing: 5) {
            Image(systemName: g > 0 ? "arrow.up.right" : "figure.soccer").font(.system(size: 12, weight: .heavy))
            Text(g > 0 ? "+\(g) OVR FROM TRAINING" : "TRAIN TO GROW IT").font(F.display(13)).kerning(0.4)
        }
        .foregroundStyle(g > 0 ? C.brandInk : C.creme2)
        .padding(.horizontal, 11).frame(height: 30)
        .background(Capsule().fill(g > 0 ? C.brand : C.char700))
        .overlay(Capsule().stroke(g > 0 ? C.brandInk : C.charInk, lineWidth: 2))
    }

    @ViewBuilder private func footer(_ sp: SpiderStats) -> some View {
        if let k = focus {
            let g = sp.gain[k] ?? 0, n = sp.sets[k] ?? 0
            HStack(spacing: 8) {
                Text(STAT_NAME[k] ?? k).font(F.round(16, .bold)).foregroundStyle(C.creme)
                Text("\(sp.start[k] ?? 0) from onboarding").font(F.round(14, .semibold)).foregroundStyle(C.muted)
                if g > 0 {
                    Text("+\(g) · \(n) sets").font(F.round(14, .bold)).foregroundStyle(C.brand)
                }
            }
            .lineLimit(1).minimumScaleFactor(0.8)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .id(k)
        } else {
            HStack(spacing: 18) {
                legend(dashed: true, "START")
                legend(dashed: false, "NOW")
            }
            .transition(.opacity)
        }
    }

    private func legend(dashed: Bool, _ t: String) -> some View {
        HStack(spacing: 7) {
            Capsule()
                .stroke(dashed ? C.creme.opacity(0.6) : C.brand, style: StrokeStyle(lineWidth: dashed ? 2 : 3.5, lineCap: .round, dash: dashed ? [4, 4] : []))
                .frame(width: 22, height: 0.5)
            Text(t).font(F.round(13, .bold)).foregroundStyle(dashed ? C.muted : C.creme2)
        }
    }
}

// MARK: - the graph

enum SpiderCenter { case photo(UIImage), name(String) }

struct SpiderGraph: View {
    let stats: SpiderStats
    let center: SpiderCenter
    var focus: Binding<String?> = .constant(nil)
    /// Share images skip the grow-in.
    var still = false
    /// The dark hexagon plate + its ink border. Off in onboarding, where it sat on the gold rays as a hard ring (2026-10-29).
    var plate = true
    @State private var grow = 0.0

    private static let lo = 35.0, hi = 99.0

    var body: some View {
        GeometryReader { g in
            let side = min(g.size.width, g.size.height)
            let R = side * 0.33
            let c = CGPoint(x: g.size.width / 2, y: g.size.height / 2)
            let r0 = R * 0.34                      // the centre badge's radius
            let t = still ? 1 : grow
            ZStack {
                Canvas { ctx, _ in draw(ctx, c: c, R: R, r0: r0, t: t) }
                badge(r0 * 2)
                    .position(c)
                    .scaleEffect(still ? 1 : 0.6 + 0.4 * min(1, grow * 1.4), anchor: .center)
                ForEach(Array(STATS.enumerated()), id: \.element) { i, k in
                    label(k).position(point(i, R + side * 0.105, c))
                }
            }
        }
        .onAppear {
            guard !still else { return }
            grow = 0
            withAnimation(.spring(response: 0.6, dampingFraction: 0.72)) { grow = 1 }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(STATS.map { "\(STAT_NAME[$0] ?? $0) \(stats.now[$0] ?? 0)" }.joined(separator: ", "))
    }

    private func angle(_ i: Int) -> Double { -.pi / 2 + Double(i) * 2 * .pi / Double(STATS.count) }
    private func point(_ i: Int, _ r: CGFloat, _ c: CGPoint) -> CGPoint {
        CGPoint(x: c.x + r * CGFloat(Foundation.cos(angle(i))), y: c.y + r * CGFloat(Foundation.sin(angle(i))))
    }
    private func radius(_ v: Int, R: CGFloat, r0: CGFloat) -> CGFloat {
        let f = (Double(v) - Self.lo) / (Self.hi - Self.lo)
        return r0 + 8 + (R - r0 - 8) * CGFloat(max(0, min(1, f)))
    }
    private func poly(_ rs: [CGFloat], _ c: CGPoint) -> Path {
        var p = Path()
        for (i, r) in rs.enumerated() {
            let pt = point(i, r, c)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }

    private func draw(_ ctx: GraphicsContext, c: CGPoint, R: CGFloat, r0: CGFloat, t: Double) {
        let n = STATS.count
        // the pitch-dark web: outer plate, three stitched rings, spokes
        let outer = poly(Array(repeating: R, count: n), c)
        let k = CGFloat(t)
        let startR = STATS.map { r0 + (radius(stats.start[$0] ?? 0, R: R, r0: r0) - r0) * k }
        let nowR = STATS.map { r0 + (radius(stats.now[$0] ?? 0, R: R, r0: r0) - r0) * k }
        let grew = stats.totalGain > 0

        if plate {
            ctx.fill(outer, with: .linearGradient(Gradient(colors: [C.char700.opacity(0.55), C.char900.opacity(0.4)]),
                                                   startPoint: CGPoint(x: c.x, y: c.y - R), endPoint: CGPoint(x: c.x, y: c.y + R)))
            ctx.stroke(outer, with: .color(C.charInk), lineWidth: 2.5)
        }
        // rings + spokes only OUTSIDE the green web, so no dashed rings show through it (2026-10-29)
        var frame = Path(ellipseIn: CGRect(x: c.x - R * 1.6, y: c.y - R * 1.6, width: R * 3.2, height: R * 3.2))
        frame.addPath(poly(nowR, c))
        var web = ctx
        web.clip(to: frame, style: FillStyle(eoFill: true))
        for f in [0.25, 0.5, 0.75] as [CGFloat] {
            let r = r0 + 8 + (R - r0 - 8) * f
            web.stroke(poly(Array(repeating: r, count: n), c), with: .color(C.creme.opacity(0.1)),
                       style: StrokeStyle(lineWidth: 1.3, dash: [3, 4]))
        }
        if !plate {   // without the plate, a faint outer ring keeps the scale readable
            web.stroke(outer, with: .color(C.creme.opacity(0.1)), style: StrokeStyle(lineWidth: 1.3, dash: [3, 4]))
        }
        for i in 0..<n {
            var s = Path()
            s.move(to: point(i, r0, c))
            s.addLine(to: point(i, R, c))
            let on = focus.wrappedValue == STATS[i]
            (on ? ctx : web).stroke(s, with: .color(on ? C.brand.opacity(0.9) : C.creme.opacity(0.08)), lineWidth: on ? 2.5 : 1.3)
        }

        // START: the onboarding shape, dashed (only worth showing once training moved it)
        if grew {
            ctx.stroke(poly(startR, c), with: .color(C.creme.opacity(0.55)),
                       style: StrokeStyle(lineWidth: 2, lineJoin: .round, dash: [5, 5]))
        }
        // NOW: the green web, with a sunk shadow so it sits on the plate
        let now = poly(nowR, c)
        ctx.drawLayer { l in
            l.translateBy(x: 0, y: 4)
            l.fill(now, with: .color(C.charInk.opacity(0.45)))
        }
        ctx.fill(now, with: .radialGradient(Gradient(colors: [C.brand.opacity(0.15), C.brand.opacity(0.5)]),
                                            center: c, startRadius: r0, endRadius: R))
        ctx.stroke(now, with: .color(C.brandInk), style: StrokeStyle(lineWidth: 6.5, lineJoin: .round))
        ctx.stroke(now, with: .color(C.brand), style: StrokeStyle(lineWidth: 3.5, lineJoin: .round))
        // the green growth on each spoke (START ? NOW)
        if grew {
            for i in 0..<n where nowR[i] > startR[i] + 1 {
                var s = Path()
                s.move(to: point(i, startR[i], c))
                s.addLine(to: point(i, nowR[i], c))
                ctx.stroke(s, with: .color(C.brandHi), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
        // studs on the corners
        for i in 0..<n {
            let p = point(i, nowR[i], c)
            let on = focus.wrappedValue == STATS[i]
            let d: CGFloat = on ? 15 : 11
            let rect = CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d)
            ctx.fill(Path(ellipseIn: rect.offsetBy(dx: 0, dy: 2)), with: .color(C.charInk))
            ctx.fill(Path(ellipseIn: rect), with: .color(on ? C.brandHi : C.creme))
            ctx.stroke(Path(ellipseIn: rect), with: .color(C.brandInk), lineWidth: 2.2)
        }
    }

    @ViewBuilder private func badge(_ d: CGFloat) -> some View {
        ZStack {
            switch center {
            case .photo(let img):
                Image(uiImage: img).resizable().scaledToFill()
            case .name(let n):
                LinearGradient(colors: [C.brandHi, C.brand, C.brandMid], startPoint: .top, endPoint: .bottom)
                Circle().inset(by: d * 0.07).stroke(C.creme.opacity(0.45), style: StrokeStyle(lineWidth: 1.4, dash: [3, 3]))
                Text(n.uppercased())
                    .font(F.display(d * 0.24)).foregroundStyle(.white)
                    .shadow(color: C.brandInk, radius: 0, y: 2)
                    .lineLimit(1).minimumScaleFactor(0.4)
                    .padding(.horizontal, d * 0.13)
            }
        }
        .frame(width: d, height: d)
        .clipShape(Circle())
        .overlay(Circle().stroke(C.charInk, lineWidth: 3))
        .overlay(Circle().inset(by: -5).stroke(C.brand.opacity(0.5), lineWidth: 2))
        .background(Circle().fill(C.charInk).offset(y: 4))
    }

    private func label(_ k: String) -> some View {
        let on = focus.wrappedValue == k
        let g = stats.gain[k] ?? 0
        return Button {
            Haptics.play(.stud)
            withAnimation(.snappy) { focus.wrappedValue = on ? nil : k }
        } label: {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Disp("\(stats.now[k] ?? 0)", size: 25, color: on ? C.brand : C.creme)
                    if g > 0 {
                        Text("+\(g)").font(F.round(13, .bold)).foregroundStyle(C.brand)
                    }
                }
                Text(SpiderGraph.short[k] ?? k).font(F.round(12, .bold)).kerning(0.6)
                    .foregroundStyle(on ? C.creme : C.muted)
            }
            .fixedSize()
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? C.char700 : .clear))
            .scaleEffect(on ? 1.08 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(STAT_NAME[k] ?? k) \(stats.now[k] ?? 0)")
    }

    static let short = ["SHO": "SHOOTING", "PAS": "PASSING", "DRI": "DRIBBLING", "DEF": "DEFENDING", "PHY": "PHYSICAL", "BC": "TOUCH"]
}
