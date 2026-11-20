// The SOCCER LAB mascot (2026-10-26, notes/30-mascot.md): a cartoon ball of turf with two big eyes, brows and a smile,
// made in Blender (app/blender/mascot.py). It lives on empty pages and asks every onboarding question, talking
// through a speech bubble.
//
// Two see-through video loops play on top of each other ? IDLE (smile) and TALK (chatter). Their body motion is
// identical, so showing TALK while the bubble types and IDLE while it waits looks like one character.
import SwiftUI

enum MascotClip {
    static func url(_ name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "mov", subdirectory: "Mascot")
    }
}

/// Just the character: idle loop, with the talk loop shown on top while `talking`.
struct MascotVideo: View {
    var talking: Bool
    /// The still stands in until the video's first frame is up ? the mascot is there the instant the page opens.
    @State private var playing = false
    var body: some View {
        ZStack {
            if let img = ImageCache.load("mascot", ext: "png", dir: "Mascot"), !playing {
                Image(uiImage: img).resizable().scaledToFit()
            }
            if let idle = MascotClip.url("mascot-idle"), let talk = MascotClip.url("mascot-talk") {
                LoopingVideo(url: idle, clear: true, onReady: { playing = true })
                LoopingVideo(url: talk, clear: true).opacity(talking ? 1 : 0)
            } else if ImageCache.load("mascot", ext: "png", dir: "Mascot") == nil {
                // SOCCER LAB (2026-11-12): no mascot video or still in the bundle, so the character is drawn here
                MascotDrawn(talking: talking)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The Soccer Lab mascot, drawn in code: the logo's ball with two eyes and a mouth. It bobs gently, blinks, and its
/// mouth opens and closes while `talking`. Everything is sized from the frame it is given (108 to 200 pt).
struct MascotDrawn: View {
    var talking: Bool
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: still)) { ctx in
            let t = still ? 0 : ctx.date.timeIntervalSinceReferenceDate
            GeometryReader { g in
                let s = min(g.size.width, g.size.height)
                let bob = CGFloat(sin(t * 2.2)) * s * 0.018
                // a blink every ~3.4 s, lasting about a tenth of a second
                let blink = t.truncatingRemainder(dividingBy: 3.4) < 0.12
                let open = talking ? CGFloat(0.35 + 0.65 * abs(sin(t * 11))) : 0
                ZStack {
                    Ellipse().fill(.black.opacity(0.35))
                        .frame(width: s * 0.5, height: s * 0.07)
                        .offset(y: s * 0.43)
                        .blur(radius: s * 0.02)
                    ZStack {
                        Image("AppBall").resizable().scaledToFit()
                        HStack(spacing: s * 0.13) {
                            MascotEye(size: s * 0.17, closed: blink)
                            MascotEye(size: s * 0.17, closed: blink)
                        }
                        .offset(y: -s * 0.04)
                        // closed: a smile; talking: the smile opens into a mouth
                        MascotMouth(open: open)
                            .fill(C.charInk)
                            .frame(width: s * 0.2, height: s * 0.12)
                            .offset(y: s * 0.15)
                    }
                    .frame(width: s * 0.9, height: s * 0.9)
                    .offset(y: bob - s * 0.03)
                }
                .frame(width: g.size.width, height: g.size.height)
            }
        }
    }
}

private struct MascotEye: View {
    let size: CGFloat
    let closed: Bool
    var body: some View {
        ZStack {
            if closed {
                Capsule().fill(C.charInk).frame(width: size, height: size * 0.16)
            } else {
                Ellipse().fill(.white).overlay(Ellipse().stroke(C.charInk, lineWidth: max(1.5, size * 0.1)))
                Circle().fill(C.charInk).frame(width: size * 0.5, height: size * 0.5).offset(y: size * 0.08)
                Circle().fill(.white).frame(width: size * 0.16, height: size * 0.16).offset(x: size * 0.1, y: -size * 0.04)
            }
        }
        .frame(width: size, height: size * 1.15)
    }
}

/// A smile whose lower lip drops as `open` goes 0 to 1.
private struct MascotMouth: Shape {
    var open: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        let top = r.minY + r.height * 0.15
        let drop = r.height * (0.28 + 0.6 * open)
        p.move(to: CGPoint(x: r.minX, y: top))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: top), control: CGPoint(x: r.midX, y: top + r.height * 0.22))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: top), control: CGPoint(x: r.midX, y: top + drop * 2))
        p.closeSubpath()
        return p
    }
}

/// Types `text` out a few characters at a time; `talking` is true while it types.
private struct Typer {
    static func run(_ text: String, shown: @escaping (Int) -> Void, talking: @escaping (Bool) -> Void) async -> Bool {
        shown(0)
        try? await Task.sleep(for: .milliseconds(220))
        if Task.isCancelled { return false }
        talking(true)
        var i = 0
        for ch in text {
            i += 1
            shown(i)
            try? await Task.sleep(for: .milliseconds(ch == " " ? 40 : 28))
            if Task.isCancelled { return false }
        }
        talking(false)
        return true
    }
}

/// The mascot with its speech bubble above. Lines play in turn; tap it to skip to the next one. (Empty pages.)
struct Mascot: View {
    let lines: [String]
    var size: CGFloat = 200

    @State private var line = 0
    @State private var shown = 0
    @State private var talking = false
    @State private var poke = false

    var body: some View {
        VStack(spacing: -8) {
            SpeechBubble(text: lines[safe: line] ?? "", shown: shown)
                .padding(.horizontal, 8)
                .zIndex(1)
            MascotVideo(talking: talking)
                .frame(width: size, height: size)
                .scaleEffect(poke ? 0.92 : 1, anchor: .bottom)
                .contentShape(Circle())
                .onTapGesture { next() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Socco says: " + lines.joined(separator: " "))
        .task(id: line) {
            let text = lines[safe: line] ?? ""
            guard await Typer.run(text, shown: { shown = $0 }, talking: { talking = $0 }) else { return }
            try? await Task.sleep(for: .seconds(3.2))
            if Task.isCancelled || lines.count < 2 { return }
            line = (line + 1) % lines.count
        }
    }

    private func next() {
        Haptics.play(.pop)
        withAnimation(.spring(response: 0.18, dampingFraction: 0.4)) { poke = true }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.45).delay(0.12)) { poke = false }
        if shown < (lines[safe: line]?.count ?? 0) { shown = lines[line].count; talking = false } else if lines.count > 1 {
            line = (line + 1) % lines.count
        }
    }
}

/// The mascot on the left, asking `text` in a bubble on its right (onboarding questions). Types it once; re-types when
/// the text changes. Tap to finish the line at once.
struct MascotSays: View {
    let text: String
    var size: CGFloat = 108
    var font: Font = F.display(22)

    @State private var shown = 0
    @State private var talking = false
    @State private var poke = false

    var body: some View {
        HStack(alignment: .center, spacing: -2) {
            MascotVideo(talking: talking)
                .frame(width: size, height: size)
                .scaleEffect(poke ? 0.92 : 1, anchor: .bottom)
            SpeechBubble(text: text, shown: shown, tail: .leading, font: font, align: .leading)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.play(.pop)
            withAnimation(.spring(response: 0.18, dampingFraction: 0.4)) { poke = true }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.45).delay(0.12)) { poke = false }
            shown = text.count
            talking = false
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityAddTraits(.isHeader)
        .task(id: text) { _ = await Typer.run(text, shown: { shown = $0 }, talking: { talking = $0 }) }
    }
}

/// A rounded bubble with a tail pointing at the mascot (down, or left). The whole line is laid out from the start (the
/// untyped part is invisible) so the bubble never changes size while it types.
struct SpeechBubble: View {
    let text: String
    let shown: Int
    var tail: Edge = .bottom
    var font: Font = F.round(17, .bold)
    var align: TextAlignment = .center

    var body: some View {
        Text(typed)
            .font(font)
            .multilineTextAlignment(align)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(BubbleShape(tail: tail).fill(C.creme).overlay(BubbleShape(tail: tail).stroke(C.line, lineWidth: 1)))
            .background(BubbleShape(tail: tail).fill(C.charInk).offset(y: 4))
            .padding(tail == .bottom ? .bottom : .leading, 12)
            .animation(nil, value: shown)
    }

    private var typed: AttributedString {
        var a = AttributedString(text)
        a.foregroundColor = C.charInk
        let n = min(shown, text.count)
        if n < text.count {
            let start = a.index(a.startIndex, offsetByCharacters: n)
            a[start..<a.endIndex].foregroundColor = .clear
        }
        return a
    }
}

private struct BubbleShape: Shape {
    var tail: Edge = .bottom

    /// One outline: rounded box with the tail cut into one edge (so the stroke has no line across the tail).
    func path(in r: CGRect) -> Path {
        let c = tail == .leading ? min(14, r.height / 2) : min(20, r.height / 2)
        let t: CGFloat = tail == .leading ? 8 : 11
        var p = Path()
        p.move(to: CGPoint(x: r.minX + c, y: r.minY))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.maxY), radius: c)
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY), radius: c)
        if tail == .bottom {
            p.addLine(to: CGPoint(x: r.midX + t, y: r.maxY))
            p.addLine(to: CGPoint(x: r.midX, y: r.maxY + 12))
            p.addLine(to: CGPoint(x: r.midX - t, y: r.maxY))
        }
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.minY), radius: c)
        if tail == .leading {
            let y = r.midY
            p.addLine(to: CGPoint(x: r.minX, y: y + t))
            p.addLine(to: CGPoint(x: r.minX - 13, y: y + 3))
            p.addLine(to: CGPoint(x: r.minX, y: y - t))
        }
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY), radius: c)
        p.closeSubpath()
        return p
    }
}
