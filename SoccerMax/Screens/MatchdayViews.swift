// MATCHDAY tab (notes/22): real games, pulled daily from API-Football, each one a native MATCH FILM.
// 2026-10-26 v2 ? SIMPLE: ONE hero, a RANDOM button with club + league crests drifting round it (drag to spin them,
// poke them, they wobble), then one plain row per film: crests, club names, length. No other text.
import SwiftUI

struct MatchdayTab: View {
    @State private var md = Matchday.shared
    @Environment(AppStore.self) private var store
    @State private var playing: Film?
    @State private var sharing: ShareTarget?
    private struct ShareTarget: Identifiable { let tape: MatchTape; var id: Int { tape.id } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    TabHeader("MATCHDAY")

                    RandomHero(tapes: md.tapes) {
                        // a film you haven't seen yet when there is one
                        let fresh = md.tapes.filter { !md.watched.contains($0.id) }
                        if let t = (fresh.isEmpty ? md.tapes : fresh).randomElement() { playing = Film(tape: t) }
                    }
                    .padding(.top, 6)

                    if !md.status.isEmpty {
                        ProgressView().tint(C.brand).frame(maxWidth: .infinity).padding(.top, 8)
                    }

                    VStack(spacing: 10) {
                        ForEach(md.tapes) { t in
                            Button { playing = Film(tape: t) } label: { TapeRow(tape: t, minutes: FilmPlan.minutes(t, store.answers)) }
                                .buttonStyle(.press)
                                .contextMenu { Button("Share", systemImage: "square.and.arrow.up") { sharing = ShareTarget(tape: t) } }
                        }
                    }
                    .padding(.top, 14).padding(.bottom, 30)
                }
                .padding(.horizontal, 16)
            }
            .refreshable { await md.refresh(force: true) }
            .tabRoot("Matchday")
            .page()
        }
        .task { await md.refresh() }
        .fullScreenCover(item: $playing) { TapePlayer(tape: $0.tape, start: $0.start) }
        // the match-of-the-day widget opens its film straight away
        .onChange(of: Nav.shared.tape, initial: true) { _, id in
            if let id, let t = md.tape(id) { playing = Film(tape: t) }
            if id != nil { Nav.shared.tape = nil }
        }
        .sheet(item: $sharing) { ShareSheet(item: .film($0.tape)) }
        .onAppear {
            // ./sim.sh tape:<fixtureId>[:<lesson>]
            if DebugRoute.parts.first == "tape" {
                let start = DebugRoute.parts[safe: 2].flatMap { Int($0) } ?? 0
                if let t = DebugRoute.parts[safe: 1].flatMap({ Int($0) }).flatMap(md.tape) ?? md.hero { playing = Film(tape: t, start: start) }
            }
        }
    }
}

/// A film to open (and the lesson to open it on ? debug routes jump straight in).
struct Film: Identifiable {
    let tape: MatchTape
    var start = 0
    var id: Int { tape.id }
}

// MARK: - the hero: RANDOM + a loose orbit of crests

/// The big green RANDOM ball in the middle; crests of tonight's clubs + famous clubs and leagues drift round it on
/// uneven rings (each its own radius, speed, bob). Drag anywhere to fling the whole orbit, crests near your finger
/// get shoved aside and spring back, tap one and it pops.
private struct RandomHero: View {
    let tapes: [MatchTape]
    let play: () -> Void
    @State private var orbit = LogoOrbit()
    @State private var dragLast: CGPoint?
    @State private var dragStart: CGPoint?

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                TimelineView(.animation) { tl in
                    Canvas { ctx, s in
                        orbit.step(tl.date, size: s)
                        orbit.draw(&ctx, size: s)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            if dragStart == nil { dragStart = g.location }
                            orbit.drag(from: dragLast ?? g.location, to: g.location, size: size)
                            dragLast = g.location
                        }
                        .onEnded { g in
                            if let s = dragStart, hypot(g.location.x - s.x, g.location.y - s.y) < 8 { orbit.tap(g.location, size: size) }
                            orbit.release()
                            dragLast = nil; dragStart = nil
                        }
                )

                Button(action: play) { RandomBall() }
                    .buttonStyle(.press(.kick))
                    .disabled(tapes.isEmpty)
                    .opacity(tapes.isEmpty ? 0.5 : 1)
                    .accessibilityLabel("Play a random film")
            }
        }
        .frame(height: 340)
        .onAppear { orbit.load(urls: Self.urls(tapes)) }
        .onChange(of: tapes.map(\.id)) { orbit.load(urls: Self.urls(tapes)) }
    }

    /// A few of tonight's crests, then the big leagues and clubs ? no repeats, 20 in all.
    static func urls(_ tapes: [MatchTape]) -> [String] {
        let api = "https://media.api-sports.io/football/"
        let clubs = [541, 529, 33, 40, 50, 42, 157, 85, 496, 505, 489, 49, 165, 47, 530, 492]   // Real, Barça, United, Liverpool, City, Arsenal, Bayern, PSG, Juve, Inter, Milan, Chelsea, Dortmund, Spurs, Atlético, Napoli
        let leagues = [2, 39, 140, 135, 78, 61, 253]                                            // UCL, PL, La Liga, Serie A, Bundesliga, Ligue 1, MLS
        var out: [String] = []
        let tonight = Array(Set(tapes.flatMap { [$0.home.logo, $0.away.logo] })).sorted().prefix(6)   // a few of tonight's, the rest famous
        for u in Array(tonight) + leagues.map({ "\(api)leagues/\($0).png" }) + clubs.map({ "\(api)teams/\($0).png" })
        where !out.contains(u) && out.count < 20 { out.append(u) }
        return out
    }
}

/// The RANDOM button: a fat grass disc with a dark lip, shuffle mark + word.
private struct RandomBall: View {
    var body: some View {
        ZStack {
            Circle().fill(C.brandLip).offset(y: 7)
            Circle().fill(LinearGradient(colors: [C.brandHi, C.brand, C.brandMid], startPoint: .top, endPoint: .bottom))
                .overlay(Circle().stroke(C.charInk, lineWidth: 3))
            VStack(spacing: 2) {
                Image(systemName: "shuffle").font(.system(size: 30, weight: .black)).foregroundStyle(C.brandInk)
                Disp("RANDOM", size: 26)
            }
        }
        .frame(width: 136, height: 136)
    }
}

/// The orbit's state, stepped once a frame from the Canvas (a plain class on purpose: it changes every frame and the
/// TimelineView already redraws, so nothing needs to observe it).
@MainActor
private final class LogoOrbit {
    struct Item {
        let url: String
        var img: Image?
        let ring: CGFloat       // 0?1 of the orbit radius
        let speed: Double       // × the base turn
        var angle: Double
        let bob: (amp: CGFloat, freq: Double, phase: Double)
        let size: CGFloat
        var push = CGVector.zero, pushV = CGVector.zero
        var pop = 0.0           // 1 ? 0 after a tap
        var at = CGPoint.zero, scale: CGFloat = 1, depth: Double = 0
    }
    private(set) var items: [Item] = []
    private var spin = 0.0          // extra turn speed from a fling (rad/s)
    private var finger: CGPoint?
    private var last: Date?
    private var t = 0.0
    private var loaded: [String] = []

    func load(urls: [String]) {
        guard urls != loaded else { return }
        loaded = urls
        var rng = SystemRandomNumberGenerator()
        let old = Dictionary(items.map { ($0.url, $0.img) }, uniquingKeysWith: { a, _ in a })
        items = urls.enumerated().map { i, u in
            let ring = [0.7, 0.86, 1.0][i % 3] + CGFloat.random(in: -0.07...0.07, using: &rng)
            return Item(url: u, img: old[u] ?? RemoteImages.cached(u).map { Image(uiImage: $0) }, ring: ring,
                        speed: (ring < 0.78 ? 1.3 : ring < 0.93 ? 1.0 : 0.72) * Double.random(in: 0.85...1.15, using: &rng),
                        angle: Double(i) * 2.399 + Double.random(in: -0.3...0.3, using: &rng),   // golden angle ? no clumps
                        bob: (CGFloat.random(in: 3...9, using: &rng), Double.random(in: 0.6...1.4, using: &rng), Double.random(in: 0...6.28, using: &rng)),
                        size: CGFloat.random(in: 40...52, using: &rng))
        }
        for u in urls where old[u] == nil && RemoteImages.cached(u) == nil {
            Task {
                guard let ui = await RemoteImages.load(u) else { return }
                if let k = items.firstIndex(where: { $0.url == u }) { items[k].img = Image(uiImage: ui) }
            }
        }
    }

    func step(_ now: Date, size: CGSize) {
        let dt = min(1 / 20, last.map { now.timeIntervalSince($0) } ?? 0)
        last = now; t += dt
        spin *= exp(-dt * 1.4)
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let rx = size.width / 2 - 30, ry = size.height / 2 - 44
        let tilt = -0.14                                     // the orbit leans a little ? not a perfect ring
        for i in items.indices {
            var it = items[i]
            it.angle += (0.28 * it.speed + spin * (1.25 - Double(it.ring) * 0.4)) * dt
            // spring back from any shove
            var f = CGVector(dx: -60 * it.push.dx - 9 * it.pushV.dx, dy: -60 * it.push.dy - 9 * it.pushV.dy)
            if let p = finger {
                let dx = it.at.x - p.x, dy = it.at.y - p.y, d = max(1, hypot(dx, dy))
                if d < 90 { let k = (90 - d) * 40 / d; f.dx += dx * k; f.dy += dy * k }
            }
            it.pushV.dx += f.dx * dt; it.pushV.dy += f.dy * dt
            it.push.dx += it.pushV.dx * dt; it.push.dy += it.pushV.dy * dt
            it.pop = max(0, it.pop - dt * 2.2)
            let ex = cos(it.angle) * rx * it.ring, ey = sin(it.angle) * ry * it.ring
            let bob = it.bob.amp * sin(t * it.bob.freq + it.bob.phase)
            // split up: as one expression it can time out the type-checker on a busy Mac
            let ct: CGFloat = cos(tilt), st: CGFloat = sin(tilt)
            let ax: CGFloat = c.x + ex * ct - ey * st
            let ay: CGFloat = c.y + ex * st + ey * ct
            it.at = CGPoint(x: ax + it.push.dx, y: ay + bob + it.push.dy)
            it.depth = sin(it.angle)                          // +1 = front (low on screen), ?1 = back
            it.scale = 0.7 + 0.3 * CGFloat((it.depth + 1) / 2) + CGFloat(sin(it.pop * .pi) * 0.45)
            items[i] = it
        }
    }

    func draw(_ ctx: inout GraphicsContext, size: CGSize) {
        for it in items.sorted(by: { $0.depth < $1.depth }) {
            let s = it.size * it.scale, r = CGRect(x: it.at.x - s / 2, y: it.at.y - s / 2, width: s, height: s)
            var g = ctx
            g.opacity = 0.45 + 0.55 * (it.depth + 1) / 2
            g.fill(Path(ellipseIn: r.offsetBy(dx: 0, dy: 3)), with: .color(C.charInk))
            g.fill(Path(ellipseIn: r), with: .color(C.creme))
            g.stroke(Path(ellipseIn: r), with: .color(C.charInk), lineWidth: 2)
            if let img = it.img { g.draw(img, in: r.insetBy(dx: s * 0.16, dy: s * 0.16)) }
        }
    }

    /// A drag turns the orbit by how far the finger swept round the middle; crests near it get shoved.
    func drag(from a: CGPoint, to b: CGPoint, size: CGSize) {
        finger = b
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        var d = atan2(b.y - c.y, b.x - c.x) - atan2(a.y - c.y, a.x - c.x)
        if d > .pi { d -= 2 * .pi } else if d < -.pi { d += 2 * .pi }
        spin = max(-9, min(9, spin * 0.6 + d * 22))
    }

    func release() { finger = nil }

    func tap(_ p: CGPoint, size: CGSize) {
        guard let k = items.indices.filter({ hypot(items[$0].at.x - p.x, items[$0].at.y - p.y) < items[$0].size * items[$0].scale / 2 + 8 })
            .max(by: { items[$0].depth < items[$1].depth }) else { return }
        items[k].pop = 1
        items[k].pushV = CGVector(dx: .random(in: -160...160), dy: -220)
        Haptics.play(.pop)
    }
}

// MARK: - a film row: crests, clubs, length

private struct TapeRow: View {
    let tape: MatchTape
    let minutes: Int
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: -6) {
                CrestImage(url: tape.home.logo, size: 34)
                CrestImage(url: tape.away.logo, size: 34)
            }
            .frame(width: 70, height: 46)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0x0B0D0F)))
            Text("\(tape.home.name) v \(tape.away.name)").font(F.round(16, .bold)).foregroundStyle(C.creme)
                .lineLimit(2).minimumScaleFactor(0.75)
            Spacer(minLength: 4)
            Text("\(minutes) MIN").font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundStyle(C.brand)
                .accessibilityLabel("\(minutes) minute\(minutes == 1 ? "" : "s")")
        }
        .gameCard(padding: 10, radius: 18)
    }
}
