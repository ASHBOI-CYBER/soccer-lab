// The coach's board (2026-10-27, notes/25 "Video or board"): drills with no Blender video are drawn FLAT and from
// ABOVE ? a mown pitch, gold cones, white ladders/hurdles, player tokens and white arrows along the run (dashed) or
// the ball (solid) ? so they never look like a paused video. Data = `board` in library.json (export-native.mjs).
import SwiftUI

struct Board: Codable, Hashable {
    struct Prop: Codable, Hashable { let k: String; let x: Double; let z: Double; let yaw: Double; let rungs: Int? }
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

    private static let stripeA = Color(hex: 0x2E8A45)
    private static let stripeB = Color(hex: 0x277A3C)
    private static let chalk = Color.white
    private static let mate = Color(hex: 0x515869)

    var body: some View {
        Canvas { ctx, size in
            // mown stripes
            let n = 8
            for i in 0..<n {
                let r = CGRect(x: 0, y: CGFloat(i) * size.height / CGFloat(n), width: size.width, height: size.height / CGFloat(n) + 1)
                ctx.fill(Path(r), with: .color(i % 2 == 0 ? Self.stripeA : Self.stripeB))
            }
            if board.side == true { drawSide(&ctx, size) } else { drawTop(&ctx, size) }
        }
    }

    // MARK: top-down

    private func drawTop(_ ctx: inout GraphicsContext, _ size: CGSize) {
        // fit everything (min span so a one-ball drill isn't blown up)
        var xs: [Double] = [], zs: [Double] = []
        for p in board.props {
            xs.append(p.x); zs.append(p.z)
            if p.k == "ladder" { xs.append(p.x + Double(p.rungs ?? 4) * 0.45) }
            if p.k == "goal" { xs += [p.x - 3.66, p.x + 3.66]; zs.append(p.z - 1.2) }
        }
        for m in board.players { xs.append(m.x); zs.append(m.z) }
        for b in board.balls { xs.append(b[0]); zs.append(b[1]) }
        for path in board.paths { for q in path.pts { xs.append(q[0]); zs.append(q[1]) } }
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 0, minZ = zs.min() ?? 0, maxZ = zs.max() ?? 0
        let span = 1.3
        let w = max(maxX - minX, span), h = max(maxZ - minZ, span)
        let cx = (minX + maxX) / 2, cz = (minZ + maxZ) / 2
        let u = max(min(size.width, size.height) / 300, 0.42)  // token scale: readable in a 62 pt row, true size in a 330 pt box
        let pad = 26 * u + 10
        let s = min((size.width - 2 * pad) / w, (size.height - 2 * pad) / h)
        func pt(_ x: Double, _ z: Double) -> CGPoint {
            CGPoint(x: size.width / 2 + (x - cx) * s, y: size.height / 2 + (z - cz) * s)
        }

        // props
        for p in board.props {
            let c = pt(p.x, p.z)
            switch p.k {
            case "ladder":
                let rungs = p.rungs ?? 4
                let a = pt(p.x, p.z - 0.25), b = pt(p.x + Double(rungs) * 0.45, p.z + 0.25)
                let r = CGRect(x: a.x, y: a.y, width: b.x - a.x, height: max(b.y - a.y, 14 * u))
                ctx.stroke(Path(r), with: .color(Self.chalk), lineWidth: 2.5 * u)
                for i in 1..<rungs {
                    let x = r.minX + r.width * CGFloat(i) / CGFloat(rungs)
                    var l = Path(); l.move(to: CGPoint(x: x, y: r.minY)); l.addLine(to: CGPoint(x: x, y: r.maxY))
                    ctx.stroke(l, with: .color(Self.chalk), lineWidth: 2 * u)
                }
            case "hurdle":
                // the bar lies across the run: yaw 1.57 ? along z
                let dx = cos(p.yaw), dz = -sin(p.yaw)
                let half = 9 * u
                var l = Path()
                l.move(to: CGPoint(x: c.x - dx * half, y: c.y - dz * half))
                l.addLine(to: CGPoint(x: c.x + dx * half, y: c.y + dz * half))
                ctx.stroke(l, with: .color(Self.chalk), style: StrokeStyle(lineWidth: 5 * u, lineCap: .round))
            case "goal":
                let a = pt(p.x - 3.66, p.z), b = pt(p.x + 3.66, p.z - 1.0)
                let net = CGRect(x: a.x, y: b.y, width: b.x - a.x, height: a.y - b.y)
                ctx.fill(Path(net), with: .color(.white.opacity(0.18)))
                var g = Path()
                g.move(to: CGPoint(x: net.minX, y: net.maxY)); g.addLine(to: CGPoint(x: net.minX, y: net.minY))
                g.addLine(to: CGPoint(x: net.maxX, y: net.minY)); g.addLine(to: CGPoint(x: net.maxX, y: net.maxY))
                ctx.stroke(g, with: .color(Self.chalk), lineWidth: 2 * u)
                var line = Path(); line.move(to: CGPoint(x: 0, y: net.maxY)); line.addLine(to: CGPoint(x: 9999, y: net.maxY))
                ctx.stroke(line, with: .color(.white.opacity(0.55)), lineWidth: 2 * u)
                ctx.stroke(Path(CGRect(x: net.minX - 2 * u, y: net.maxY - 2 * u, width: 4 * u, height: 4 * u)), with: .color(Self.chalk), lineWidth: 3 * u)
                ctx.stroke(Path(CGRect(x: net.maxX - 2 * u, y: net.maxY - 2 * u, width: 4 * u, height: 4 * u)), with: .color(Self.chalk), lineWidth: 3 * u)
            default:  // cone: a gold triangle
                let r = 8 * u
                var t = Path()
                t.move(to: CGPoint(x: c.x, y: c.y - r * 1.1))
                t.addLine(to: CGPoint(x: c.x + r, y: c.y + r * 0.75))
                t.addLine(to: CGPoint(x: c.x - r, y: c.y + r * 0.75))
                t.closeSubpath()
                ctx.fill(t, with: .color(C.gold))
                ctx.stroke(t, with: .color(C.goldInk), lineWidth: 1.5 * u)
            }
        }

        // arrows (under the tokens), numbered when there are a few
        let many = board.paths.count > 1 && board.paths.allSatisfy { $0.pts.count > 1 } && board.paths.contains { $0.pts.count > 2 || hypot($0.pts[0][0] - $0.pts[1][0], $0.pts[0][1] - $0.pts[1][1]) > 1 }
        for (i, path) in board.paths.enumerated() {
            let pts = path.pts.map { pt($0[0], $0[1]) }
            arrow(&ctx, pts, ball: path.ball == true, both: path.both == true, u: u)
            if many, let first = pts.first { badge(&ctx, "\(i + 1)", at: first, u: u) }
        }

        // balls
        for b in board.balls {
            let c = pt(b[0], b[1]), r = 6 * u
            let e = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            ctx.fill(e, with: .color(.white))
            ctx.stroke(e, with: .color(C.charInk), lineWidth: 1.5 * u)
            let d = r * 0.42
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - d, y: c.y - d, width: 2 * d, height: 2 * d)), with: .color(C.charInk))
        }

        // players: a round token + a nose that points where he faces (yaw 0 = +z = down)
        for (i, m) in board.players.enumerated() {
            let c = pt(m.x, m.z), r = 12 * u
            let fill: Color = m.kit == "you" ? C.creme : m.kit == "keeper" ? Color(hex: 0x615648) : Self.mate
            let fx = sin(m.yaw), fz = cos(m.yaw)
            var nose = Path()
            nose.move(to: CGPoint(x: c.x + fx * r * 1.55, y: c.y + fz * r * 1.55))
            nose.addLine(to: CGPoint(x: c.x - fz * r * 0.7, y: c.y + fx * r * 0.7))
            nose.addLine(to: CGPoint(x: c.x + fz * r * 0.7, y: c.y - fx * r * 0.7))
            nose.closeSubpath()
            ctx.fill(nose, with: .color(fill))
            let e = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            ctx.fill(e, with: .color(fill))
            ctx.stroke(e, with: .color(i == 0 ? C.brandInk : C.charInk), lineWidth: 2.5 * u)
            if i == 0 {
                ctx.draw(Text("YOU").font(.system(size: 7 * u, weight: .black, design: .rounded)).foregroundColor(C.brandInk), at: c)
            }
        }
    }

    /// White arrow along the points: dashed = you run, solid = the ball. Arrowhead at the end (and the start if `both`).
    private func arrow(_ ctx: inout GraphicsContext, _ pts: [CGPoint], ball: Bool, both: Bool, u: CGFloat) {
        guard pts.count > 1 else { return }
        var p = Path()
        p.move(to: pts[0])
        for q in pts.dropFirst() { p.addLine(to: q) }
        let style = StrokeStyle(lineWidth: (ball ? 3.5 : 3) * u, lineCap: .round, lineJoin: .round, dash: ball ? [] : [7 * u, 6 * u])
        ctx.stroke(p, with: .color(.black.opacity(0.18)), style: StrokeStyle(lineWidth: style.lineWidth + 3 * u, lineCap: .round, lineJoin: .round, dash: style.dash))
        ctx.stroke(p, with: .color(.white), style: style)
        head(&ctx, from: pts[pts.count - 2], to: pts[pts.count - 1], u: u)
        if both { head(&ctx, from: pts[1], to: pts[0], u: u) }
    }

    private func head(_ ctx: inout GraphicsContext, from a: CGPoint, to b: CGPoint, u: CGFloat) {
        let ang = atan2(b.y - a.y, b.x - a.x), l = 11 * u, w = 0.5
        var h = Path()
        h.move(to: b)
        h.addLine(to: CGPoint(x: b.x - l * cos(ang - w), y: b.y - l * sin(ang - w)))
        h.addLine(to: CGPoint(x: b.x - l * cos(ang + w), y: b.y - l * sin(ang + w)))
        h.closeSubpath()
        ctx.fill(h, with: .color(.white))
    }

    private func badge(_ ctx: inout GraphicsContext, _ s: String, at c: CGPoint, u: CGFloat) {
        let r = 8 * u
        let e = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        ctx.fill(e, with: .color(C.brandInk))
        ctx.draw(Text(s).font(.system(size: 10 * u, weight: .black, design: .rounded)).foregroundColor(.white), at: c)
    }

    // MARK: side view (copenhagen plank): forearm down, body straight, partner holds the top leg, hips go up and down

    private func drawSide(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let u = min(size.width, size.height) / 300
        let W = size.width, H = size.height
        let ground = H * 0.78
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: W / 2 + x * u, y: ground - y * u) }
        var g = Path(); g.move(to: CGPoint(x: 0, y: ground)); g.addLine(to: CGPoint(x: W, y: ground))
        ctx.stroke(g, with: .color(.white.opacity(0.55)), lineWidth: 2 * u)
        let limb = StrokeStyle(lineWidth: 9 * u, lineCap: .round, lineJoin: .round)
        // you (creme): elbow on the ground, shoulder above it, straight line to the feet on the partner's hands
        let elbow = P(-120, 0), shoulder = P(-112, 34), hip = P(-20, 52), ankle = P(80, 72)
        var body = Path(); body.move(to: elbow); body.addLine(to: shoulder); body.addLine(to: hip); body.addLine(to: ankle)
        ctx.stroke(body, with: .color(C.creme), style: limb)
        var hand = Path(); hand.move(to: elbow); hand.addLine(to: P(-82, 0))
        ctx.stroke(hand, with: .color(C.creme), style: limb)
        let face = P(-128, 54), hr = 12 * u
        ctx.fill(Path(ellipseIn: CGRect(x: face.x - hr, y: face.y - hr, width: 2 * hr, height: 2 * hr)), with: .color(C.creme))
        // partner (slate): standing, holding the ankle
        let pf = P(112, 0), ph = P(112, 70), ps = P(112, 128)
        var mate = Path(); mate.move(to: pf); mate.addLine(to: ph); mate.addLine(to: ps)
        ctx.stroke(mate, with: .color(Self.mate), style: limb)
        var arm = Path(); arm.move(to: P(112, 116)); arm.addLine(to: P(86, 76))
        ctx.stroke(arm, with: .color(Self.mate), style: limb)
        let mh = P(112, 148)
        ctx.fill(Path(ellipseIn: CGRect(x: mh.x - hr, y: mh.y - hr, width: 2 * hr, height: 2 * hr)), with: .color(Self.mate))
        // the move: hips up and down
        let top = P(-20, 108), bottom = P(-20, 66)
        var a = Path(); a.move(to: bottom); a.addLine(to: top)
        ctx.stroke(a, with: .color(.white), style: StrokeStyle(lineWidth: 3.5 * u, lineCap: .round))
        head(&ctx, from: bottom, to: top, u: u)
        head(&ctx, from: top, to: bottom, u: u)
    }
}
