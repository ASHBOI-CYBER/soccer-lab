// The coach's board (2026-10-27, notes/25 "Video or board"; animated since 2026-11-16). Drills are drawn from ABOVE
// on a mown pitch: disc cones, ladders, hurdles, goals, the ball and you. On the drill page it PLAYS the drill: you
// run each dashed line in order (with the ball at your feet when it starts there), the ball rolls along each solid
// line (passes, shots), the line draws itself as you go, then it loops. Drills with no lines (toe taps, rolls) show
// the ball tapping side to side. Thumbnails stay still (the whole diagram), and so does Reduce Motion.
// Data = `board` in library.json (content/make_library.py).
import SwiftUI

struct Board: Codable, Hashable {
    struct Prop: Codable, Hashable {
        let k: String; let x: Double; let z: Double; let yaw: Double; let rungs: Int?
        /// A cone's colour when the drill calls colours ("red", "blue", "yellow", "green"); nil = training orange.
        let c: String?
        /// A wall's width in metres (centred on x).
        let w: Double?
    }
    struct Man: Codable, Hashable { let kit: String; let x: Double; let z: Double; let yaw: Double }
    struct Path: Codable, Hashable { let pts: [[Double]]; let ball: Bool?; let both: Bool? }
    let side: Bool?
    let props: [Prop]
    let players: [Man]
    let balls: [[Double]]
    let paths: [Path]
}

struct DrillBoard: View {
    let board: Board
    /// Play the drill (the drill page). Off for thumbnails.
    var animated = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let script = BoardScript(board)
        let live = animated && !reduceMotion && board.side != true
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !live)) { tl in
            Canvas { ctx, size in
                BoardPainter.grass(&ctx, size)
                if board.side == true {
                    BoardPainter.side(&ctx, size)
                } else {
                    let t = live ? tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: script.cycle) : nil
                    BoardPainter(board: board, script: script, size: size).draw(&ctx, at: t)
                }
            }
        }
        .accessibilityLabel("Diagram of the drill")
    }
}

// MARK: - the script: who moves where, when

/// The drill as a timeline: each line of the board in order, how long it takes, and whether the ball goes along.
struct BoardScript {
    struct Leg {
        let pts: [CGPoint]       // world metres (x right, y = z down the screen)
        let ball: Bool           // the ball travels this line (a pass or a shot)
        let dribble: Bool        // you run it with the ball at your feet
        let start: Double
        let dur: Double
        let length: Double
        let index: Int           // which board path (for its number)
    }
    let legs: [Leg]
    let cycle: Double
    let youStart: CGPoint
    let youYaw: Double
    /// The ball you use (the one nearest your start), if any.
    let ballIndex: Int?

    static let intro = 0.7, gap = 0.35, hold = 1.3

    init(_ b: Board) {
        let you = b.players.first.map { CGPoint(x: $0.x, y: $0.z) } ?? .zero
        youStart = you
        youYaw = b.players.first?.yaw ?? .pi
        let balls = b.balls.map { CGPoint(x: $0[0], y: $0[1]) }
        ballIndex = balls.indices.min { Self.dist(balls[$0], you) < Self.dist(balls[$1], you) }
        var ball = ballIndex.map { balls[$0] }
        var me = you
        var t = Self.intro
        var out: [Leg] = []
        for (i, p) in b.paths.enumerated() {
            var pts = p.pts.map { CGPoint(x: $0[0], y: $0[1]) }
            guard pts.count > 1 else { continue }
            if p.both == true { pts += pts.dropLast().reversed() }
            let len = Self.length(pts)
            if p.ball == true {
                let dur = max(0.6, min(2.2, len / 7.5))
                out.append(Leg(pts: pts, ball: true, dribble: false, start: t, dur: dur, length: len, index: i))
                ball = pts.last
                t += dur + Self.gap
            } else {
                // the ball goes with you when it's at your feet where this run starts
                let carry = ball.map { Self.dist($0, pts[0]) < 1.3 || Self.dist($0, me) < 1.0 } ?? false
                let dur = max(0.8, min(6, len / (carry ? 2.4 : 3.4)))
                out.append(Leg(pts: pts, ball: false, dribble: carry, start: t, dur: dur, length: len, index: i))
                me = pts.last ?? me
                if carry { ball = pts.last }
                t += dur + Self.gap
            }
        }
        legs = out
        cycle = out.isEmpty ? 2.4 : t + Self.hold
    }

    static func dist(_ a: CGPoint, _ b: CGPoint) -> Double { hypot(a.x - b.x, a.y - b.y) }
    static func length(_ p: [CGPoint]) -> Double { zip(p, p.dropFirst()).reduce(0) { $0 + dist($1.0, $1.1) } }

    /// The point `f` (0...1) of the way along a line, and the direction it's heading.
    static func along(_ p: [CGPoint], _ f: Double) -> (CGPoint, CGVector) {
        let total = length(p)
        var left = max(0, min(1, f)) * total
        for (a, b) in zip(p, p.dropFirst()) {
            let d = dist(a, b)
            if left <= d || b == p.last {
                let k = d > 0 ? min(1, left / d) : 0
                return (CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k), CGVector(dx: b.x - a.x, dy: b.y - a.y))
            }
            left -= d
        }
        return (p.last ?? .zero, CGVector(dx: 0, dy: -1))
    }

    /// The line up to `f` of the way along.
    static func partial(_ p: [CGPoint], _ f: Double) -> [CGPoint] {
        let total = length(p)
        var left = max(0, min(1, f)) * total
        var out = [p[0]]
        for (a, b) in zip(p, p.dropFirst()) {
            let d = dist(a, b)
            if left >= d { out.append(b); left -= d } else {
                let k = d > 0 ? left / d : 0
                out.append(CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k))
                break
            }
        }
        return out
    }

    static func ease(_ x: Double) -> Double { x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2 }
}

// MARK: - drawing

struct BoardPainter {
    let board: Board
    let script: BoardScript
    let size: CGSize
    private let u: CGFloat
    private let fit: (cx: Double, cz: Double, s: Double)

    init(board: Board, script: BoardScript, size: CGSize) {
        self.board = board
        self.script = script
        self.size = size
        let u = max(min(size.width, size.height) / 300, 0.42)
        self.u = u
        fit = Self.fit(board, size, u)
    }

    // fit everything (min span so a one-ball drill isn't blown up)
    private static func fit(_ board: Board, _ size: CGSize, _ u: CGFloat) -> (cx: Double, cz: Double, s: Double) {
        var xs: [Double] = [], zs: [Double] = []
        for p in board.props {
            xs.append(p.x); zs.append(p.z)
            if p.k == "ladder" { xs.append(p.x + Double(p.rungs ?? 4) * 0.45) }
            if p.k == "goal" { xs += [p.x - 3.66, p.x + 3.66]; zs.append(p.z - 1.2) }
            if p.k == "wall" { let h = (p.w ?? 4) / 2; xs += [p.x - h, p.x + h]; zs.append(p.z - 0.4) }
        }
        for m in board.players { xs.append(m.x); zs.append(m.z) }
        for b in board.balls { xs.append(b[0]); zs.append(b[1]) }
        for path in board.paths { for q in path.pts { xs.append(q[0]); zs.append(q[1]) } }
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 0, minZ = zs.min() ?? 0, maxZ = zs.max() ?? 0
        let w = max(maxX - minX, 1.3), h = max(maxZ - minZ, 1.3)
        let pad = 26 * u + 10
        let s = min((size.width - 2 * pad) / w, (size.height - 2 * pad) / h)
        return ((minX + maxX) / 2, (minZ + maxZ) / 2, s)
    }

    private func pt(_ p: CGPoint) -> CGPoint {
        CGPoint(x: size.width / 2 + (p.x - fit.cx) * fit.s, y: size.height / 2 + (p.y - fit.cz) * fit.s)
    }
    private func pt(_ x: Double, _ z: Double) -> CGPoint { pt(CGPoint(x: x, y: z)) }

    /// t = seconds into the loop; nil = the still diagram (every line drawn, everyone at the start).
    func draw(_ ctx: inout GraphicsContext, at t: Double?) {
        // props
        for p in board.props { prop(&ctx, p) }

        // lines: still = all of them; live = faint ahead, bright behind
        let numbered = board.paths.count > 1
        let fadeOut = t.map { max(0, min(1, (script.cycle - $0) / 0.45)) } ?? 1
        for leg in script.legs {
            let pts = leg.pts.map(pt)
            guard let t else { line(&ctx, pts, ball: leg.ball, alpha: 1, head: true); continue }
            line(&ctx, pts, ball: leg.ball, alpha: 0.22, head: false, ghost: true)
            if t >= leg.start {
                let f = BoardScript.ease(min(1, (t - leg.start) / leg.dur))
                line(&ctx, BoardScript.partial(leg.pts, f).map(pt), ball: leg.ball, alpha: 0.95 * fadeOut, head: f >= 1)
            }
        }

        // where you and the ball are now
        var you = script.youStart
        var facing = CGVector(dx: sin(script.youYaw), dy: cos(script.youYaw))
        var ball = script.ballIndex.map { CGPoint(x: board.balls[$0][0], y: board.balls[$0][1]) }
        var rolled = 0.0
        var moving = false
        if let t {
            for leg in script.legs {
                guard t >= leg.start else { break }
                let f = BoardScript.ease(min(1, (t - leg.start) / leg.dur))
                let (p, dir) = BoardScript.along(leg.pts, f)
                if leg.ball {
                    ball = p
                    rolled += leg.length * f
                } else {
                    you = p
                    if hypot(dir.dx, dir.dy) > 0.001 { facing = dir }
                    if leg.dribble {
                        let n = max(0.001, hypot(facing.dx, facing.dy))
                        ball = CGPoint(x: p.x + facing.dx / n * 0.42, y: p.y + facing.dy / n * 0.42)
                        rolled += leg.length * f
                    }
                }
                if t < leg.start + leg.dur { moving = true }
            }
        }
        // no lines to follow: the ball taps side to side at your feet
        var tap: Double?
        if let t, script.legs.isEmpty, let b = ball {
            let beat = t / 0.55
            let side = Int(beat) % 2 == 0 ? 1.0 : -1.0
            let k = sin((beat - floor(beat)) * .pi)
            ball = CGPoint(x: b.x + side * 0.22 * k, y: b.y)
            rolled = beat * 0.5
            tap = beat - floor(beat)
        }

        // other players, then you, then the ball (on top)
        for (i, m) in board.players.enumerated() where i > 0 {
            player(&ctx, at: pt(m.x, m.z), facing: CGVector(dx: sin(m.yaw), dy: cos(m.yaw)), kit: m.kit, me: false)
        }
        if !board.players.isEmpty { player(&ctx, at: pt(you), facing: facing, kit: "you", me: true, bob: moving ? (t ?? 0) : nil) }
        for (i, b) in board.balls.enumerated() where i != script.ballIndex { self.ball(&ctx, at: pt(b[0], b[1]), spin: 0) }
        if let ball {
            if let tap, tap < 0.5 { ripple(&ctx, at: pt(ball), k: tap / 0.5) }
            self.ball(&ctx, at: pt(ball), spin: rolled * 2.2)
        }
        // step numbers last, so the player never hides number 1
        if numbered {
            for leg in script.legs { badge(&ctx, "\(leg.index + 1)", at: pt(leg.pts[0]), lit: t.map { $0 >= leg.start && $0 < leg.start + leg.dur } ?? false) }
        }
    }

    // MARK: pieces

    private static func coneColor(_ c: String?) -> Color {
        switch c {
        case "red": return Color(hex: 0xE5484D)
        case "blue": return Color(hex: 0x2F7BFF)
        case "yellow": return Color(hex: 0xF5C542)
        case "green": return Color(hex: 0x2BB673)
        default: return Color(hex: 0xFF8A1F)
        }
    }

    private func prop(_ ctx: inout GraphicsContext, _ p: Board.Prop) {
        let c = pt(p.x, p.z)
        switch p.k {
        case "ladder":
            let rungs = p.rungs ?? 4
            let a = pt(p.x, p.z - 0.25), b = pt(p.x + Double(rungs) * 0.45, p.z + 0.25)
            let r = CGRect(x: a.x, y: a.y, width: b.x - a.x, height: max(b.y - a.y, 14 * u))
            let yellow = Color(hex: 0xF5C542)
            ctx.stroke(Path(r.offsetBy(dx: 1.5 * u, dy: 2 * u)), with: .color(.black.opacity(0.25)), lineWidth: 3 * u)
            for i in 1..<rungs {
                let x = r.minX + r.width * CGFloat(i) / CGFloat(rungs)
                var l = Path(); l.move(to: CGPoint(x: x, y: r.minY)); l.addLine(to: CGPoint(x: x, y: r.maxY))
                ctx.stroke(l, with: .color(yellow.opacity(0.9)), lineWidth: 2.2 * u)
            }
            var rails = Path()
            rails.move(to: CGPoint(x: r.minX, y: r.minY)); rails.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            rails.move(to: CGPoint(x: r.minX, y: r.maxY)); rails.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            ctx.stroke(rails, with: .color(yellow), style: StrokeStyle(lineWidth: 3 * u, lineCap: .round))
        case "hurdle":
            // the bar lies across the run: yaw 1.57 = along z
            let dx = cos(p.yaw), dz = -sin(p.yaw), half = 10 * u
            let a = CGPoint(x: c.x - dx * half, y: c.y - dz * half), b = CGPoint(x: c.x + dx * half, y: c.y + dz * half)
            var shadow = Path(); shadow.move(to: a); shadow.addLine(to: b)
            ctx.stroke(shadow.applying(CGAffineTransform(translationX: 2 * u, y: 3 * u)), with: .color(.black.opacity(0.25)), style: StrokeStyle(lineWidth: 5 * u, lineCap: .round))
            var bar = Path(); bar.move(to: a); bar.addLine(to: b)
            ctx.stroke(bar, with: .color(Color(hex: 0xFF8A1F)), style: StrokeStyle(lineWidth: 4.5 * u, lineCap: .round))
            for e in [a, b] { ctx.fill(Path(ellipseIn: CGRect(x: e.x - 3 * u, y: e.y - 3 * u, width: 6 * u, height: 6 * u)), with: .color(.white)) }
        case "wall":
            // a brick wall seen from above, with its shadow on the grass
            let h = (p.w ?? 4) / 2
            let a = pt(p.x - h, p.z - 0.32), b = pt(p.x + h, p.z)
            let r = CGRect(x: a.x, y: a.y, width: b.x - a.x, height: max(b.y - a.y, 9 * u))
            ctx.fill(Path(r.offsetBy(dx: 0, dy: 4 * u)), with: .color(.black.opacity(0.3)))
            ctx.fill(Path(r), with: .linearGradient(Gradient(colors: [Color(hex: 0xC9B79C), Color(hex: 0xA8957A)]),
                                                     startPoint: CGPoint(x: r.midX, y: r.minY), endPoint: CGPoint(x: r.midX, y: r.maxY)))
            var bricks = Path()
            let rows = 2, bw = 12 * u
            for row in 0..<rows {
                let y0 = r.minY + r.height * CGFloat(row) / CGFloat(rows), y1 = r.minY + r.height * CGFloat(row + 1) / CGFloat(rows)
                if row > 0 { bricks.move(to: CGPoint(x: r.minX, y: y0)); bricks.addLine(to: CGPoint(x: r.maxX, y: y0)) }
                var x = r.minX + (row % 2 == 0 ? bw : bw / 2)
                while x < r.maxX { bricks.move(to: CGPoint(x: x, y: y0)); bricks.addLine(to: CGPoint(x: x, y: y1)); x += bw }
            }
            ctx.stroke(bricks, with: .color(.black.opacity(0.18)), lineWidth: 0.8 * u)
            ctx.stroke(Path(r), with: .color(.black.opacity(0.35)), lineWidth: 1 * u)
            ctx.stroke(Path(CGRect(x: r.minX, y: r.minY, width: r.width, height: 1.2 * u)), with: .color(.white.opacity(0.35)), lineWidth: 1 * u)
        case "goal":
            let a = pt(p.x - 3.66, p.z), b = pt(p.x + 3.66, p.z - 1.0)
            let net = CGRect(x: a.x, y: b.y, width: b.x - a.x, height: a.y - b.y)
            ctx.fill(Path(net), with: .color(.white.opacity(0.10)))
            var mesh = Path()
            var x = net.minX
            while x < net.maxX { mesh.move(to: CGPoint(x: x, y: net.minY)); mesh.addLine(to: CGPoint(x: x, y: net.maxY)); x += 5 * u }
            var y = net.minY
            while y < net.maxY { mesh.move(to: CGPoint(x: net.minX, y: y)); mesh.addLine(to: CGPoint(x: net.maxX, y: y)); y += 5 * u }
            ctx.stroke(mesh, with: .color(.white.opacity(0.18)), lineWidth: 0.6 * u)
            var line = Path(); line.move(to: CGPoint(x: 0, y: net.maxY)); line.addLine(to: CGPoint(x: size.width, y: net.maxY))
            ctx.stroke(line, with: .color(.white.opacity(0.5)), lineWidth: 2 * u)
            var frame = Path()
            frame.move(to: CGPoint(x: net.minX, y: net.maxY)); frame.addLine(to: CGPoint(x: net.minX, y: net.minY))
            frame.addLine(to: CGPoint(x: net.maxX, y: net.minY)); frame.addLine(to: CGPoint(x: net.maxX, y: net.maxY))
            ctx.stroke(frame, with: .color(.white.opacity(0.55)), lineWidth: 1.5 * u)
            for px in [net.minX, net.maxX] {
                ctx.fill(Path(ellipseIn: CGRect(x: px - 3.5 * u, y: net.maxY - 3.5 * u, width: 7 * u, height: 7 * u)), with: .color(.white))
            }
            var bar = Path(); bar.move(to: CGPoint(x: net.minX, y: net.maxY)); bar.addLine(to: CGPoint(x: net.maxX, y: net.maxY))
            ctx.stroke(bar, with: .color(.white), lineWidth: 3 * u)
        default:   // a disc cone seen from above
            let r = 7.5 * u
            let col = Self.coneColor(p.c)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r + 1.5 * u, y: c.y - r + 2.5 * u, width: 2 * r, height: 2 * r)), with: .color(.black.opacity(0.28)))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(col))
            let ri = r * 0.58
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - ri, y: c.y - ri, width: 2 * ri, height: 2 * ri)), with: .color(.white.opacity(0.22)))
            let rh = r * 0.26
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - rh, y: c.y - rh, width: 2 * rh, height: 2 * rh)), with: .color(.black.opacity(0.35)))
            var shine = Path()
            shine.addArc(center: c, radius: r * 0.8, startAngle: .degrees(200), endAngle: .degrees(260), clockwise: false)
            ctx.stroke(shine, with: .color(.white.opacity(0.55)), style: StrokeStyle(lineWidth: 1.4 * u, lineCap: .round))
        }
    }

    /// A line: dashed blue = you run, solid white = the ball travels. `ghost` = the faint guide ahead of you.
    private func line(_ ctx: inout GraphicsContext, _ pts: [CGPoint], ball: Bool, alpha: Double, head: Bool, ghost: Bool = false) {
        guard pts.count > 1, alpha > 0.01 else { return }
        var p = Path()
        p.move(to: pts[0])
        for q in pts.dropFirst() { p.addLine(to: q) }
        let color: Color = ghost ? .white : ball ? .white : C.brandHi
        let width = (ghost ? 2 : ball ? 3.4 : 3.2) * u
        let dash: [CGFloat] = ball ? [] : [7 * u, 6 * u]
        if !ghost {
            ctx.stroke(p, with: .color((ball ? Color.white : C.brand).opacity(0.28 * alpha)),
                       style: StrokeStyle(lineWidth: width + 5 * u, lineCap: .round, lineJoin: .round, dash: dash))
        }
        ctx.stroke(p, with: .color(color.opacity(alpha)), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: dash))
        if head, let last = pts.last { arrowHead(&ctx, from: pts[pts.count - 2], to: last, color: color.opacity(alpha)) }
    }

    private func arrowHead(_ ctx: inout GraphicsContext, from a: CGPoint, to b: CGPoint, color: Color) {
        let ang = atan2(b.y - a.y, b.x - a.x), l = 11 * u, w = 0.5
        var h = Path()
        h.move(to: b)
        h.addLine(to: CGPoint(x: b.x - l * cos(ang - w), y: b.y - l * sin(ang - w)))
        h.addLine(to: CGPoint(x: b.x - l * cos(ang + w), y: b.y - l * sin(ang + w)))
        h.closeSubpath()
        ctx.fill(h, with: .color(color))
    }

    private func badge(_ ctx: inout GraphicsContext, _ s: String, at c: CGPoint, lit: Bool) {
        let r = (lit ? 9.5 : 8) * u
        let at = CGPoint(x: c.x - 19 * u, y: c.y - 17 * u)
        let e = Path(ellipseIn: CGRect(x: at.x - r, y: at.y - r, width: 2 * r, height: 2 * r))
        ctx.fill(e, with: .color(lit ? C.brand : Color.black.opacity(0.55)))
        ctx.stroke(e, with: .color(.white.opacity(lit ? 0.9 : 0.5)), lineWidth: 1.2 * u)
        ctx.draw(Text(s).font(.system(size: 10 * u, weight: .black, design: .rounded)).foregroundColor(.white), at: at)
    }

    /// A player from above: shadow, shoulders in the kit colour, head, and a chevron where they face.
    private func player(_ ctx: inout GraphicsContext, at c: CGPoint, facing: CGVector, kit: String, me: Bool, bob: Double? = nil) {
        let r = 11.5 * u * (1 + (bob.map { 0.04 * sin($0 * 14) } ?? 0))
        let n = max(0.001, hypot(facing.dx, facing.dy))
        let fx = facing.dx / n, fy = facing.dy / n
        let fill: Color = me ? C.brand : kit == "keeper" ? Color(hex: 0xFF9F43) : Color(hex: 0x5A6172)
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r + 2 * u, y: c.y - r + 3 * u, width: 2 * r, height: 2 * r)), with: .color(.black.opacity(0.3)))
        // facing chevron
        var nose = Path()
        nose.move(to: CGPoint(x: c.x + fx * r * 1.62, y: c.y + fy * r * 1.62))
        nose.addLine(to: CGPoint(x: c.x + fx * r * 0.85 - fy * r * 0.55, y: c.y + fy * r * 0.85 + fx * r * 0.55))
        nose.addLine(to: CGPoint(x: c.x + fx * r * 0.85 + fy * r * 0.55, y: c.y + fy * r * 0.85 - fx * r * 0.55))
        nose.closeSubpath()
        ctx.fill(nose, with: .color(me ? .white : fill))
        let body = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        ctx.fill(body, with: .linearGradient(Gradient(colors: [fill.opacity(1), fill.opacity(0.78)]), startPoint: CGPoint(x: c.x - r, y: c.y - r), endPoint: CGPoint(x: c.x + r, y: c.y + r)))
        ctx.stroke(body, with: .color(me ? .white : .black.opacity(0.45)), lineWidth: (me ? 2.2 : 1.5) * u)
        let hr = r * 0.42
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - hr, y: c.y - hr, width: 2 * hr, height: 2 * hr)), with: .color(Color(hex: 0x1B1E26)))
        if me {
            let label = CGPoint(x: c.x, y: c.y + r + 9 * u)
            let w = 26 * u, h = 12 * u
            ctx.fill(Path(roundedRect: CGRect(x: label.x - w / 2, y: label.y - h / 2, width: w, height: h), cornerRadius: h / 2), with: .color(.black.opacity(0.55)))
            ctx.draw(Text("YOU").font(.system(size: 7.5 * u, weight: .black, design: .rounded)).foregroundColor(.white), at: label)
        }
    }

    /// A ball from above, spinning as it rolls.
    private func ball(_ ctx: inout GraphicsContext, at c: CGPoint, spin: Double) {
        let r = 5.8 * u
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r + 1.5 * u, y: c.y - r + 2.5 * u, width: 2 * r, height: 2 * r)), with: .color(.black.opacity(0.32)))
        let e = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        ctx.fill(e, with: .radialGradient(Gradient(colors: [.white, Color(hex: 0xD9DDE5)]), center: CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.35), startRadius: 0, endRadius: r * 1.4))
        var inner = ctx
        inner.clip(to: e)
        func pentagon(_ at: CGPoint, _ size: CGFloat, _ rot: Double) -> Path {
            var p = Path()
            for i in 0..<5 {
                let a = rot + Double(i) * 2 * .pi / 5 - .pi / 2
                let q = CGPoint(x: at.x + cos(a) * size, y: at.y + sin(a) * size)
                if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
            }
            p.closeSubpath()
            return p
        }
        inner.fill(pentagon(c, r * 0.36, spin), with: .color(Color(hex: 0x15171C)))
        for i in 0..<5 {
            let a = spin + Double(i) * 2 * .pi / 5 - .pi / 2
            inner.fill(pentagon(CGPoint(x: c.x + cos(a) * r * 0.95, y: c.y + sin(a) * r * 0.95), r * 0.3, spin + .pi / 5), with: .color(Color(hex: 0x15171C)))
        }
        ctx.stroke(e, with: .color(.black.opacity(0.55)), lineWidth: 0.8 * u)
    }

    private func ripple(_ ctx: inout GraphicsContext, at c: CGPoint, k: Double) {
        let r = (7 + 12 * k) * u
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(.white.opacity(0.5 * (1 - k))), lineWidth: 1.5 * u)
    }

    // MARK: pitch

    /// Mown grass in diagonal stripes, darker at the edges, with a faint chalk box.
    static func grass(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        ctx.fill(Path(rect), with: .linearGradient(Gradient(colors: [Color(hex: 0x2F9A4D), Color(hex: 0x23793B)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        var stripes = ctx
        stripes.translateBy(x: size.width / 2, y: size.height / 2)
        stripes.rotate(by: .degrees(-28))
        let diag = hypot(size.width, size.height)
        let band = max(18, diag / 11)
        var x = -diag
        var i = 0
        while x < diag {
            if i % 2 == 0 { stripes.fill(Path(CGRect(x: x, y: -diag, width: band, height: 2 * diag)), with: .color(.white.opacity(0.05))) }
            x += band; i += 1
        }
        // grain
        let u = max(min(size.width, size.height) / 300, 0.42)
        for k in 0..<90 {
            let px = (sin(Double(k) * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1)
            let py = (sin(Double(k) * 78.233) * 12543.123).truncatingRemainder(dividingBy: 1)
            let p = CGPoint(x: abs(px) * size.width, y: abs(py) * size.height)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x, y: p.y, width: 1.6 * u, height: 1.6 * u)), with: .color(.black.opacity(0.12)))
        }
        let inset = rect.insetBy(dx: 10 * u, dy: 10 * u)
        ctx.stroke(Path(roundedRect: inset, cornerRadius: 6 * u), with: .color(.white.opacity(0.10)), lineWidth: 1.5 * u)
        ctx.fill(Path(rect), with: .radialGradient(Gradient(colors: [.clear, .black.opacity(0.32)]), center: CGPoint(x: size.width / 2, y: size.height / 2),
                                                   startRadius: min(size.width, size.height) * 0.35, endRadius: diag * 0.62))
    }

    // MARK: side view (copenhagen plank): forearm down, body straight, partner holds the top leg, hips go up and down

    static func side(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let u = min(size.width, size.height) / 300
        let W = size.width, H = size.height
        let ground = H * 0.78
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: W / 2 + x * u, y: ground - y * u) }
        var g = Path(); g.move(to: CGPoint(x: 0, y: ground)); g.addLine(to: CGPoint(x: W, y: ground))
        ctx.stroke(g, with: .color(.white.opacity(0.55)), lineWidth: 2 * u)
        let limb = StrokeStyle(lineWidth: 9 * u, lineCap: .round, lineJoin: .round)
        let mate = Color(hex: 0x5A6172)
        let elbow = P(-120, 0), shoulder = P(-112, 34), hip = P(-20, 52), ankle = P(80, 72)
        var body = Path(); body.move(to: elbow); body.addLine(to: shoulder); body.addLine(to: hip); body.addLine(to: ankle)
        ctx.stroke(body, with: .color(C.brandHi), style: limb)
        var hand = Path(); hand.move(to: elbow); hand.addLine(to: P(-82, 0))
        ctx.stroke(hand, with: .color(C.brandHi), style: limb)
        let face = P(-128, 54), hr = 12 * u
        ctx.fill(Path(ellipseIn: CGRect(x: face.x - hr, y: face.y - hr, width: 2 * hr, height: 2 * hr)), with: .color(C.brandHi))
        let pf = P(112, 0), ph = P(112, 70), ps = P(112, 128)
        var m = Path(); m.move(to: pf); m.addLine(to: ph); m.addLine(to: ps)
        ctx.stroke(m, with: .color(mate), style: limb)
        var arm = Path(); arm.move(to: P(112, 116)); arm.addLine(to: P(86, 76))
        ctx.stroke(arm, with: .color(mate), style: limb)
        let mh = P(112, 148)
        ctx.fill(Path(ellipseIn: CGRect(x: mh.x - hr, y: mh.y - hr, width: 2 * hr, height: 2 * hr)), with: .color(mate))
        let top = P(-20, 108), bottom = P(-20, 66)
        var a = Path(); a.move(to: bottom); a.addLine(to: top)
        ctx.stroke(a, with: .color(.white), style: StrokeStyle(lineWidth: 3.5 * u, lineCap: .round))
        for (from, to) in [(bottom, top), (top, bottom)] {
            let ang = atan2(to.y - from.y, to.x - from.x), l = 11 * u, w = 0.5
            var h = Path()
            h.move(to: to)
            h.addLine(to: CGPoint(x: to.x - l * cos(ang - w), y: to.y - l * sin(ang - w)))
            h.addLine(to: CGPoint(x: to.x - l * cos(ang + w), y: to.y - l * sin(ang + w)))
            h.closeSubpath()
            ctx.fill(h, with: .color(.white))
        }
    }
}
