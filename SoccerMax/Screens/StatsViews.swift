// STATS tab (notes/19 "Stats tab"): ONE hero ? the STREAK FIRE (2026-10-26, was the air ball: train 10 min at least
// once every 3 days or the 3D flame burns down and goes out; tap it, drag it; the day count sits above it and the clock
// ticks in the last 24 h; it never goes fully out) ? then the LEVEL BAR (LEVEL X + one bar), the RANK card on its own
// (tap ? all badges), THIS WEEK (VS. LAST WEEK swaps the bars to last week; "+X MIN" when you're ahead), all time. The calendar button in the
// header opens the year in squares.
import SwiftUI

struct StatsTab: View {
    @Environment(AppStore.self) private var store
    @State private var showYear = DebugRoute.parts[safe: 1] == "year"
    @State private var showBadges = DebugRoute.parts[safe: 1] == "badges"

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 26) {
                    TabHeader(title: "STATS") {
                        Button { showYear = true } label: { Image(systemName: "calendar").font(.system(size: 19, weight: .bold)) }
                            .buttonStyle(.gameRound(.charcoal, size: 46))
                            .accessibilityLabel("My year")
                    }
                    FireHero(air: store.air)
                    LevelBar(level: store.level)
                    Button { showBadges = true } label: { RankCard(badge: store.level.badge) }
                        .buttonStyle(.press)
                    WeekMinutes().id("week")
                    Totals(best: store.air.best).id("totals")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
            .onAppear {
                // DEBUG `stats:week:demo`, `stats:totals:demo` open scrolled to that section
                if let to = DebugRoute.parts[safe: 1], ["week", "totals"].contains(to) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { proxy.scrollTo(to, anchor: .top) }
                }
            }
            }
            .overlay(alignment: .top) { TopScrim() }
            .tabRoot("Stats")
            .page()
        }
        .sheet(isPresented: $showYear) { YearSheet() }
        .sheet(isPresented: $showBadges) { BadgeBook() }
    }
}

// MARK: - the hero: keep the fire burning

struct FireHero: View {
    let air: AirStreak
    @State private var info = false

    // 2026-11-08 (user): fire and streak side by side; the explainer sits behind an info button, not as plain text.
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            let a = air.air(tl.date)
            let left = air.deadline.map { $0.timeIntervalSince(tl.date) } ?? 0
            let urgent = air.alive && !air.keptToday && left < 86_400
            VStack(spacing: 10) {
                HStack(spacing: 4) {
                    StreakFire(heat: air.alive ? max(0.2, a) : 0.25, size: 170)
                        .padding(.vertical, -14)
                    VStack(alignment: .leading, spacing: 0) {
                        Disp("\(air.days)", size: 76, color: urgent ? C.gold : C.creme)
                            .contentTransition(.numericText())
                        HStack(spacing: 8) {
                            Text("DAY STREAK").font(F.display(24)).foregroundStyle(urgent ? C.gold : C.creme2)
                            Button { info = true } label: {
                                Image(systemName: "info.circle.fill").font(.system(size: 20, weight: .bold)).foregroundStyle(C.muted)
                            }
                            .buttonStyle(.press(.stud))
                            .accessibilityLabel("How the streak works")
                            .popover(isPresented: $info) { StreakInfo(best: air.best).presentationCompactAdaptation(.popover).presentationBackground(C.char850) }
                        }
                        .padding(.top, -8)
                    }
                    Spacer(minLength: 0)
                }
                status(left: left, urgent: urgent, date: tl.date)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func status(left: TimeInterval, urgent: Bool, date: Date) -> some View {
        if !air.alive {
            EmptyView()   // how it works lives behind the info button
        } else if air.keptToday, let d = air.deadline {
            Label("Lit today · burning until \(d.addingTimeInterval(-1).formatted(.dateTime.weekday(.wide)))", systemImage: "checkmark.seal.fill")
                .font(F.round(16, .bold)).foregroundStyle(C.brand)
        } else {
            HStack(spacing: 10) {
                Text(urgent ? "FIRE GOES OUT IN" : "BURNS FOR").font(F.round(13, .bold)).kerning(1.2)
                    .foregroundStyle(urgent ? C.gold : C.muted)
                Text(countdown(left, urgent: urgent))
                    .font(.system(size: 22, weight: .heavy, design: .monospaced)).monospacedDigit()
                    .foregroundStyle(urgent ? C.gold : C.creme)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy, value: Int(left))
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Capsule().fill(urgent ? C.goldInk.opacity(0.55) : C.char950))
            .overlay(Capsule().stroke(urgent ? C.gold.opacity(0.8) : C.charInk, lineWidth: 2))
            .scaleEffect(urgent && Int(date.timeIntervalSinceReferenceDate) % 2 == 0 ? 1.04 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.5), value: Int(date.timeIntervalSinceReferenceDate))
        }
    }

    /// "2D 14H 05M" while there's time; a ticking "13:42:09" in the last day.
    private func countdown(_ s: TimeInterval, urgent: Bool) -> String {
        let t = max(0, Int(s))
        let d = t / 86_400, h = t % 86_400 / 3600, m = t % 3600 / 60, sec = t % 60
        if urgent { return String(format: "%02d:%02d:%02d", h, m, sec) }
        return d > 0 ? String(format: "%dD %02dH %02dM", d, h, m) : String(format: "%dH %02dM", h, m)
    }
}

/// What the info button on the streak opens.
struct StreakInfo: View {
    let best: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Disp("YOUR STREAK", size: 22)
            row("flame.fill", "Train 10 minutes to light your fire.")
            row("calendar", "Train 10 minutes at least once every 3 days to keep it burning.")
            row("clock.fill", "Miss 3 days and the streak starts again.")
            row("trophy.fill", "Best streak: \(best) days.")
        }
        .padding(20)
        .frame(width: 300, alignment: .leading)
    }
    private func row(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.system(size: 15, weight: .bold)).foregroundStyle(C.gold).frame(width: 20)
            Text(text).font(F.round(15, .semibold)).foregroundStyle(C.creme).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Today's minutes toward the 10 that keep the fire lit.
struct FuelBar: View {
    let minutes: Double
    var body: some View {
        let p = min(1, minutes / AirStreak.keep)
        HStack(spacing: 10) {
            Image(systemName: "flame.fill").font(.system(size: 15, weight: .heavy)).foregroundStyle(C.gold)
            HStack(spacing: 4) {
                ForEach(0..<10, id: \.self) { i in
                    PanelMark(state: Double(i) < minutes ? .stitched : (Double(i) < minutes + 1 ? .next : .empty),
                              pent: i == 9, size: 17)
                }
            }
            Text("\(Int(min(minutes, 10)))/10 MIN TODAY").font(F.round(13, .bold)).foregroundStyle(p > 0 ? C.creme : C.muted)
        }
    }
}


// MARK: - level = badge (the bar itself is UI/LevelBar.swift)

/// Every level's badge in one sheet: earned ones in colour, yours highlighted, the rest still to sew on.
struct BadgeBook: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let lv = store.level.lv
        ScrollView {
            VStack(spacing: 18) {
                Disp("MY BADGES", size: 32)
                Text("Level up to sew on the next one. Finish a session: +50 XP, plus 10 XP for every minute you trained.")
                    .font(F.round(15, .semibold)).foregroundStyle(C.creme2).multilineTextAlignment(.center)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 4), spacing: 18) {
                    ForEach(LevelBadge.all) { b in
                        let got = b.lv <= lv
                        VStack(spacing: 6) {
                            BadgePatch(badge: b, earned: got, size: 70)
                                .scaleEffect(b.lv == min(lv, LevelBadge.all.count) ? 1.08 : 1)
                            Text(got ? b.name.uppercased() : "LV \(b.lv)")
                                .font(F.round(11, .bold)).kerning(0.4)
                                .foregroundStyle(b.lv == lv ? C.brand : got ? C.creme : C.muted)
                                .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.85)
                        }
                    }
                }
            }
            .padding(22)
        }
        .background(AppBackground())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            if lv > store.seenLevel { Haptics.play(.goal); store.seenLevel = lv } else { Haptics.play(.pop) }
        }
    }
}

extension Rarity {
    var tint: Color { [Color(hex: 0xE09A5C), Color(hex: 0xD3D8E0), C.gold, Color(hex: 0x9FE8FF)][rawValue] }
}

/// A badge as a sewn hexagon patch: earned = full colour (rarer every 5 levels; the last five shimmer like foil),
/// not yet = an empty sewing pattern with a faint icon.
struct BadgePatch: View {
    let badge: LevelBadge
    let earned: Bool
    var size: CGFloat = 70
    var fresh = false

    var body: some View {
        let shape = PanelShape()
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !(earned && (badge.rarity == .legend || fresh)))) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            ZStack {
                shape.fill(earned ? lip : C.charInk).offset(y: size * 0.06)
                if earned {
                    shape.fill(face(t))
                    shape.inset(by: size * 0.11).stroke(stitch.opacity(0.55), style: StrokeStyle(lineWidth: max(0.8, size * 0.02), dash: [2.5, 3.5]))
                    glyph.foregroundStyle(.white).shadow(color: ink, radius: 0, y: max(1, size * 0.028))
                    shape.fill(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center))
                        .mask(Rectangle().frame(height: size * 0.5).offset(y: -size * 0.25))
                    shape.stroke(ink, lineWidth: max(1.2, size * 0.035))
                } else {
                    shape.fill(C.char850)
                    shape.inset(by: size * 0.11).stroke(C.creme.opacity(0.16), style: StrokeStyle(lineWidth: 1.2, dash: [2.5, 3.5]))
                    glyph.foregroundStyle(C.creme.opacity(0.18))
                    shape.stroke(C.charInk, lineWidth: max(1.2, size * 0.035))
                }
            }
            .overlay(alignment: .topTrailing) {
                if fresh {
                    Text("NEW").font(F.display(12)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(C.brand).overlay(Capsule().stroke(C.brandInk, lineWidth: 1.5)))
                        .scaleEffect(1 + 0.08 * sin(t * 5))
                        .offset(x: 8, y: -4)
                }
            }
        }
        .frame(width: size, height: size)
    }

    private var glyph: some View {
        Group {
            if badge.word {
                Text(badge.icon.uppercased()).font(F.display(size * 0.38))
            } else {
                Image(systemName: badge.icon).font(.system(size: size * 0.33, weight: .heavy))
            }
        }
    }

    // bronze · silver · gold · diamond
    private var lip: Color { [Color(hex: 0x7A4A22), Color(hex: 0x6F7680), C.goldLip, Color(hex: 0x3E7C95)][badge.rarity.rawValue] }
    private var ink: Color { [Color(hex: 0x3D2410), Color(hex: 0x2E333A), C.goldInk, Color(hex: 0x163B4A)][badge.rarity.rawValue] }
    private var stitch: Color { .white }

    private func face(_ t: Double) -> AnyShapeStyle {
        switch badge.rarity {
        case .common: return AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xEBB27E), Color(hex: 0xCF8A4E), Color(hex: 0xA5652F)], startPoint: .top, endPoint: .bottom))
        case .rare: return AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xF4F6F9), Color(hex: 0xC9CED6), Color(hex: 0x9AA1AC)], startPoint: .top, endPoint: .bottom))
        case .epic: return AnyShapeStyle(LinearGradient(colors: [C.goldHi, C.gold, C.goldMid], startPoint: .top, endPoint: .bottom))
        case .legend:
            // diamond: icy blue-white sheen sweeping round
            return AnyShapeStyle(AngularGradient(colors: [Color(hex: 0x7FD6F5), .white, Color(hex: 0xC7B8FF), Color(hex: 0x9FE8FF),
                                                          Color(hex: 0xE6FAFF), Color(hex: 0x5BC2EA), Color(hex: 0x7FD6F5)],
                                                 center: .center, angle: .degrees(t * 60)))
        }
    }
}

// MARK: - this week (VS. LAST WEEK just swaps the bars to last week; "+X MIN" shows only when you're ahead)

struct WeekMinutes: View {
    @Environment(AppStore.self) private var store
    @State private var grow = 0.0
    @State private var last = DebugRoute.parts.contains("vs")

    // 2026-11-08 (user): no border, training minutes only (film dropped).
    var body: some View {
        let now = store.week(back: 0), prev = store.week(back: 1)
        let days = last ? prev : now
        let train = days.reduce(0) { $0 + $1.train }
        let top = max(30, days.map { $0.train }.max() ?? 0)
        let today = dateKey(Date())
        // ahead = this week so far vs last week's same days (Mon ? today)
        let upTo = now.firstIndex { dateKey($0.date) == today } ?? 6
        let gap = Int((soFar(now, upTo) - soFar(prev, upTo)).rounded())
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Disp(last ? "LAST WEEK" : "THIS WEEK", size: 24)
                    .lineLimit(1).minimumScaleFactor(0.75)
                    .contentTransition(.opacity)
                if !last && gap > 0 {
                    Text("+\(gap) MIN").font(F.display(13)).foregroundStyle(C.brandInk).lineLimit(1).fixedSize()
                        .padding(.horizontal, 8).frame(height: 24)
                        .background(Capsule().fill(C.brand))
                        .transition(.scale.combined(with: .opacity))
                }
                Spacer(minLength: 4)
                Button {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { last.toggle() }
                    grow = 0
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.78)) { grow = 1 }
                    Haptics.play(last ? .latch : .unlatch)
                } label: {
                    Text("VS. LAST WEEK").font(F.display(13)).lineLimit(1).fixedSize()
                        .foregroundStyle(last ? C.goldInk : C.creme2)
                        .padding(.horizontal, 12).frame(height: 34)
                        .background(Capsule().fill(last ? AnyShapeStyle(LinearGradient(colors: [C.goldHi, C.gold], startPoint: .top, endPoint: .bottom))
                                                        : AnyShapeStyle(C.char800)))
                        .background(Capsule().fill(last ? C.goldLip : C.charInk).offset(y: 3))
                        .overlay(Capsule().stroke(last ? C.goldInk : C.charInk, lineWidth: 2))
                }
                .buttonStyle(.press)
                .accessibilityAddTraits(last ? .isSelected : [])
            }
            HStack(alignment: .lastTextBaseline, spacing: 7) {
                Text(minText(train).uppercased()).font(F.display(17)).foregroundStyle(C.creme)
                Text("TRAINING").font(F.round(12, .bold)).kerning(1).foregroundStyle(C.muted)
            }
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(days, id: \.date) { d in
                    let isToday = dateKey(d.date) == today
                    VStack(spacing: 6) {
                        Text(d.train > 0 ? "\(Int(d.train.rounded()))" : " ").font(F.display(13)).foregroundStyle(C.creme2)
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(C.char950.opacity(0.6))
                            if d.train > 0 {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(LinearGradient(colors: [C.brandHi, C.brand, C.brandMid], startPoint: .top, endPoint: .bottom))
                                    .frame(height: 150 * d.train / top * grow)
                            }
                            if d.train >= AirStreak.keep {
                                Image(systemName: "flame.fill").font(.system(size: 10, weight: .heavy)).foregroundStyle(C.brandInk).padding(.bottom, 5)
                            }
                        }
                        .frame(height: 150)
                        .overlay(alignment: .top) {
                            if isToday { BallGlyph(size: 18).offset(y: -9 + 150 * (1 - min(1, d.train / top * grow))) }
                        }
                        Text(String(d.date.formatted(.dateTime.weekday(.narrow))))
                            .font(F.round(13, .bold)).foregroundStyle(isToday ? C.brand : C.muted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) { grow = 1 } }
    }

    private func soFar(_ w: [(date: Date, train: Double, film: Double)], _ upTo: Int) -> Double {
        var m = 0.0
        for i in 0...upTo { m += w[i].train }
        return m
    }
}

private struct Legend: View {
    let color: Color
    let value: String
    let label: String
    var body: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 12, height: 12)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(C.charInk, lineWidth: 1.5))
            Text(value.uppercased()).font(F.display(17)).foregroundStyle(C.creme)
            Text(label).font(F.round(12, .bold)).kerning(1).foregroundStyle(C.muted)
        }
    }
}

// MARK: - all time

struct Totals: View {
    let best: Int
    @Environment(AppStore.self) private var store

    // 2026-11-08 (user): only sessions, streak and training time; no borders.
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Disp("ALL TIME", size: 24)
            HStack(alignment: .top, spacing: 10) {
                Big(value: "\(store.completions.count)", label: "SESSIONS", color: C.creme)
                Big(value: "\(best) d", label: "BEST STREAK", color: C.creme)
                Big(value: minText(store.totalTrained), label: "TRAINED", color: C.brand)
            }
        }
    }

    private struct Big: View {
        let value: String
        let label: String
        let color: Color
        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Disp(value.uppercased(), size: 28, color: color).lineLimit(1).minimumScaleFactor(0.6)
                Text(label).font(F.round(12, .bold)).kerning(1.2).foregroundStyle(C.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - the year in squares

struct YearSheet: View {
    @Environment(AppStore.self) private var store
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var picked: Date?

    var body: some View {
        let cal = Calendar.current
        let keys = store.trained.keys.filter { $0.hasPrefix("\(year)") }
        let mins = keys.reduce(0) { $0 + (store.trained[$1] ?? 0) }
        let kept = keys.filter { (store.trained[$0] ?? 0) >= AirStreak.keep }.count
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button { year -= 1; picked = nil } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.gameRound(.charcoal, size: 38))
                    Spacer()
                    Disp(String(year), size: 38)
                    Spacer()
                    Button { year += 1; picked = nil } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(.gameRound(.charcoal, size: 38))
                        .disabled(year >= cal.component(.year, from: Date()))
                }
                Group {
                    if let p = picked {
                        let k = dateKey(p)
                        Text("\(p.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())) · \(minText(store.trained[k] ?? 0)) training · \(minText(store.film[k] ?? 0)) film")
                    } else {
                        Text("\(minText(mins)) trained · \(kept) days pumped")
                    }
                }
                .font(F.round(16, .bold)).foregroundStyle(C.creme2).frame(maxWidth: .infinity)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: 3), alignment: .leading, spacing: 18) {
                    ForEach(1...12, id: \.self) { m in month(m) }
                }
                HStack(spacing: 14) {
                    key(C.char800, "None")
                    key(C.brand.opacity(0.35), "Some")
                    key(C.brand, "10+ min")
                    key(C.gold, "Film")
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            }
            .padding(20)
        }
        .background(AppBackground())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func month(_ m: Int) -> some View {
        let cal = Calendar.current
        let first = cal.date(from: DateComponents(year: year, month: m, day: 1))!
        let count = cal.range(of: .day, in: .month, for: first)!.count
        let lead = (cal.component(.weekday, from: first) + 5) % 7      // Mon = 0
        let today = cal.startOfDay(for: Date())
        return VStack(alignment: .leading, spacing: 5) {
            Text(first.formatted(.dateTime.month(.abbreviated)).uppercased()).font(F.round(12, .bold)).kerning(1).foregroundStyle(C.muted)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2.5), count: 7), spacing: 2.5) {
                ForEach(0..<(lead + count), id: \.self) { i in
                    if i < lead {
                        Color.clear.aspectRatio(1, contentMode: .fit)
                    } else {
                        let d = cal.date(from: DateComponents(year: year, month: m, day: i - lead + 1))!
                        let k = dateKey(d)
                        let t = store.trained[k] ?? 0, f = store.film[k] ?? 0
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(d > today ? C.char850 : t >= AirStreak.keep ? C.brand : t > 0 ? C.brand.opacity(0.35) : f > 0 ? C.gold.opacity(0.8) : C.char700)
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(RoundedRectangle(cornerRadius: 2).stroke(d == today ? C.creme : picked == d ? C.gold : .clear, lineWidth: 1.5))
                            .overlay(alignment: .topTrailing) {
                                if t > 0 && f > 0 { Circle().fill(C.gold).frame(width: 3, height: 3).padding(1) }
                            }
                            .onTapGesture { if d <= today { picked = d; Haptics.play(.stud) } }
                    }
                }
            }
        }
    }

    private func key(_ c: Color, _ s: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 11, height: 11)
            Text(s).font(F.round(12, .bold)).foregroundStyle(C.muted)
        }
    }
}

// MARK: - Profile stats v3 (2026-11-08, user): range dropdown graph, all levels, one all-time stat, month calendar

/// A Liquid Glass capsule (iOS 26), frosted material before that.
struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content.background(.ultraThinMaterial, in: Capsule())
        }
    }
}

/// The dropdown's label: one glass button, the choice + a chevron.
struct GlassMenuLabel: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Text(text).font(F.display(18)).foregroundStyle(C.creme)
            Image(systemName: "chevron.down").font(.system(size: 13, weight: .heavy)).foregroundStyle(C.creme2)
        }
        .padding(.horizontal, 16).frame(height: 40)
        .modifier(GlassCapsule())
        .contentShape(Capsule())
    }
}

enum ChartRange: String, CaseIterable, Identifiable {
    case thisWeek = "THIS WEEK", lastWeek = "LAST WEEK", thisMonth = "THIS MONTH", lastMonth = "LAST MONTH"
    var id: String { rawValue }
    var isMonth: Bool { self == .thisMonth || self == .lastMonth }
    /// "This week"
    var title: String { let s = rawValue.lowercased(); return s.prefix(1).uppercased() + s.dropFirst() }
}

/// Training minutes only, for the picked time frame. No card, no border.
/// v2 (2026-11-08, user): press-and-drag across the bars (a haptic tick per bar) to read each day; the picked day
/// lists its sessions, tap one ? it opens in the Sessions tab. Longer days = darker green, shorter = lighter.
struct TrainingChart: View {
    @Environment(AppStore.self) private var store
    @State private var range: ChartRange = .thisWeek
    @State private var grow = 0.0
    @State private var sel: Int?

    var body: some View {
        let days = days(range)
        let total = days.reduce(0) { $0 + $1.train }
        let top = max(30, days.map(\.train).max() ?? 0)
        let today = dateKey(Date())
        let gap: CGFloat = range.isMonth ? 3 : 10
        let h: CGFloat = 150
        let picked = sel.flatMap { days.indices.contains($0) ? days[$0] : nil }
        let sub: String = picked.map { $0.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) + " \u{00B7} " + minText($0.train) }
            ?? (minText(total) + " in total")
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                // the total, or the day under your finger
                VStack(alignment: .leading, spacing: 2) {
                    Text("Training").font(.system(size: 18, weight: .bold)).foregroundStyle(C.creme)
                    Text(sub)
                        .font(F.round(13, .semibold)).foregroundStyle(picked == nil ? C.muted : C.brandHi)
                        .contentTransition(.numericText())
                }
                .animation(.snappy(duration: 0.18), value: sel)
                Spacer(minLength: 8)
                Menu {
                    Picker("Time frame", selection: $range) {
                        ForEach(ChartRange.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(range.title).font(F.round(14, .semibold)).foregroundStyle(C.creme)
                        Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).foregroundStyle(C.muted)
                    }
                    .padding(.horizontal, 12).frame(height: 34)
                    .background(Capsule().fill(C.char700))
                    .contentShape(Capsule())
                }
                .menuStyle(.button).buttonStyle(.plain)
            }
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(Array(days.enumerated()), id: \.element.date) { i, d in
                    let isToday = dateKey(d.date) == today
                    let on = sel == nil || sel == i
                    let r: CGFloat = range.isMonth ? 3 : 9
                    VStack(spacing: 6) {
                        if !range.isMonth {
                            Text(d.train > 0 ? "\(Int(d.train.rounded()))" : " ").font(F.round(12, .semibold))
                                .foregroundStyle(sel == i ? C.creme : C.creme2)
                        }
                        ZStack(alignment: .bottom) {
                            Color.clear   // no empty track behind the bar (2026-11-08)
                            if d.train > 0 {
                                RoundedRectangle(cornerRadius: r, style: .continuous)
                                    .fill(Self.shade(d.train / top))
                                    .overlay(RoundedRectangle(cornerRadius: r, style: .continuous)
                                        .fill(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center)))
                                    .frame(height: max(range.isMonth ? 3 : 6, h * d.train / top * grow))
                            }
                            if !range.isMonth && d.train >= AirStreak.keep {
                                Image(systemName: "flame.fill").font(.system(size: 10, weight: .heavy))
                                    .foregroundStyle(.white.opacity(0.85)).padding(.bottom, 5)
                            }
                        }
                        .frame(height: h)
                        .opacity(on ? 1 : 0.32)
                        .scaleEffect(x: sel == i ? 1.08 : 1, y: 1, anchor: .bottom)
                        .overlay(alignment: .top) {
                            if isToday && !range.isMonth && sel == nil && total > 0 { BallGlyph(size: 18).offset(y: -9 + h * (1 - min(1, d.train / top * grow))) }
                        }
                        Text(label(d.date, i))
                            .font(F.round(range.isMonth ? 10 : 13, .bold))
                            .foregroundStyle(sel == i ? C.creme : isToday ? C.brand : C.muted)
                            .lineLimit(1).fixedSize()
                            .frame(height: 16)
                            .opacity(total > 0 ? 1 : 0)   // nothing logged ? no labels under the empty graph
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .animation(.snappy(duration: 0.18), value: sel)
            // nothing trained in this time frame (2026-11-08, user)
            .overlay {
                if total == 0 {
                    VStack(spacing: 8) {
                        Image(systemName: "soccerball").font(.system(size: 26, weight: .bold)).foregroundStyle(C.muted.opacity(0.6))
                        Text("Nothing logged \(range.rawValue.lowercased())").font(F.round(15, .semibold)).foregroundStyle(C.muted)
                    }
                    .padding(.bottom, 24)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
            .overlay {
                if total > 0 {
                GeometryReader { g in
                    Color.clear.contentShape(Rectangle())
                        // hold, then drag: a quick swipe still scrolls the page
                        .gesture(LongPressGesture(minimumDuration: 0.12)
                            .sequenced(before: DragGesture(minimumDistance: 0))
                            .onChanged { v in
                                if case .second(true, let d?) = v { pick(d.location.x, g.size.width, days.count) }
                            })
                        .simultaneousGesture(SpatialTapGesture().onEnded { t in
                            let i = index(t.location.x, g.size.width, days.count)
                            sel = sel == i ? nil : i
                        })
                }
                }
            }
            .sensoryFeedback(.selection, trigger: sel)

            if let i = sel, let d = picked { DaySessions(date: d.date, minutes: d.train).id(i) }
        }
        .gameCard(padding: 16, radius: 18)   // a card like the others on Profile (2026-11-13)
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) { grow = 1 } }
        .onChange(of: range) { _, _ in
            sel = nil
            grow = 0
            withAnimation(.spring(response: 0.6, dampingFraction: 0.78)) { grow = 1 }
            Haptics.play(.latch)
        }
    }

    private func index(_ x: CGFloat, _ w: CGFloat, _ n: Int) -> Int {
        min(n - 1, max(0, Int(x / max(1, w) * CGFloat(n))))
    }
    private func pick(_ x: CGFloat, _ w: CGFloat, _ n: Int) {
        let i = index(x, w, n)
        if sel != i { sel = i }
    }

    /// Short days light blue, long days deep blue (0?1 of the busiest day in view).
    static func shade(_ f: Double) -> Color {
        let t = min(1, max(0, f))
        let lo = (r: 0.66, g: 0.82, b: 1.00)   // #A8D1FF
        let hi = (r: 0.04, g: 0.25, b: 0.64)   // #0A40A3
        return Color(red: lo.r + (hi.r - lo.r) * t, green: lo.g + (hi.g - lo.g) * t, blue: lo.b + (hi.b - lo.b) * t)
    }

    /// Week = the day's letter; month = the date on the 1st and every 7th day after, nothing in between.
    private func label(_ d: Date, _ i: Int) -> String {
        if !range.isMonth { return String(d.formatted(.dateTime.weekday(.narrow))) }
        let day = Calendar.current.component(.day, from: d)
        return (day - 1) % 7 == 0 ? "\(day)" : " "
    }

    private func days(_ r: ChartRange) -> [(date: Date, train: Double)] {
        switch r {
        case .thisWeek: return store.week(back: 0).map { ($0.date, $0.train) }
        case .lastWeek: return store.week(back: 1).map { ($0.date, $0.train) }
        case .thisMonth, .lastMonth:
            let cal = Calendar.current
            let start = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
            let first = r == .thisMonth ? start : cal.date(byAdding: .month, value: -1, to: start)!
            let n = cal.range(of: .day, in: .month, for: first)!.count
            return (0..<n).map { i in let d = addDays(first, i); return (d, store.trained[dateKey(d)] ?? 0) }
        }
    }
}

/// The picked day's sessions; tap one ? its page, back returns to the graph.
private struct DaySessions: View {
    let date: Date
    let minutes: Double
    @Environment(AppStore.self) private var store

    var body: some View {
        let list = store.completions.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }.sorted { $0.date < $1.date }
        VStack(spacing: 8) {
            if list.isEmpty {
                Text(minutes > 0 ? "\(minText(minutes)) trained · no session logged" : "Rest day")
                    .font(F.round(14, .semibold)).foregroundStyle(C.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            }
            ForEach(list, id: \.self) { c in
                // opens on Profile's own stack, so back returns to the graph (2026-11-08)
                NavigationLink(value: c) {
                    HStack(spacing: 12) {
                        Image(systemName: TrainingArea.of(c.area)?.icon ?? "soccerball")
                            .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(TrainingChart.shade(Double(c.minutes) / 60)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.name).font(F.round(16, .bold)).foregroundStyle(C.creme).lineLimit(1)
                            Text(c.date.formatted(date: .omitted, time: .shortened)).font(F.round(13, .semibold)).foregroundStyle(C.muted)
                        }
                        Spacer(minLength: 8)
                        Text(minText(Double(c.minutes)).uppercased()).font(F.display(17)).foregroundStyle(C.creme)
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .heavy)).foregroundStyle(C.muted)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.press)
                .simultaneousGesture(TapGesture().onEnded { Haptics.play(.pop) })
                .accessibilityLabel("\(c.name), \(c.minutes) minutes. Open session")
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

/// Every level there is (levels go on forever; the list shows well past yours).
struct LevelsSheet: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        let me = store.level
        let last = max(30, me.lv + 10)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Disp("ALL RANKS", size: 32).frame(maxWidth: .infinity)
                    Text("Earn XP by ticking off drills (+20), finishing today's session (+50), film reviews (+40), runs and logging food.")
                        .font(F.round(15, .semibold)).foregroundStyle(C.creme2).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity).padding(.bottom, 8)
                    ForEach(1...last, id: \.self) { l in
                        let done = l < me.lv, now = l == me.lv
                        HStack(spacing: 14) {
                            ZStack {
                                Circle().fill(done ? C.brand : now ? C.gold : C.char800)
                                if done { Image(systemName: "checkmark").font(.system(size: 14, weight: .heavy)).foregroundStyle(C.brandInk) }
                                else { Text("\(l)").font(F.display(15)).foregroundStyle(now ? C.goldInk : C.muted) }
                            }
                            .frame(width: 34, height: 34)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(LevelBadge.of(l).name.uppercased()).font(F.display(19))
                                    .foregroundStyle(done || now ? (LevelBadge.of(l).rarity == .common ? C.creme : LevelBadge.of(l).rarity.tint) : C.muted)
                                if now { XPBar(progress: me.progress, height: 10) }
                            }
                            Spacer(minLength: 8)
                            Text(now ? "\(me.into.formatted()) / \(me.need.formatted()) XP" : "\(start(l).formatted()) XP")
                                .font(F.round(13, .bold)).monospacedDigit().foregroundStyle(now ? C.gold : C.muted)
                        }
                        .padding(.vertical, 8)
                        .id(l)
                    }
                }
                .padding(22)
            }
            .onAppear { proxy.scrollTo(max(1, me.lv - 2), anchor: .top) }
        }
        .background(AppBackground())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
    /// Total XP it takes to reach level l.
    private func start(_ l: Int) -> Int { (1..<max(1, l)).reduce(0) { $0 + Level.need($1) } }
}

/// ALL TIME + this month, side by side (2026-11-08, user: "put the see year preview next to the all time stats,
/// small enough to fit side by side and look ultra nice"). Two equal soft tiles, no strokes.
struct StatsPair: View {
    let best: Int
    var body: some View {
        // spacing v2 (2026-11-08, user): columns sit on the graph's edges, a wide gutter between them,
        // clear air above (the graph's labels) ? both headers on one line, content under each.
        HStack(alignment: .top, spacing: 28) {
            AllTimeStat(best: best)
            MonthPreview()
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 18)
    }
}

/// The shared tile look: a soft filled surface with a faint top light. No border.
private struct SoftTile: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // no inset: the columns line up with the graph above; no fill, no stroke ? seamless with the page (2026-11-08)
    }
}

/// ALL TIME: one stat at a time, big and centred, picked from a glass dropdown.
struct AllTimeStat: View {
    let best: Int
    @Environment(AppStore.self) private var store
    enum Kind: String, CaseIterable, Identifiable {
        case sessions = "SESSIONS", streak = "BEST STREAK", trained = "TIME"
        var id: String { rawValue }
        var menu: String { self == .trained ? "Training time" : rawValue.capitalized }
    }
    @State private var kind: Kind = .sessions

    var body: some View {
        VStack(spacing: 0) {
            Menu {
                Picker("Stat", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.menu).tag($0) }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(kind.rawValue).font(F.display(14)).foregroundStyle(C.creme).lineLimit(1).fixedSize()
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .heavy)).foregroundStyle(C.creme2)
                }
                .padding(.horizontal, 12).frame(height: 32)
                .modifier(GlassCapsule())
                .contentShape(Capsule())
            }
            .menuStyle(.button).buttonStyle(.plain)
            Spacer(minLength: 14)   // number + label sit centred under the button, level with the calendar
            Disp(value.uppercased(), size: 46, color: C.brand)
                .lineLimit(1).minimumScaleFactor(0.45)
                .shadow(color: C.brand.opacity(0.25), radius: 8)
                .contentTransition(.numericText())
                .animation(.snappy, value: kind)
            Text("ALL TIME").font(F.round(11, .heavy)).kerning(1.6).foregroundStyle(C.muted)
                .padding(.top, 2)
            Spacer(minLength: 14)
        }
        .modifier(SoftTile())
        .onChange(of: kind) { _, _ in Haptics.play(.latch) }
    }

    private var value: String {
        switch kind {
        case .sessions: return "\(store.completions.count)"
        case .streak: return "\(best) d"
        case .trained: return minText(store.totalTrained)
        }
    }
}

/// This month's squares, small; tap ? the whole year.
struct MonthPreview: View {
    @Environment(AppStore.self) private var store
    @State private var open = false

    var body: some View {
        let cal = Calendar.current
        let first = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
        let count = cal.range(of: .day, in: .month, for: first)!.count
        let lead = (cal.component(.weekday, from: first) + 5) % 7      // Mon = 0
        let today = cal.startOfDay(for: Date())
        Button { open = true; Haptics.play(.pop) } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 4) {
                    Text(first.formatted(.dateTime.month(.wide)).uppercased()).font(F.display(14)).foregroundStyle(C.creme)
                    Spacer(minLength: 2)
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .heavy)).foregroundStyle(C.muted)
                }
                .frame(height: 32)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 3) {
                    ForEach(0..<(lead + count), id: \.self) { i in
                        if i < lead {
                            Color.clear.aspectRatio(1, contentMode: .fit)
                        } else {
                            let d = cal.date(byAdding: .day, value: i - lead, to: first)!
                            let t = store.trained[dateKey(d)] ?? 0
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(d > today ? C.char950.opacity(0.5) : t > 0 ? TrainingChart.shade(t / 60) : C.char700.opacity(0.7))
                                .aspectRatio(1, contentMode: .fit)
                                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(d == today ? C.creme : .clear, lineWidth: 1.5))
                        }
                    }
                }
            }
            .modifier(SoftTile())
        }
        .buttonStyle(.press)
        .accessibilityLabel("This month's training. Show the whole year")
        .sheet(isPresented: $open) { YearSheet() }
    }
}
