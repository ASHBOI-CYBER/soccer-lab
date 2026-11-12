// Onboarding controls in the game style: big answer rows, chips, a ball-thumb slider, check boxes, the
// slow back button and the progress bar.
import SwiftUI

/// Big tappable answers. Picking one never moves on by itself: CONTINUE does.
struct Options: View {
    let options: [String]
    let value: String?
    var icon: ((String) -> AnyView?)? = nil
    let pick: (String) -> Void

    var body: some View {
        VStack(spacing: 12) {
            ForEach(options, id: \.self) { o in
                let on = value == o
                Button { pick(o) } label: {
                    HStack(spacing: 14) {
                        if let i = icon?(o) { i }
                        Text(o).font(F.round(19, .semibold)).foregroundStyle(C.creme)
                        Spacer()
                        ZStack {
                            Circle().fill(on ? C.brand : C.char950).frame(width: 28, height: 28)
                                .overlay(Circle().stroke(on ? C.brandInk : C.char600, lineWidth: 2.5))
                            if on { Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white) }
                        }
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 62)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(on ? C.brand.opacity(0.16) : C.char800)
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(on ? C.brand : C.charInk, lineWidth: 2.5))
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(on ? C.brandLip : C.charInk).offset(y: 4))
                    )
                }
                .buttonStyle(.press(.pop))
            }
        }
    }
}

struct Chip: View {
    let label: String
    let on: Bool
    var height: CGFloat = 44
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                if on { Image(systemName: "checkmark").font(.system(size: 13, weight: .black)) }
                Text(label).font(F.round(15.5, .semibold))
            }
            .foregroundStyle(on ? .white : C.creme)
            .padding(.horizontal, 15)
            .frame(height: height)
            .background(
                Capsule().fill(on ? LinearGradient(colors: [C.brandHi, C.brand, C.brandMid], startPoint: .top, endPoint: .bottom)
                                  : LinearGradient(colors: [C.char700, C.char800], startPoint: .top, endPoint: .bottom))
                    .overlay(Capsule().stroke(on ? C.brandInk : C.charInk, lineWidth: 2.5))
                    .background(Capsule().fill(on ? C.brandLip : Color(hex: 0x070D1F)).offset(y: 3))
            )
        }
        .buttonStyle(.press(on ? .unlatch : .pop))
    }
}

/// Wraps chips onto as many lines as they need.
struct Wrap: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 360
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > w, x > 0 { x = 0; y += row + spacing; row = 0 }
            x += sz.width + spacing
            row = max(row, sz.height)
        }
        return CGSize(width: w, height: y + row)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, row: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > b.maxX, x > b.minX { x = b.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += sz.width + spacing
            row = max(row, sz.height)
        }
    }
}

/// Notched slider with the ball as its thumb; a stud tick on every notch. ONLY the ball grabs (2026-10-29):
/// a swipe anywhere else on the row scrolls the page.
struct BallSlider: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    var unit = ""
    var compact = false
    var onGrab: () -> Void = {}
    @State private var dragging = false

    var body: some View {
        GeometryReader { g in
            let w = g.size.width - 36
            let frac = Double(value - range.lowerBound) / Double(range.upperBound - range.lowerBound)
            let knob: CGFloat = compact ? 34 : 40
            ZStack(alignment: .leading) {
                Capsule().fill(C.char950).frame(height: 14).overlay(Capsule().stroke(C.charInk, lineWidth: 2))
                    .padding(.horizontal, 18)
                Capsule().fill(LinearGradient(colors: [C.brandHi, C.brand], startPoint: .top, endPoint: .bottom))
                    .frame(width: max(14, w * frac + 9), height: 14)
                    .padding(.leading, 18)
                ZStack {
                    if !compact {
                        Text("\(value)\(unit.isEmpty ? "" : " \(unit)")")
                            .font(F.display(17)).foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(C.brandMid).overlay(Capsule().stroke(C.brandInk, lineWidth: 2)))
                            .offset(y: -38)
                            .fixedSize()
                            .allowsHitTesting(false)
                    }
                    IconBall(size: knob)
                        .rotationEffect(.degrees(frac * 540))
                        .scaleEffect(dragging ? 1.12 : 1)
                        .contentShape(Circle())
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("ballslider"))
                                .onChanged { d in
                                    if !dragging { dragging = true; onGrab(); Haptics.play(.press) }
                                    let f = min(1, max(0, (d.location.x - 18) / w))
                                    let raw = Double(range.lowerBound) + f * Double(range.upperBound - range.lowerBound)
                                    let v = min(range.upperBound, max(range.lowerBound, Int((raw / Double(step)).rounded()) * step))
                                    if v != value {
                                        Haptics.play(v == range.lowerBound || v == range.upperBound ? .wall : .stud)
                                        value = v
                                    }
                                }
                                .onEnded { _ in dragging = false }
                        )
                }
                .frame(width: 36)
                .offset(x: w * frac)
            }
            .frame(maxHeight: .infinity)
            .coordinateSpace(.named("ballslider"))
            .animation(.spring(response: 0.2), value: dragging)
        }
        .frame(height: compact ? 40 : 64)
        .padding(.top, compact ? 0 : 26)
    }
}

/// The app icon's ball (green panel, 3D shading) ? the ONE ball used across onboarding (2026-10-29).
struct IconBall: View {
    var size: CGFloat = 32
    var body: some View {
        Image("AppBall").resizable().interpolation(.high).scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle().inset(by: size * 0.015))
            .shadow(color: .black.opacity(0.35), radius: 0, y: size * 0.06)
    }
}

/// A chunky 3D tile (same lip + ink as the answer rows): green when on.
struct Tile3D<Content: View>: View {
    let on: Bool
    var height: CGFloat = 96
    var radius: CGFloat = 20
    let action: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Button(action: action) {
            content
                .frame(maxWidth: .infinity).frame(height: height)
                .background(
                    shape.fill(on ? LinearGradient(colors: [C.brand.opacity(0.32), C.brand.opacity(0.14)], startPoint: .top, endPoint: .bottom)
                                  : LinearGradient(colors: [C.char700, C.char800], startPoint: .top, endPoint: .bottom))
                        .overlay(shape.stroke(on ? C.brand : C.charInk, lineWidth: 2.5))
                        .background(shape.fill(on ? C.brandLip : C.charInk).offset(y: 5))
                )
                .overlay(alignment: .topTrailing) {
                    if on {
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .black)).foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(C.brand).overlay(Circle().stroke(C.brandInk, lineWidth: 2)))
                            .padding(7)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
        }
        .buttonStyle(.press(on ? .unlatch : .pop))
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: on)
    }
}

/// A day of the week as a chunky key (the old buttons were too narrow to show their letters).
struct DayKey: View {
    let day: String
    let on: Bool
    let toggle: () -> Void
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        Button(action: toggle) {
            VStack(spacing: 3) {
                Text(String(day.prefix(1))).font(F.display(22))
                Text(day.uppercased()).font(F.round(10, .bold)).opacity(0.8)
            }
            .foregroundStyle(on ? .white : C.creme2)
            .frame(maxWidth: .infinity).frame(height: 62)
            .background(
                shape.fill(on ? LinearGradient(colors: [C.brandHi, C.brand, C.brandMid], startPoint: .top, endPoint: .bottom)
                              : LinearGradient(colors: [C.char700, C.char800], startPoint: .top, endPoint: .bottom))
                    .overlay(shape.stroke(on ? C.brandInk : C.charInk, lineWidth: 2.5))
                    .background(shape.fill(on ? C.brandLip : C.charInk).offset(y: 4))
            )
            .offset(y: on ? 2 : 0)
        }
        .buttonStyle(.press(on ? .unlatch : .pop))
    }
}

/// "Where did you find me?" ? each answer gets its app's logo on its own app-style tile (logos: Simple Icons, CC0).
struct SourceLogo: View {
    let source: String
    var size: CGFloat = 36
    var body: some View {
        let r = size * 0.26
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        ZStack {
            switch source {
            case "TikTok":
                shape.fill(Color(hex: 0x010101))
                ZStack {
                    logo("Logo-tiktok", Color(hex: 0x25F4EE)).offset(x: -1, y: -1)
                    logo("Logo-tiktok", Color(hex: 0xFE2C55)).offset(x: 1, y: 1)
                    logo("Logo-tiktok", .white)
                }
            case "Instagram":
                shape.fill(LinearGradient(colors: [Color(hex: 0xFEDA75), Color(hex: 0xFA7E1E), Color(hex: 0xD62976), Color(hex: 0x962FBF), Color(hex: 0x4F5BD5)],
                                          startPoint: .bottomLeading, endPoint: .topTrailing))
                logo("Logo-instagram", .white)
            case "YouTube":
                shape.fill(.white)
                logo("Logo-youtube", Color(hex: 0xFF0000), scale: 0.66)
            case "App Store":
                shape.fill(LinearGradient(colors: [Color(hex: 0x1BC0FA), Color(hex: 0x1C6EF2)], startPoint: .top, endPoint: .bottom))
                logo("Logo-appstore", .white)
            case "A friend":
                shape.fill(LinearGradient(colors: [C.brandHi, C.brand, C.brandMid], startPoint: .top, endPoint: .bottom))
                Image(systemName: "person.2.fill").font(.system(size: size * 0.38, weight: .bold)).foregroundStyle(.white)
            default:
                shape.fill(LinearGradient(colors: [C.char600, C.char700], startPoint: .top, endPoint: .bottom))
                Image(systemName: "ellipsis").font(.system(size: size * 0.4, weight: .black)).foregroundStyle(C.creme)
            }
        }
        .frame(width: size, height: size)
        .overlay(shape.stroke(.black.opacity(0.35), lineWidth: 1.5))
        .background(shape.fill(C.charInk).offset(y: 3))
    }

    private func logo(_ name: String, _ tint: Color, scale: CGFloat = 0.56) -> some View {
        Image(name).renderingMode(.template).resizable().scaledToFit()
            .foregroundStyle(tint).frame(width: size * scale, height: size * scale)
    }
}

struct CheckBox: View {
    let label: String
    let on: Bool
    let toggle: () -> Void
    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9).fill(on ? C.brand : C.char950).frame(width: 32, height: 32)
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(on ? C.brandInk : C.char600, lineWidth: 2.5))
                    if on { Image(systemName: "checkmark").font(.system(size: 15, weight: .black)).foregroundStyle(.white) }
                }
                Text(label).font(F.round(18, .semibold)).foregroundStyle(C.creme)
                Spacer()
            }
        }
        .buttonStyle(.press(on ? .unlatch : .pop))
    }
}

/// Game-style segmented control.
struct GameSegmented: View {
    let options: [String]
    @Binding var value: String
    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { o in
                Button {
                    if o != value { Haptics.play(.stud); value = o }
                } label: {
                    Text(o).font(F.display(17))
                        .foregroundStyle(o == value ? .white : C.muted)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background {
                            if o == value {
                                Capsule().fill(LinearGradient(colors: [C.brandHi, C.brand, C.brandMid], startPoint: .top, endPoint: .bottom))
                                    .overlay(Capsule().stroke(C.brandInk, lineWidth: 2))
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(C.char950).overlay(Capsule().stroke(C.charInk, lineWidth: 2)))
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: value)
    }
}

/// Back is slow on purpose, but silent (2026-10-29, user: no ring closing, "just make it suddenly delayed"):
/// the tap gives one haptic, then nothing happens for most of a second, then it goes.
struct SlowBack: View {
    let action: () -> Void
    @State private var waiting = false
    var body: some View {
        Button {
            guard !waiting else { return }
            waiting = true
            Haptics.play(.unlatch)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { action(); waiting = false }   // was 0.9 s (user, 2026-11-08: "a lot quicker")
        } label: {
            ZStack {
                Circle().fill(C.char850).overlay(Circle().stroke(C.charInk, lineWidth: 2)).frame(width: 40, height: 40)
                Image(systemName: "chevron.left").font(.system(size: 16, weight: .heavy)).foregroundStyle(C.muted)
            }
        }
        .buttonStyle(.plain)
        .frame(width: 48, height: 48)
    }
}

struct ProgressBar: View {
    let value: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(C.char950).overlay(Capsule().stroke(C.charInk, lineWidth: 2))
                Capsule().fill(LinearGradient(colors: [C.brandHi, C.brand], startPoint: .top, endPoint: .bottom))
                    .frame(width: max(10, g.size.width * value))
                    .padding(2)
            }
        }
        .frame(height: 12)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: value)
    }
}
