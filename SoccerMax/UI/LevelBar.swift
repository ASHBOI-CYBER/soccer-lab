// LEVEL BAR + RANK (2026-10-26 v2). v1 piled chips, stripes, ticks, XP-to-go and the rank into one card; the user:
// "make it more seamless and separate the rank from it to be its own thing? less text around the level bar, just the
// level bar, less text around the rank, just the rank. Isolate these components so they shine."
//   LevelBar = LEVEL X + XP numbers on one line, then one smooth bar (soft shine sweeps it). Nothing else.
//   RankCard = the badge you wear + its name (coloured by rarity). Tap ? every badge.
// Used on Stats and Profile (compact). A streak strip for Profile lives here too.
import SwiftUI

struct LevelBar: View {
    let level: Level
    var compact = false
    var showsMore = false
    @State private var fill = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 12) {
            HStack(alignment: .lastTextBaseline) {
                Disp("LEVEL \(level.lv)", size: compact ? 24 : 26)
                    .contentTransition(.numericText())
                Spacer(minLength: 8)
                Text("\(level.into.formatted()) / \(level.need.formatted()) XP")
                    .font(F.round(14, .bold)).monospacedDigit().foregroundStyle(C.muted)
                if showsMore { Image(systemName: "chevron.right").font(.system(size: 13, weight: .heavy)).foregroundStyle(C.muted) }
            }
            XPBar(progress: fill, height: compact ? 18 : 22)
                .padding(.top, -4)     // the display font's tall line box
        }   // no card border (2026-11-08, user)
        .onAppear { withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) { fill = level.progress } }
        .onChange(of: level.into) { _, _ in withAnimation(.spring) { fill = level.progress } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Level \(level.lv), \(level.into) of \(level.need) XP")
    }
}

/// One smooth bar: a sunk track, a green fill with a top highlight, a soft shine gliding across every few seconds.
struct XPBar: View {
    let progress: Double
    var height: CGFloat = 22

    var body: some View {
        GeometryReader { g in
            let fw = max(height, g.size.width * progress)
            TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                let sweep = (t / 3.2).truncatingRemainder(dividingBy: 1)       // 0?1 every 3.2 s
                ZStack(alignment: .leading) {
                    Capsule().fill(C.char950)
                        .overlay(Capsule().stroke(C.charInk, lineWidth: 2))
                    ZStack {
                        LinearGradient(colors: [C.brandHi, C.brand, C.brandMid], startPoint: .top, endPoint: .bottom)
                        Capsule().fill(.white.opacity(0.32))
                            .frame(height: height * 0.22)
                            .padding(.horizontal, height * 0.45)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .padding(.top, height * 0.16)
                        LinearGradient(colors: [.clear, .white.opacity(0.4), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: height * 3)
                            .offset(x: (fw + height * 6) * sweep - fw / 2 - height * 3)
                    }
                    .frame(width: fw)
                    .clipShape(Capsule())
                    .shadow(color: C.brand.opacity(0.35), radius: 6)
                }
            }
        }
        .frame(height: height)
    }
}

/// Your rank, on its own: the badge you wear + its name. Nothing else.
struct RankCard: View {
    let badge: LevelBadge
    var compact = false
    @Environment(AppStore.self) private var store

    var body: some View {
        HStack(spacing: 18) {
            BadgePatch(badge: badge, earned: true, size: compact ? 62 : 76, fresh: store.level.lv > store.seenLevel)
            Disp(badge.name.uppercased(), size: compact ? 26 : 30, color: badge.rarity == .common ? C.creme : badge.rarity.tint)
                .lineLimit(2).minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        // no card border (2026-11-08, user)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rank: \(badge.name). Show all badges")
    }
}

/// Profile's streak: a small live fire you can poke + the day count.
struct StreakStrip: View {
    let air: AirStreak
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { tl in
            HStack(spacing: 6) {
                StreakFire(heat: air.alive ? max(0.75, air.air(tl.date)) : 0.3, size: 108)
                    .padding(.vertical, -16).padding(.leading, -8)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Disp("\(air.days)", size: 46)
                        Disp("DAY STREAK", size: 20, color: C.creme2)
                    }
                    Text(line(tl.date)).font(F.round(14, .semibold)).foregroundStyle(air.alive ? C.creme2 : C.muted)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .gameCard(padding: 12)
        .stitched(22)
    }

    private func line(_ now: Date) -> String {
        if !air.alive { return "Train 10 min to grow your fire." }
        if air.keptToday { return "Lit today · best \(air.best) days" }
        let h = Int((air.deadline?.timeIntervalSince(now) ?? 0) / 3600)
        return h < 24 ? "Goes out in \(h) h — train 10 min" : "Burns \(h / 24) more days · best \(air.best)"
    }
}

// MARK: - Profile: STREAK · LEVEL · RANK in one row (2026-10-26, user: "put the streak, rank, and level all in one
// horizontal row"). Three matching tiles, same height; each shows one thing big. Tap level or rank ? every badge.

struct ProgressRow: View {
    let air: AirStreak
    let level: Level
    var onBadges: () -> Void = {}
    @Environment(AppStore.self) private var store
    @State private var fill = 0.0

    var body: some View {
        HStack(spacing: 10) {
            // STREAK: the live fire + day count
            tile {
                TimelineView(.periodic(from: .now, by: 60)) { tl in
                    StreakFire(heat: air.alive ? max(0.75, air.air(tl.date)) : 0.3, size: 92)
                        .frame(width: 92, height: 92)
                        .padding(.top, -26).padding(.bottom, -8)
                }
                Disp("\(air.days)", size: 30)
                caption("DAY STREAK")
            }
            // LEVEL: the number + a mini bar
            Button(action: onBadges) {
                tile {
                    caption("LEVEL").padding(.top, 4)
                    Disp("\(level.lv)", size: 44).padding(.bottom, -6)
                    XPBar(progress: fill, height: 10)
                        .padding(.horizontal, 4)
                        .padding(.top, 6)
                    Text("\(level.into.formatted())/\(level.need.formatted())")
                        .font(F.round(11, .bold)).monospacedDigit().foregroundStyle(C.muted)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            .buttonStyle(.press)
            // RANK: the badge + its name
            Button(action: onBadges) {
                tile {
                    BadgePatch(badge: level.badge, earned: true, size: 58, fresh: level.lv > store.seenLevel)
                        .padding(.top, 2)
                    Disp(level.badge.name.uppercased(), size: 15,
                         color: level.badge.rarity == .common ? C.creme : level.badge.rarity.tint)
                        .lineLimit(2).minimumScaleFactor(0.7).multilineTextAlignment(.center)
                        .padding(.top, 6)
                }
            }
            .buttonStyle(.press)
        }
        .onAppear { withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) { fill = level.progress } }
        .onChange(of: level.into) { _, _ in withAnimation(.spring) { fill = level.progress } }
    }

    private func tile<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        VStack(spacing: 2) { content() }
            .frame(maxWidth: .infinity, minHeight: 138)
            .padding(.horizontal, 8).padding(.vertical, 10)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))   // the tile is the fire's box
            .gameCard(padding: 0, radius: 20)
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(C.line, lineWidth: 1))   // border on top of the glow
    }

    private func caption(_ s: String) -> some View {
        Text(s).font(F.round(11, .heavy)).kerning(1).foregroundStyle(C.muted).lineLimit(1).minimumScaleFactor(0.8)
    }
}
