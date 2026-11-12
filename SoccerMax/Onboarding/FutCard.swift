// The player card: an FC-style shield (bronze / silver / gold, plus the green-black MAX card for the 6-week
// target) with the 3D guy as the portrait (pre-rendered from the stage), overall + position, name, six stats.
import SwiftUI

struct Shield: Shape {
    // Same outline as the web card (viewBox 300 × 420).
    func path(in r: CGRect) -> Path {
        let sx = r.width / 300, sy = r.height / 420
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * sx, y: r.minY + y * sy) }
        var path = Path()
        path.move(to: p(150, 6))
        path.addLine(to: p(196, 6))
        path.addCurve(to: p(230, 18), control1: p(210, 6), control2: p(214, 18))
        path.addLine(to: p(280, 18))
        path.addCurve(to: p(292, 30), control1: p(288, 18), control2: p(292, 22))
        path.addLine(to: p(292, 330))
        path.addCurve(to: p(274, 358), control1: p(292, 344), control2: p(286, 352))
        path.addLine(to: p(162, 410))
        path.addQuadCurve(to: p(138, 410), control: p(150, 416))
        path.addLine(to: p(26, 358))
        path.addCurve(to: p(8, 330), control1: p(14, 352), control2: p(8, 344))
        path.addLine(to: p(8, 30))
        path.addCurve(to: p(20, 18), control1: p(8, 22), control2: p(12, 18))
        path.addLine(to: p(70, 18))
        path.addCurve(to: p(104, 6), control1: p(86, 18), control2: p(90, 6))
        path.closeSubpath()
        return path
    }
}

private struct TierLook {
    let stops: [Color]; let glow: Color; let edge: Color; let rim: Color; let ink: Color; let hi: Color

    static func of(_ t: Tier) -> TierLook {
        switch t {
        case .gold: TierLook(stops: [Color(hex: 0xFCEBA4), Color(hex: 0xE4BC4E), Color(hex: 0xA9761F)], glow: Color(hex: 0xFFF8D8, alpha: 0.75),
                             edge: Color(hex: 0x6E4E0E), rim: Color(hex: 0xFFF6D2, alpha: 0.7), ink: Color(hex: 0x3A2A08), hi: C.brandLip)
        case .silver: TierLook(stops: [Color(hex: 0xFBFCFD), Color(hex: 0xC7CED5), Color(hex: 0x858F98)], glow: Color(hex: 0xFFFFFF, alpha: 0.8),
                               edge: Color(hex: 0x545D66), rim: Color(hex: 0xFFFFFF, alpha: 0.75), ink: Color(hex: 0x22272C), hi: C.brandLip)
        case .bronze: TierLook(stops: [Color(hex: 0xF5D0A6), Color(hex: 0xC88A52), Color(hex: 0x81491E)], glow: Color(hex: 0xFFE8CC, alpha: 0.7),
                               edge: Color(hex: 0x55300F), rim: Color(hex: 0xFFE8CC, alpha: 0.65), ink: Color(hex: 0x351B08), hi: C.brandLip)
        case .max: TierLook(stops: [Color(hex: 0x1A2A52), Color(hex: 0x081022), Color(hex: 0x0B2A6B)], glow: C.brand.opacity(0.45),
                            edge: C.brand, rim: C.brandHi.opacity(0.6), ink: C.creme, hi: C.brandHi)
        }
    }
}

struct FutCard: View {
    let card: PlayerCardStats
    let name: String
    let position: String
    let tier: Tier
    var width: CGFloat = 260
    /// Stats to highlight (the one being rated, or the ones that grew).
    var up: Set<String> = []
    /// The player's club: its crest sits under the position, like a real FC card.
    var club: Club? = nil
    @State private var shine = false

    var body: some View {
        let w = width, h = width * 1.4, em = width / 260 * 16
        let look = TierLook.of(tier)
        ZStack(alignment: .topLeading) {
            ZStack {
                Shield().fill(LinearGradient(colors: look.stops, startPoint: .topLeading, endPoint: .bottomTrailing))
                RadialGradient(colors: [look.glow, look.glow.opacity(0)], center: UnitPoint(x: 0.64, y: 0.3), startRadius: 0, endRadius: w * 0.6)
                Rectangle().fill(.white.opacity(tier == .max ? 0.12 : 0.35)).frame(width: w * 0.16, height: h * 1.4)
                    .blur(radius: 6).rotationEffect(.degrees(25))
                    .offset(x: shine ? w * 1.1 : -w * 1.1)
            }
            .frame(width: w, height: h)
            .clipShape(Shield())
            .overlay(Shield().stroke(look.edge, lineWidth: 3.5 * w / 300))
            .overlay(Shield().stroke(look.rim, lineWidth: 1.4 * w / 300).scaleEffect(0.94))
            .background(Shield().fill(.black.opacity(0.4)).offset(y: 6))
            .shadow(color: .black.opacity(0.35), radius: 12, y: 14)

            if let img = UIImage(named: tier == .max ? "portrait-max.png" : "portrait-gold.png") {
                Image(uiImage: img).resizable().scaledToFit()
                    .frame(width: w * 0.73, height: h * 0.58)
                    .offset(x: w * 0.25, y: h * 0.07)
            }

            VStack(spacing: em * 0.1) {
                Text("\(card.ovr)").font(F.display(em * 3.4)).foregroundStyle(tier == .max ? look.hi : look.ink)
                Text(position).font(F.display(em * 1.35)).foregroundStyle(look.ink)
                if tier == .max {
                    Text("MAX").font(F.display(em * 0.68)).foregroundStyle(.white)
                        .padding(.horizontal, em * 0.5).padding(.top, em * 0.2).padding(.bottom, em * 0.1)
                        .background(RoundedRectangle(cornerRadius: em * 0.4).fill(C.brand))
                }
                if let club {
                    ClubCrest(club: club, size: em * 2.1).padding(.top, em * 0.35)
                }
            }
            .frame(width: w * 0.25)
            .offset(x: w * 0.09, y: h * 0.11)

            Text(name.uppercased())
                .font(F.display(em * 1.62)).foregroundStyle(look.ink)
                .lineLimit(1).minimumScaleFactor(0.5)
                .frame(width: w * 0.84)
                .offset(x: w * 0.08, y: h * 0.596)

            Rectangle().fill(look.ink.opacity(0.28)).frame(width: w * 0.71, height: 1.6 * w / 300)
                .offset(x: w * 0.147, y: h * 0.657)

            HStack(spacing: 0) {
                ForEach(STATS, id: \.self) { s in
                    VStack(spacing: 0) {
                        Text(s).font(F.display(em * 0.56)).foregroundStyle(look.ink.opacity(0.72))
                        Text("\(card.stats[s] ?? 0)").font(F.display(em * 1.28))
                            .foregroundStyle(up.contains(s) ? look.hi : look.ink)
                            .scaleEffect(up.contains(s) ? 1.12 : 1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(width: w * 0.8)
            .offset(x: w * 0.1, y: h * 0.686)
            .animation(.spring(response: 0.35, dampingFraction: 0.5), value: up)

            Text("SM").font(F.display(em * 0.66)).kerning(em * 0.08).foregroundStyle(look.ink.opacity(0.55))
                .frame(width: w)
                .offset(y: h * 0.87)
        }
        .frame(width: w, height: h, alignment: .topLeading)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: false).delay(1)) { shine = true }
        }
    }
}

extension FutCard {
    /// The card for the current answers.
    init(answers a: Answers, width: CGFloat, up: Set<String> = [], club: Club? = nil) {
        let c = CardMath.card(a)
        self.init(card: c, name: a.cardName, position: a.position, tier: CardMath.tier(c.ovr), width: width, up: up, club: club)
    }
}
