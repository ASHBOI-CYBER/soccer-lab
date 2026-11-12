// Team look (2026-10-26, notes/26 "v3"): a soft GREEN GRADIENT that follows your finger. Touch a card and a glow blooms
// under the fingertip and fades when you let go; the code keypad uses the same light. Used on the Team tab + the
// join-code sheet only ? the rest of the app keeps its flat game cards.
import SwiftUI

/// The page's green gradient: soft green light that is always there (it breathes slowly) and, when you touch the
/// page, drifts toward your finger in one smooth shift ? never a hard follow ? then eases back when you let go.
struct PageGlow: ViewModifier {
    @GestureState private var down = false
    @State private var pull = CGSize.zero       // -0.5?0.5 across the page
    @State private var breathe = false
    @State private var page = CGRect(x: 0, y: 0, width: 1, height: 1)   // this page in global space (not UIScreen.main ? iPhone Duo has two screens)

    @Environment(\.horizontalSizeClass) private var hClass
    /// iPhone Duo inner display: the page is a centered column (duoColumn) and the nav stack clips at its edges, so
    /// the light fades out toward both sides instead of ending in a hard seam. Full width on every other iPhone.
    private var edgeFade: LinearGradient {
        let e: CGFloat = hClass == .regular ? 0.22 : 0
        return LinearGradient(stops: [.init(color: e > 0 ? .clear : .black, location: 0), .init(color: .black, location: max(e, 0.001)),
                                      .init(color: .black, location: min(1 - e, 0.999)), .init(color: e > 0 ? .clear : .black, location: 1)],
                              startPoint: .leading, endPoint: .trailing)
    }

    private func blob(_ x: CGFloat, _ y: CGFloat, _ color: Color, _ r: CGFloat, _ k: CGFloat, _ w: CGFloat) -> some View {
        RadialGradient(colors: [color, color.opacity(0.35), .clear],
                       center: UnitPoint(x: x + pull.width * k + (breathe ? 0.04 : -0.04),
                                         y: y + pull.height * k + (breathe ? -0.03 : 0.03)),
                       startRadius: 0, endRadius: w * r)
    }

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { g in
                    let w = max(g.size.width, 1), h = max(g.size.height, 1)
                    ZStack {
                        blob(0.15, 0.06, C.brand.opacity(0.30), 1.0, 0.6, w)
                        blob(0.95, 0.50, C.brandMid.opacity(0.20), 0.9, 0.5, w)
                        blob(0.25, 0.98, C.brand.opacity(0.16), 0.9, 0.4, w)
                    }
                    .frame(width: w, height: h)
                    .mask(edgeFade)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .updating($down) { _, s, _ in s = true }
                    .onChanged { v in
                        let w = max(page.width, 1), h = max(page.height, 1)
                        withAnimation(.smooth(duration: 1.8)) {
                            pull = CGSize(width: (v.location.x - page.minX) / w - 0.5, height: (v.location.y - page.minY) / h - 0.5)
                        }
                    }
            )
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { page = $0 }
            .onChange(of: down) { _, d in
                if !d { withAnimation(.smooth(duration: 3)) { pull = .zero } }
            }
            .onAppear { withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) { breathe = true } }
    }
}

extension View {
    func pageGlow() -> some View { modifier(PageGlow()) }
}

// MARK: - the code entry

/// Six boxes + a numbers keypad (1?9, paste, 0, delete) bound to `code`. No system keyboard.
struct CodeEntry: View {
    @Binding var code: String
    var keypad = true
    @State private var open = false

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { i in
                    CodeBox(ch: i < code.count ? String(Array(code)[i]) : "", active: open && i == min(code.count, 5) && code.count < 6, filled: code.count == 6)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { open = true }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Code")
            .accessibilityValue(code.isEmpty ? "empty" : code.map(String.init).joined(separator: " "))
            if keypad, open { Keypad(code: $code).transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        .animation(.snappy, value: open)
    }
}

private struct CodeBox: View {
    let ch: String
    let active: Bool
    let filled: Bool
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        Text(ch)
            .font(.system(size: 28, weight: .heavy, design: .monospaced)).foregroundStyle(C.creme)
            .frame(maxWidth: .infinity).frame(height: 58)
            .background(
                shape.fill(ch.isEmpty ? AnyShapeStyle(C.char950)
                           : AnyShapeStyle(LinearGradient(colors: [C.brand.opacity(0.30), C.brandMid.opacity(0.10)], startPoint: .top, endPoint: .bottom)))
                    .overlay(shape.stroke(active ? C.brand : ch.isEmpty ? C.charInk : C.brand.opacity(filled ? 0.9 : 0.55), lineWidth: active ? 2.5 : 2))
            )
            .overlay(alignment: .bottom) {
                if ch.isEmpty { Capsule().fill(active ? C.brand : C.char700).frame(width: 14, height: 3).padding(.bottom, 14) }
            }
            .shadow(color: active ? C.brand.opacity(0.35) : .clear, radius: 8)
            .scaleEffect(ch.isEmpty ? 1 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.55), value: ch)
            .animation(.easeOut(duration: 0.15), value: active)
    }
}

private struct Keypad: View {
    @Binding var code: String

    private let rows: [[Key]] = [[.d("1"), .d("2"), .d("3")], [.d("4"), .d("5"), .d("6")], [.d("7"), .d("8"), .d("9")], [.paste, .d("0"), .delete]]

    enum Key: Hashable { case d(String), paste, delete }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 8) {
                    ForEach(rows[r], id: \.self) { k in KeyCap(key: k, enabled: enabled(k)) { press(k) } }
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(C.char950.opacity(0.35))
        )
    }

    private func enabled(_ k: Key) -> Bool {
        switch k {
        case .d: code.count < 6
        case .delete: !code.isEmpty
        case .paste: code.isEmpty && UIPasteboard.general.hasStrings
        }
    }

    private func press(_ k: Key) {
        switch k {
        case .d(let n): if code.count < 6 { code += n; Haptics.play(.stud) }
        case .delete: if !code.isEmpty { code.removeLast(); Haptics.play(.unlatch) }
        case .paste: if let v = UIPasteboard.general.string { code = Team.clean(v); Haptics.play(.latch) }
        }
    }
}

/// One key. It lights up green under your finger, sinks a little, and fires on release (if you're still on it).
private struct KeyCap: View {
    let key: Keypad.Key
    let enabled: Bool
    let tap: () -> Void
    @GestureState private var down = false
    @State private var at = CGPoint(x: 0.5, y: 0.5)
    @State private var size = CGSize(width: 100, height: 50)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        ZStack {
            shape.fill(LinearGradient(colors: [C.char700, C.char800], startPoint: .top, endPoint: .bottom))
            if down { shape.fill(.white.opacity(0.08)) }
            shape.inset(by: 2).stroke(.white.opacity(0.10), lineWidth: 1.5)
                .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center))
            label
        }
        .clipShape(shape)
        .overlay(shape.stroke(C.charInk, lineWidth: 2))
        .frame(height: 50)
        .background(GeometryReader { g in Color.clear.onAppear { size = g.size }.onChange(of: g.size) { _, s in size = s } })
        .scaleEffect(down ? 0.94 : 1)
        .animation(.spring(response: 0.2, dampingFraction: 0.55), value: down)
        .opacity(enabled ? 1 : 0.35)
        .contentShape(shape)
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($down) { _, s, _ in s = enabled }
                .onChanged { at = $0.location }
                .onEnded { v in
                    let inside = CGRect(origin: .zero, size: size).insetBy(dx: -10, dy: -10).contains(v.location)
                    if enabled, inside { tap() }
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11y)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if enabled { tap() } }
    }

    @ViewBuilder private var label: some View {
        switch key {
        case .d(let n): Text(n).font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(C.creme)
        case .delete: Image(systemName: "delete.left.fill").font(.system(size: 20, weight: .bold)).foregroundStyle(C.creme2)
        case .paste: Image(systemName: "doc.on.clipboard.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(C.creme2)
        }
    }

    private var a11y: String {
        switch key { case .d(let n): n; case .delete: "Delete"; case .paste: "Paste code" }
    }
}
