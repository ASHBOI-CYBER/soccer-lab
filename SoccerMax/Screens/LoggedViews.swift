// LOGGED (2026-10-28): "In settings AND in a third tab called 'logged' on the first sessions page create a list of
// all logged sessions." Every finished session, newest first, by day; tap one = its drills with the real time each.
// 2026-11-08: free sessions (FreeSession.swift) show their area icon + photos/videos.
// Data = `store.completions` (sessions finished before the player have no per-drill detail ? they show the total).
import SwiftUI

/// The list itself (no scroll view): the Sessions tab's LOGGED page and Settings ? Logged sessions both use it.
struct LoggedSessions: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let days = Self.byDay(store.completions)
        if days.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.seal").font(.system(size: 40, weight: .bold)).foregroundStyle(C.brand)
                Disp("NOTHING LOGGED YET", size: 24)
                Text("Finish a session and it lands here.").font(F.round(16)).foregroundStyle(C.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
            .gameCard()
        } else {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(days, id: \.day) { g in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(Self.dayTitle(g.day)).font(F.round(13, .bold)).kerning(1.2).foregroundStyle(C.muted)
                        ForEach(g.list, id: \.self) { c in
                            NavigationLink { LoggedDetail(c: c) } label: { LoggedRow(c: c) }
                                .buttonStyle(.press(.stud))
                        }
                    }
                }
            }
        }
    }

    static func byDay(_ all: [Completion]) -> [(day: Date, list: [Completion])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: all) { cal.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { d in (d, groups[d]!.sorted { $0.date > $1.date }) }
    }
    static func dayTitle(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "TODAY" }
        if cal.isDateInYesterday(d) { return "YESTERDAY" }
        let f = DateFormatter()
        f.dateFormat = cal.isDate(d, equalTo: Date(), toGranularity: .year) ? "EEE d MMM" : "EEE d MMM yyyy"
        return f.string(from: d).uppercased()
    }
}

/// The time it really took ("12:40"), or the rounded minutes for older logs.
private func took(_ c: Completion) -> String {
    if c.area != nil { return minText(Double(c.minutes)) }   // free sessions: the time they set ("47 min", "1 h 30")
    return c.seconds.map { clock($0) } ?? "\(c.minutes) min"
}

struct LoggedRow: View {
    let c: Completion
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: TrainingArea.of(c.area)?.icon ?? "checkmark")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(C.brandInk)
                .frame(width: 44, height: 44)
                .background(Circle().fill(C.brand))
            VStack(alignment: .leading, spacing: 3) {
                Text(c.name.uppercased()).font(F.display(19)).foregroundStyle(C.creme).lineLimit(1).minimumScaleFactor(0.7)
                Text([c.date.formatted(date: .omitted, time: .shortened),
                      c.drills.flatMap { $0.isEmpty ? nil : "\($0.count) drill\($0.count == 1 ? "" : "s")" },
                      c.media.map { "\($0.count) attached" }]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(F.round(14, .semibold)).foregroundStyle(C.muted)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(took(c)).font(.system(size: 18, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(C.creme)
                Text("+\(c.xp) XP").font(F.round(13, .bold)).foregroundStyle(C.gold)
            }
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).foregroundStyle(C.muted)
        }
        .padding(.vertical, 8)          // borderless (2026-11-08)
        .contentShape(Rectangle())
    }
}

struct LoggedDetail: View {
    let c: Completion
    @Environment(AppStore.self) private var store
    @State private var viewing: MediaName?

    // v2 (2026-11-08, user: "show the actual drills with icons and make the logged sessions look nice"):
    // a big shaded icon hero, three plain numbers, then every drill as a row with its skill icon. No borders.
    var body: some View {
        let area = TrainingArea.of(c.area)
        let logged = c.drills ?? []
        let plan = logged.isEmpty ? planned : []
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // hero
                HStack(spacing: 16) {
                    Image(systemName: area?.icon ?? skillIcon(logged.first.map { Library.shared.drill($0.drill).skill } ?? plan.first?.skill))
                        .font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .background(Circle().fill(TrainingChart.shade(Double(c.minutes) / 60)))
                        .shadow(color: C.brand.opacity(0.25), radius: 14)
                    VStack(alignment: .leading, spacing: 4) {
                        Disp(c.name.uppercased(), size: 30).lineLimit(2).minimumScaleFactor(0.6)
                        Text(c.date.formatted(.dateTime.weekday(.wide).month(.wide).day().hour().minute()))
                            .font(F.round(14, .semibold)).foregroundStyle(C.muted)
                    }
                }

                // the numbers
                HStack(spacing: 0) {
                    number(took(c), "TIME", C.creme)
                    if let area { number(area.name, "AREA", C.brand) }
                    else { number("\(max(logged.count, plan.count))", (max(logged.count, plan.count)) == 1 ? "DRILL" : "DRILLS", C.creme) }
                    number("+\(c.xp)", "XP", C.gold)
                }

                if let parts = c.parts, parts.count > 1 {
                    section("WHAT YOU WORKED ON") {
                        VStack(spacing: 14) {
                            ForEach(parts, id: \.self) { p in
                                HStack(spacing: 14) {
                                    AreaIcon(area: TrainingArea(id: p.area, name: p.name, icon: p.icon), size: 44)
                                    Text(p.name).font(F.round(17, .bold)).foregroundStyle(C.creme)
                                    Spacer()
                                    Text("\(p.minutes) min").font(F.display(20)).foregroundStyle(C.creme2)
                                }
                            }
                        }
                    }
                }

                if let media = c.media, !media.isEmpty {
                    section("PHOTOS + VIDEOS") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                            ForEach(media, id: \.self) { n in
                                Button { if SessionMedia.exists(n) { viewing = MediaName(id: n) } } label: { MediaTile(name: n) }
                                    .buttonStyle(.press(.stud))
                            }
                        }
                    }
                }

                if !logged.isEmpty {
                    section("DRILLS") {
                        ForEach(Array(logged.enumerated()), id: \.offset) { i, d in
                            let drill = Library.shared.drill(d.drill)
                            drillRow(drill, title: d.name, sub: d.dose, right: clock(d.seconds), last: i == logged.count - 1)
                        }
                    }
                } else if !plan.isEmpty {
                    section("DRILLS") {
                        ForEach(Array(plan.enumerated()), id: \.offset) { i, p in
                            drillRow(p.drill, title: p.drill.name, sub: p.dose, right: "\(p.min) min", last: i == plan.count - 1)
                        }
                    }
                } else if let area {
                    section("WHAT YOU DID") {
                        HStack(spacing: 14) {
                            Image(systemName: area.icon).font(.system(size: 18, weight: .bold)).foregroundStyle(C.brand)
                                .frame(width: 44, height: 44).background(Circle().fill(C.brand.opacity(0.14)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(area.name).font(F.round(17, .bold)).foregroundStyle(C.creme)
                                Text("Free session · \(took(c))").font(F.round(14, .semibold)).foregroundStyle(C.muted)
                            }
                            Spacer()
                        }
                    }
                }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .screenTitle("SESSION")
        .page()
        .fullScreenCover(item: $viewing) { MediaViewer(name: $0.id) }
    }

    /// Sessions logged before drill-by-drill times were kept: the drills of the saved session with that name.
    private var planned: [(drill: Drill, skill: String, dose: String, min: Int)] {
        guard let s = store.sessions.first(where: { $0.name == c.name }) else { return [] }
        return s.items.filter { Library.shared.has($0.drill) }.map { it in
            let d = Library.shared.drill(it.drill)
            let reps = it.reps.map { "\(it.sets) × \($0)\((it.unit ?? "").isEmpty ? "" : " \(it.unit!)")" } ?? "\(it.sets) sets"
            return (d, d.skill, reps, it.min)
        }
    }

    private func drillRow(_ drill: Drill, title: String, sub: String, right: String, last: Bool) -> some View {
        NavigationLink { DrillDetail(drill: drill) } label: {
            HStack(spacing: 14) {
                Image(systemName: skillIcon(drill.skill))
                    .font(.system(size: 17, weight: .bold)).foregroundStyle(C.brand)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(C.brand.opacity(0.14)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(F.round(17, .bold)).foregroundStyle(C.creme).lineLimit(1)
                    Text("\(drill.skill) · \(sub)").font(F.round(13, .semibold)).foregroundStyle(C.muted).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(right).font(.system(size: 16, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(C.creme2)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .heavy)).foregroundStyle(C.muted.opacity(0.7))
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.press(.stud))
    }

    private func section<V: View>(_ title: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(F.round(13, .heavy)).kerning(1.6).foregroundStyle(C.muted)
            content()
        }
    }

    private func number(_ v: String, _ k: String, _ tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(v).font(.system(size: 24, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(k).font(F.round(11, .bold)).kerning(1.2).foregroundStyle(C.muted)
        }
        .frame(maxWidth: .infinity)
    }
}

/// One SF Symbol per drill skill.
func skillIcon(_ skill: String?) -> String {
    switch skill {
    case "Dribbling": return "figure.soccer"
    case "Shooting": return "target"
    case "Ball mastery": return "soccerball"
    case "Passing": return "arrow.left.arrow.right"
    case "Goalkeeping": return "hand.raised.fill"
    case "First touch": return "soccerball.inverse"
    case "Fitness": return "bolt.heart.fill"
    case "Awareness": return "eye.fill"
    case "Defending": return "shield.fill"
    case "Stretching": return "figure.flexibility"
    case "Runs": return "figure.run"
    case "Core": return "figure.core.training"
    default: return "soccerball"
    }
}


/// Settings ? Logged sessions.
struct LoggedPage: View {
    var body: some View {
        ScrollView {
            LoggedSessions().padding(16)
        }
        .scrollIndicators(.hidden)
        .screenTitle("LOGGED SESSIONS")
        .page()
    }
}
