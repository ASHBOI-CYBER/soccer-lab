// SOCCER LAB look in SwiftUI (2026-11-13): black surfaces, one electric blue accent, flat cards with a hairline
// border, heavy system type. The cartoon game look (bubble font, 3D buttons, weave) is gone; the names stay.
// The `char*` names are the dark neutrals (navy now, charcoal before the 2026-11-12 blue retheme).
// Same values as the web kit (src/ui/game/game.css) so the brand doesn't change ? only the tech does.
import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

enum C {
    static let brandHi = Color(hex: 0x7DB8FF)
    static let brand = Color(hex: 0x1E78FF)
    static let brandMid = Color(hex: 0x0F5FE0)
    static let brandLip = Color(hex: 0x0A3FA3)
    static let brandInk = Color(hex: 0x06225C)

    static let char950 = Color(hex: 0x000000)
    static let char900 = Color(hex: 0x000000)
    static let char850 = Color(hex: 0x08090C)
    static let char800 = Color(hex: 0x0E1015)
    static let char700 = Color(hex: 0x181B23)
    static let char600 = Color(hex: 0x2C303C)
    static let charInk = Color(hex: 0x000000)
    /// The hairline around cards and controls.
    static let line = Color(hex: 0x20232C)

    static let creme = Color(hex: 0xFFFFFF)
    static let creme2 = Color(hex: 0xC5CAD6)
    static let muted = Color(hex: 0x808797)
    static let gold = Color(hex: 0xFFC531)
    static let goldHi = Color(hex: 0xFFE48A)
    static let goldMid = Color(hex: 0xF4AB12)
    static let goldLip = Color(hex: 0xB87708)
    static let goldInk = Color(hex: 0x6B4300)
}

enum F {
    /// Headings: the system face, heavy. A little smaller than the old bubble font, which ran wide.
    static func display(_ size: CGFloat) -> Font { .system(size: (size * 0.84).rounded(), weight: .heavy) }
    static func round(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        switch weight {
        case .bold, .heavy, .black: return .system(size: size, weight: .bold)
        case .semibold: return .system(size: size, weight: .semibold)
        default: return .system(size: size, weight: .medium)
        }
    }
}

// MARK: - headings: plain heavy type (was a bubble font with an outline and a drop)

struct Disp: View {
    let text: String
    var size: CGFloat = 28
    var color: Color = C.creme
    var ink: Color = C.charInk
    var outline: CGFloat? = nil

    init(_ text: String, size: CGFloat = 28, color: Color = C.creme, ink: Color = C.charInk) {
        self.text = text
        self.size = size
        self.color = color
        self.ink = ink
    }

    var body: some View {
        Text(text)
            .font(F.display(size))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - background: black, with a faint blue glow at the top

struct AppBackground: View {
    var body: some View {
        ZStack {
            Color.black
            // the glow: a blue light above the screen, and a fainter one low on the left
            RadialGradient(colors: [C.brand.opacity(0.34), C.brand.opacity(0.08), .clear], center: UnitPoint(x: 0.5, y: -0.08), startRadius: 0, endRadius: 420)
            RadialGradient(colors: [C.brandMid.opacity(0.14), .clear], center: UnitPoint(x: 0.0, y: 0.85), startRadius: 0, endRadius: 320)
        }
        .ignoresSafeArea()
    }
}

// MARK: - game button: a chunky face on a darker lip; press sinks it onto the lip

enum Tint {
    case brand, charcoal, gold, creme

    var hi: Color { switch self { case .brand: C.brandHi; case .charcoal: Color(hex: 0x34497D); case .gold: C.goldHi; case .creme: .white } }
    var face: Color { switch self { case .brand: C.brand; case .charcoal: C.char700; case .gold: C.gold; case .creme: C.creme } }
    var lo: Color { switch self { case .brand: C.brandMid; case .charcoal: Color(hex: 0x14213F); case .gold: C.goldMid; case .creme: C.creme2 } }
    var lip: Color { switch self { case .brand: C.brandLip; case .charcoal: Color(hex: 0x070D1F); case .gold: C.goldLip; case .creme: Color(hex: 0x8C9BBD) } }
    var ink: Color { switch self { case .brand: C.brandInk; case .charcoal: C.charInk; case .gold: C.goldInk; case .creme: Color(hex: 0x1B2540) } }
    var label: Color { switch self { case .creme: C.brandMid; case .charcoal: C.creme; case .gold: .black; default: .white } }
}

struct GameButtonStyle: ButtonStyle {
    var tint: Tint = .brand
    var height: CGFloat = 58
    var fontSize: CGFloat = 24
    var block = true
    var round = false
    var feel: Haptic? = nil
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let t = enabled ? tint : .charcoal
        let pressed = configuration.isPressed
        let shape = Capsule()
        return configuration.label
            .font(.system(size: Swift.max(14, (fontSize * 0.7).rounded()), weight: .bold))
            .foregroundStyle(enabled ? t.label : C.muted)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, round ? 0 : 20)
            .frame(maxWidth: block ? .infinity : nil)
            .frame(width: round ? height : nil, height: height)
            .background(
                shape.fill(t == .brand ? AnyShapeStyle(LinearGradient(colors: [C.brandHi, C.brand, C.brandMid], startPoint: .top, endPoint: .bottom))
                           : AnyShapeStyle(t == .charcoal ? C.char700 : t.face))
            )
            .overlay(shape.stroke(t == .charcoal ? C.line : Color.white.opacity(0.18), lineWidth: 1))
            // the primary action glows
            .shadow(color: t == .brand ? C.brand.opacity(0.6) : .clear, radius: 14, y: 4)
            .opacity(pressed ? 0.82 : 1)
            .scaleEffect(pressed ? 0.98 : 1)
            .animation(.spring(response: 0.18, dampingFraction: 0.7), value: pressed)
            .onChange(of: pressed) { _, down in
                if down { Haptics.play(.press) } else { Haptics.play(feel ?? (tint == .brand && height > 60 ? .kick : .release)) }
            }
    }
}

extension ButtonStyle where Self == GameButtonStyle {
    static var game: GameButtonStyle { GameButtonStyle() }
    static func game(_ tint: Tint, height: CGFloat = 58, font: CGFloat = 24, block: Bool = true, feel: Haptic? = nil) -> GameButtonStyle {
        GameButtonStyle(tint: tint, height: height, fontSize: font, block: block, feel: feel)
    }
    static var gameLarge: GameButtonStyle { GameButtonStyle(tint: .brand, height: 64, fontSize: 27) }
    static func gameLarge(_ tint: Tint, feel: Haptic? = nil) -> GameButtonStyle { GameButtonStyle(tint: tint, height: 64, fontSize: 27, feel: feel) }
    static func gameRound(_ tint: Tint = .charcoal, size: CGFloat = 46) -> GameButtonStyle {
        GameButtonStyle(tint: tint, height: size, fontSize: 18, block: false, round: true, feel: .stud)
    }
}

/// Tappable rows and cards: sink a touch and tick.
struct PressStyle: ButtonStyle {
    var feel: Haptic = .release
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, down in Haptics.play(down ? .press : feel) }
    }
}

extension ButtonStyle where Self == PressStyle {
    static var press: PressStyle { PressStyle() }
    static func press(_ feel: Haptic) -> PressStyle { PressStyle(feel: feel) }
}

// MARK: - surfaces

struct GameCard: ViewModifier {
    var padding: CGFloat = 14
    var radius: CGFloat = 22
    var stroke: Color = C.charInk
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x13161D), C.char850], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(LinearGradient(colors: [Color.white.opacity(0.10), C.line], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            )
    }
}

extension View {
    func gameCard(padding: CGFloat = 14, radius: CGFloat = 22, stroke: Color = C.charInk) -> some View {
        modifier(GameCard(padding: padding, radius: radius, stroke: stroke))
    }

    /// Pinned bottom action area above the home indicator.
    func dock<D: View>(fade: Color = C.char900, @ViewBuilder _ content: () -> D) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            content()
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 6)
                .background(
                    LinearGradient(colors: [fade.opacity(0), fade.opacity(0.95), fade], startPoint: .top, endPoint: .center)
                        .ignoresSafeArea()
                )
        }
    }
}

/// Small section heading.
struct H: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(F.round(17, .bold))
            .foregroundStyle(C.creme)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 18)
            .padding(.bottom, 4)
    }
}

/// The ball glyph used for icons, the toggle knob and the slider thumb.
struct BallGlyph: View {
    var size: CGFloat = 24
    var body: some View {
        Canvas { ctx, s in
            let k = s.width / 40
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * k, y: y * k) }
            let circle = Path(ellipseIn: CGRect(x: 1.5 * k, y: 1.5 * k, width: 37 * k, height: 37 * k))
            ctx.fill(circle, with: .color(Color(hex: 0xF7F5EF)))
            ctx.stroke(circle, with: .color(Color(hex: 0x070D1F)), lineWidth: 2.5 * k)
            var pent = Path()
            pent.addLines([p(20, 12.5), p(27, 17.5), p(24.3, 25.7), p(15.7, 25.7), p(13, 17.5)])
            pent.closeSubpath()
            ctx.fill(pent, with: .color(Color(hex: 0x070D1F)))
            var seams = Path()
            for (a, b) in [((20, 12.5), (20, 4)), ((27, 17.5), (35, 15)), ((24.3, 25.7), (29.3, 32.5)), ((15.7, 25.7), (10.7, 32.5)), ((13, 17.5), (5, 15))] as [((CGFloat, CGFloat), (CGFloat, CGFloat))] {
                seams.move(to: p(a.0, a.1)); seams.addLine(to: p(b.0, b.1))
            }
            ctx.stroke(seams, with: .color(Color(hex: 0x070D1F)), lineWidth: 2.2 * k)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - titles (iOS 26 ignores bar-appearance fonts, so titles are drawn in SwiftUI)

/// Big tab title in the bubble face, with an optional control on the right.
struct TabHeader<Right: View>: View {
    let title: String
    @ViewBuilder var right: Right
    @Environment(\.duoTopExtra) private var duoTop
    var body: some View {
        HStack(alignment: .center) {
            Disp(title, size: 40)
            Spacer()
            right
        }
        .padding(.horizontal, 4)
        .padding(.top, 6 + duoTop)
    }
}

extension TabHeader where Right == EmptyView {
    init(_ title: String) { self.init(title: title) { EmptyView() } }
}

extension View {
    /// Detail-page title: small bubble type in the nav bar, native back button and swipe-back kept.
    func screenTitle(_ t: String) -> some View {
        navigationTitle(t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(t).font(F.display(20)).foregroundStyle(C.creme).lineLimit(1)
                }
            }
    }

    /// Tab root: the title lives in the content, the bar only keeps the status area clear.
    func tabRoot(_ t: String) -> some View {
        navigationTitle(t).toolbar(.hidden, for: .navigationBar)
    }
}

/// Native search field in the game style.
struct SearchField: View {
    @Binding var text: String
    let prompt: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 17, weight: .bold)).foregroundStyle(C.muted)
            TextField("", text: $text, prompt: Text(prompt).foregroundStyle(C.muted))
                .font(F.round(17, .semibold))
                .foregroundStyle(C.creme)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(C.muted) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(C.char950)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(C.charInk, lineWidth: 2)))
    }
}

// MARK: - iPhone Duo (2026-11-01, notes/19 top)

/// iPhone Duo inner display (horizontal size class REGULAR): every page stays a centered phone-width column and the
/// dark page colour fills the rest edge to edge, so nothing stretches across the big screen. On every other iPhone
/// (compact) it does nothing. One view either way (only the max width changes), so unfolding never resets a page.
struct DuoColumn: ViewModifier {
    @Environment(\.horizontalSizeClass) private var h
    var width: CGFloat = 600
    /// false = the caller draws its own full-width background behind (onboarding)
    var fill = true
    /// The top safe area. On the Duo's OUTER display the status bar sits on a side rail, so the top inset is 0 and
    /// tab titles hit the screen edge (seen on the Duo simulator 2026-11-01). The missing room goes to `TabHeader`
    /// through `\.duoTopExtra` (safeAreaPadding here never reached the scroll views inside the tabs). Normal iPhones
    /// have ~59 pt up there ? 0 extra.
    @State private var top: CGFloat = 100
    private let minTop: CGFloat = 22
    func body(content: Content) -> some View {
        content
            .environment(\.duoTopExtra, max(0, minTop - top))
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { top = $0 }
            .frame(maxWidth: h == .regular ? width : .infinity)
            .frame(maxWidth: .infinity)
            .background { AppBackground().opacity(fill && h == .regular ? 1 : 0) }
    }
}

extension EnvironmentValues {
    /// Extra room above tab titles where the screen has no top safe area (iPhone Duo outer display). See DuoColumn.
    @Entry var duoTopExtra: CGFloat = 0
}

extension View {
    /// Tab roots, onboarding and the paywall: a centered column on the iPhone Duo inner display (DuoColumn).
    func duoColumn(_ width: CGFloat = 600, fill: Bool = true) -> some View { modifier(DuoColumn(width: width, fill: fill)) }
}
