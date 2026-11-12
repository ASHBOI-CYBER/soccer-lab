// PROFILE extras (SOCCER LAB, 2026-11-13): the skill map (a radar or a ratings list of the six ratings the app already
// keeps, AppStore.spider), career totals, and achievements. Everything is worked out from what is on the phone:
// the training log, runs, film reviews and the food log. Nothing here is compared with other players.
import SwiftUI

// MARK: - skill map

struct SkillMapCard: View {
    @Environment(AppStore.self) private var store
    @State private var mode = "Radar"

    var body: some View {
        let sp = store.spider
        let overall = STATS.reduce(0) { $0 + (sp.now[$1] ?? 0) } / max(1, STATS.count)
        LabPanel(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "hexagon.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(C.brand)
                    Text("SKILL MAP").font(F.round(12, .bold)).kerning(1.6).foregroundStyle(C.brandHi)
                    Spacer()
                    HStack(spacing: 2) {
                        ForEach(["Radar", "Ratings"], id: \.self) { m in
                            Button { mode = m; Haptics.play(.stud) } label: {
                                Text(m.uppercased()).font(F.round(11, .bold)).kerning(1)
                                    .foregroundStyle(mode == m ? Color.white : C.muted)
                                    .padding(.horizontal, 12).frame(height: 30)
                                    .background(Capsule().fill(mode == m ? C.brand : Color.clear))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(mode == m ? .isSelected : [])
                        }
                    }
                    .padding(3)
                    .background(Capsule().fill(C.char700))
                }
                if mode == "Radar" {
                    SkillRadar(now: sp.now, start: sp.start)
                        .frame(height: 250)
                        .frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: 12) {
                        ForEach(STATS, id: \.self) { k in
                            let v = sp.now[k] ?? 0
                            let gain = sp.gain[k] ?? 0
                            VStack(spacing: 6) {
                                HStack {
                                    Text(STAT_NAME[k] ?? k).font(F.round(15, .semibold)).foregroundStyle(C.creme)
                                    Spacer()
                                    if gain > 0 { Text("+\(gain)").font(F.round(12, .bold)).foregroundStyle(labSkillColor("Stretching")) }
                                    Text("\(v)").font(.system(size: 17, weight: .bold)).foregroundStyle(C.creme).monospacedDigit()
                                }
                                LabBar(value: Double(v - 40), goal: 59)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(STAT_NAME[k] ?? k): \(v)\(gain > 0 ? ", up \(gain) from training" : "")")
                        }
                    }
                }
                HStack {
                    Text("Overall").font(F.round(13, .semibold)).foregroundStyle(C.muted)
                    Text("\(overall)").font(.system(size: 17, weight: .bold)).foregroundStyle(C.creme)
                    Spacer()
                    Text(sp.totalGain > 0 ? "+\(sp.totalGain) from training" : "Starts from your answers. Grows as you train.")
                        .font(F.round(12, .medium)).foregroundStyle(C.muted)
                }
            }
        }
    }
}

/// Six ratings on a hexagon: a faint outline for where the player started, a filled blue shape for now.
struct SkillRadar: View {
    let now: [String: Int]
    let start: [String: Int]

    var body: some View {
        GeometryReader { g in
            let c = CGPoint(x: g.size.width / 2, y: g.size.height / 2)
            let r = min(g.size.width, g.size.height) / 2 - 34
            ZStack {
                ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { f in
                    polygon(c, r * f, [Double](repeating: 1, count: STATS.count)).stroke(C.line, lineWidth: 1)
                }
                Path { p in
                    for i in STATS.indices { p.move(to: c); p.addLine(to: point(c, r, i, 1)) }
                }
                .stroke(C.line, lineWidth: 1)
                polygon(c, r, STATS.map { level(start[$0] ?? 40) })
                    .stroke(C.creme2.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                polygon(c, r, STATS.map { level(now[$0] ?? 40) })
                    .fill(C.brand.opacity(0.22))
                polygon(c, r, STATS.map { level(now[$0] ?? 40) })
                    .stroke(C.brand, lineWidth: 2)
                    .shadow(color: C.brand.opacity(0.8), radius: 6)
                ForEach(Array(STATS.enumerated()), id: \.offset) { i, k in
                    Circle().fill(C.brandHi).frame(width: 6, height: 6)
                        .position(point(c, r, i, level(now[k] ?? 40)))
                    VStack(spacing: 1) {
                        Text(k).font(F.round(10, .bold)).kerning(1.2).foregroundStyle(C.muted)
                        Text("\(now[k] ?? 0)").font(.system(size: 15, weight: .bold)).foregroundStyle(C.creme)
                    }
                    .position(point(c, r + 22, i, 1))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(STATS.map { "\(STAT_NAME[$0] ?? $0) \(now[$0] ?? 0)" }.joined(separator: ", "))
    }

    /// 40 is the centre of the chart and 99 the edge, with a little kept so a low rating still shows.
    private func level(_ v: Int) -> Double { 0.12 + 0.88 * min(1, max(0, Double(v - 40) / 59)) }

    private func point(_ c: CGPoint, _ r: CGFloat, _ i: Int, _ f: Double) -> CGPoint {
        let a = -Double.pi / 2 + 2 * Double.pi * Double(i) / Double(STATS.count)
        return CGPoint(x: c.x + CGFloat(cos(a)) * r * CGFloat(f), y: c.y + CGFloat(sin(a)) * r * CGFloat(f))
    }

    private func polygon(_ c: CGPoint, _ r: CGFloat, _ f: [Double]) -> Path {
        var p = Path()
        for i in f.indices {
            let pt = point(c, r, i, f[i])
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - career

/// Everything the player has done since they started, counted from the phone's own records.
struct CareerNumbers {
    let minutes: Int
    let days: Int
    let sessions: Int
    let sets: Int
    let bestStreak: Int
    let km: Double
    let runs: Int
    let reviews: Int
    let foodDays: Int
    let fixesCleared: Int

    @MainActor init(_ store: AppStore) {
        let lab = Lab.shared
        minutes = Int(store.trained.values.reduce(0, +).rounded())
        days = store.trained.values.filter { $0 >= 1 }.count
        sessions = store.completions.count
        sets = store.log.values.reduce(0) { $0 + $1.values.reduce(0, +) }
        bestStreak = max(store.air.best, store.air.days)
        km = lab.runs.reduce(0) { $0 + $1.km }
        runs = lab.runs.count
        reviews = lab.reviews.count
        foodDays = lab.fuel.values.filter { !$0.entries.isEmpty }.count
        // a review's drills that are no longer on the Fix List have been worked through
        let onList = Set(lab.fixList)
        fixesCleared = Set(lab.reviews.flatMap(\.drills)).subtracting(onList).count
    }
}

struct CareerCard: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let n = CareerNumbers(store)
        LabPanel(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 13, weight: .bold)).foregroundStyle(C.brand)
                    Text("CAREER").font(F.round(12, .bold)).kerning(1.6).foregroundStyle(C.brandHi)
                    Spacer()
                    Text("ALL TIME").font(F.round(11, .bold)).kerning(1.2).foregroundStyle(C.muted)
                }
                HStack(spacing: 0) {
                    stat("\(n.minutes)", "Minutes", "clock.fill", C.brandHi)
                    stat("\(n.days)", "Days trained", "calendar", labSkillColor("Stretching"))
                    stat("\(n.sets)", "Sets done", "checkmark.circle.fill", C.gold)
                }
                Rectangle().fill(C.line).frame(height: 1)
                HStack(spacing: 0) {
                    stat(String(format: "%.1f", n.km), "Km run", "figure.run", labSkillColor("Runs"))
                    stat("\(n.reviews)", "Film reviews", "video.fill", labSkillColor("Defending"))
                    stat("\(n.bestStreak)", "Best streak", "flame.fill", labSkillColor("Shooting"))
                }
            }
        }
    }

    private func stat(_ value: String, _ label: String, _ icon: String, _ tint: Color) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 14, weight: .bold)).foregroundStyle(tint)
            Text(value).font(.system(size: 20, weight: .bold)).foregroundStyle(C.creme).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(F.round(11, .semibold)).foregroundStyle(C.muted).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - achievements

struct Achievement: Identifiable {
    let id: String
    let name: String
    let how: String
    let icon: String
    let tint: Color
    /// 0 to 1: how close the player is.
    let progress: Double
    var earned: Bool { progress >= 1 }

    @MainActor static func all(_ store: AppStore) -> [Achievement] {
        let n = CareerNumbers(store)
        func p(_ have: Double, _ need: Double) -> Double { min(1, max(0, have / need)) }
        return [
            Achievement(id: "first", name: "First touch", how: "Train for the first time", icon: "soccerball", tint: C.brandHi, progress: p(Double(n.days), 1)),
            Achievement(id: "week", name: "Full week", how: "Train on 7 different days", icon: "calendar", tint: labSkillColor("Stretching"), progress: p(Double(n.days), 7)),
            Achievement(id: "streak7", name: "On fire", how: "Reach a 7 day streak", icon: "flame.fill", tint: labSkillColor("Shooting"), progress: p(Double(n.bestStreak), 7)),
            Achievement(id: "hour", name: "Hour up", how: "Train for 60 minutes in total", icon: "clock.fill", tint: C.gold, progress: p(Double(n.minutes), 60)),
            Achievement(id: "ten", name: "Ten hours", how: "Train for 600 minutes in total", icon: "hourglass", tint: C.gold, progress: p(Double(n.minutes), 600)),
            Achievement(id: "sets", name: "Century", how: "Finish 100 sets", icon: "checkmark.seal.fill", tint: C.brandHi, progress: p(Double(n.sets), 100)),
            Achievement(id: "run", name: "First run", how: "Record a run with GPS", icon: "figure.run", tint: labSkillColor("Runs"), progress: p(Double(n.runs), 1)),
            Achievement(id: "10k", name: "Ten kilometres", how: "Run 10 km in total", icon: "map.fill", tint: labSkillColor("Runs"), progress: p(n.km, 10)),
            Achievement(id: "film", name: "Student of the game", how: "Review your first clip", icon: "video.fill", tint: labSkillColor("Defending"), progress: p(Double(n.reviews), 1)),
            Achievement(id: "fix", name: "Fixed it", how: "Clear 3 drills from your Fix List", icon: "wrench.and.screwdriver.fill", tint: labSkillColor("Defending"), progress: p(Double(n.fixesCleared), 3)),
            Achievement(id: "fuel", name: "Well fuelled", how: "Log food on 5 days", icon: "fork.knife", tint: labSkillColor("Passing"), progress: p(Double(n.foodDays), 5)),
            Achievement(id: "rating", name: "Levelled up", how: "Raise your ratings by 10 points", icon: "arrow.up.right", tint: C.brand, progress: p(Double(store.spider.totalGain), 10)),
        ]
    }
}

struct AchievementsCard: View {
    @Environment(AppStore.self) private var store
    @State private var showAll = false

    var body: some View {
        let all = Achievement.all(store)
        let earned = all.filter(\.earned).count
        // earned first, then the closest ones
        let sorted = all.sorted { ($0.earned ? 2 : $0.progress) > ($1.earned ? 2 : $1.progress) }
        let shown = showAll ? sorted : Array(sorted.prefix(4))
        LabPanel(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "trophy.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(C.gold)
                    Text("ACHIEVEMENTS").font(F.round(12, .bold)).kerning(1.6).foregroundStyle(C.brandHi)
                    Spacer()
                    Text("\(earned) OF \(all.count)").font(F.round(11, .bold)).kerning(1.2).foregroundStyle(C.muted)
                }
                VStack(spacing: 10) {
                    ForEach(shown) { a in row(a) }
                }
                Button { withAnimation(.snappy) { showAll.toggle() } } label: {
                    HStack(spacing: 6) {
                        Text(showAll ? "Show fewer" : "Show all \(all.count)")
                        Image(systemName: showAll ? "chevron.up" : "chevron.down").font(.system(size: 11, weight: .bold))
                    }
                    .font(F.round(14, .semibold)).foregroundStyle(C.brandHi)
                    .frame(maxWidth: .infinity).frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func row(_ a: Achievement) -> some View {
        HStack(spacing: 12) {
            Image(systemName: a.icon).font(.system(size: 16, weight: .bold))
                .foregroundStyle(a.earned ? a.tint : C.muted)
                .frame(width: 42, height: 42)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill((a.earned ? a.tint : C.muted).opacity(0.16)))
                .shadow(color: a.earned ? a.tint.opacity(0.5) : .clear, radius: 8)
            VStack(alignment: .leading, spacing: 4) {
                Text(a.name).font(F.round(15, .semibold)).foregroundStyle(a.earned ? C.creme : C.creme2)
                Text(a.how).font(F.round(12, .medium)).foregroundStyle(C.muted)
                if !a.earned { LabBar(value: a.progress, goal: 1, color: a.tint).padding(.top, 2) }
            }
            Spacer(minLength: 0)
            if a.earned {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 20, weight: .bold)).foregroundStyle(a.tint)
            } else {
                Text("\(Int((a.progress * 100).rounded()))%").font(F.round(12, .bold)).foregroundStyle(C.muted)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(a.name). \(a.how). \(a.earned ? "Earned" : "\(Int((a.progress * 100).rounded())) percent")")
    }
}
