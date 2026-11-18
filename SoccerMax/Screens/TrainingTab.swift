// TRAINING tab (SOCCER LAB, 2026-11-12; three parts since 2026-11-15).
//   PLAN     this week's calendar, the session for the picked day (built from onboarding: a warm-up, ball work every
//            player does, and drills for the player's position, LabPlan), the Fix List from Film.
//   DRILLS   tools (voice drills, library, Coach), ready-made sessions, quick drills by skill (TrainingHub.swift).
//   FITNESS  the live GPS run, workouts, fitness drills and the free session logger (TrainingHub.swift).
import SwiftUI

struct TrainingTab: View {
    @Environment(AppStore.self) private var store
    @State private var lab = Lab.shared
    /// The day whose session is showing ("Mon"..."Sun"); today when the tab opens.
    @State private var day = todayKey()
    // test builds: `-route tab:training:drillstab` / `:fitness` open that part
    @State private var part: TrainingPart = DebugRoute.parts.contains("fitness") ? .fitness : DebugRoute.parts.contains("drillstab") ? .drills : .plan
    // test builds: `-route tab:training:run` opens the live run, `:runsaved` its summary
    @State private var running = DebugRoute.parts.contains("run") || DebugRoute.parts.contains("runsaved")
    // test builds: `:drills` opens the drill library, `:drill` the first drill's page, `:session` the first ready-made session
    @State private var path: NavigationPath = {
        var p = NavigationPath()
        let r = DebugRoute.parts
        if r.contains("drills") { p.append(LabRoute.drills) }
        if r.contains("drill"), let d = Library.shared.drills.first { p.append(d) }
        // `drill.cone-slalom`: that drill's page
        if let id = r.first(where: { $0.hasPrefix("drill.") })?.dropFirst(6), Library.shared.has(String(id)) { p.append(Library.shared.drill(String(id))) }
        if r.contains("session"), let s = (Library.shared.technique + Library.shared.hybrid + Library.shared.workouts).first { p.append(s) }
        return p
    }()

    private var date: Date { dateOf(day) }
    private var isToday: Bool { day == todayKey() }
    private var plan: [Drill] { LabPlan.today(position: store.answers.position, date: date) }
    /// A recovery day for this player's training days (LabPlan.restDays).
    private func isRest(_ d: String) -> Bool { LabPlan.isRest(d, training: store.answers.trainingDaysPerWeek) }
    /// Days the player chose "Train anyway" on (this visit only).
    @State private var trainAnyway: Set<String> = []
    private var fixes: [Drill] { lab.fixList.filter { Library.shared.has($0) }.map { Library.shared.drill($0) } }
    private var sessions: [ProSession] { Library.shared.technique + Library.shared.hybrid + Library.shared.workouts }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    TabHeader("Training")
                    TrainingPartPicker(part: $part)
                    switch part {
                    case .plan:
                        week
                        if isRest(day) && !trainAnyway.contains(day) && !(isToday && plan.contains { lab.isDone($0.id) }) {
                            recovery
                        } else {
                            session
                        }
                        if !fixes.isEmpty { fixList }
                    case .drills:
                        TrainingDrillsPart()
                    case .fitness:
                        TrainingFitnessPart { runCard } free: { free }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .tabRoot("Training")
            .navigationDestination(for: Drill.self) { DrillDetail(drill: $0) }
            .navigationDestination(for: ProSession.self) { LabSessionPage(session: $0) }
            .navigationDestination(for: LabRoute.self) { _ in LabDrillLibrary() }
            // a session tapped on Profile's graph opens here
            .navigationDestination(item: Binding(get: { Nav.shared.log }, set: { Nav.shared.log = $0 })) { LoggedDetail(c: $0) }
            .page()
        }
        .fullScreenCover(isPresented: $running) { RunView().duoColumn() }
    }

    // MARK: this week

    private var week: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Disp("WEEK \(lab.week())", size: 24)
                Spacer()
                Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(F.round(14, .semibold)).foregroundStyle(C.muted)
            }
            HStack(spacing: 6) {
                ForEach(DAYS, id: \.self) { d in dayPill(d) }
            }
        }
    }

    private func dayPill(_ d: String) -> some View {
        let when = dateOf(d)
        let trained = (store.trained[dateKey(when)] ?? 0) >= 1
        let today = d == todayKey()
        let picked = d == day
        let future = when > Date()
        return Button {
            day = d
            Haptics.play(.stud)
        } label: {
            VStack(spacing: 5) {
                Text(String(d.prefix(1))).font(F.round(12, .bold)).foregroundStyle(picked ? Color.white : C.muted)
                Text("\(Calendar.current.component(.day, from: when))")
                    .font(F.round(17, .bold)).foregroundStyle(picked ? Color.white : future ? C.muted : C.creme)
                let rest = !trained && isRest(d)
                Image(systemName: trained ? "checkmark.circle.fill" : rest ? "moon.zzz.fill" : "circle.fill")
                    .font(.system(size: trained || rest ? 12 : 6, weight: .bold))
                    .foregroundStyle(trained ? (picked ? Color.white : C.brand) : rest ? (picked ? Color.white : C.muted) : (today ? C.brandHi : Color.clear))
                    .frame(height: 14)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(picked ? AnyShapeStyle(LinearGradient(colors: [C.brandHi, C.brand], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(C.char800))
                    .shadow(color: picked ? C.brand.opacity(0.65) : .clear, radius: 12, y: 3)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(today ? C.brandHi : C.line, lineWidth: today ? 1.5 : 1))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(FULL_DAY[d]?.capitalized ?? d) \(Calendar.current.component(.day, from: when))\(today ? ", today" : "")\(trained ? ", trained" : isRest(d) ? ", recovery day" : "")")
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    // MARK: the day's session

    private var session: some View {
        let list = plan
        let doneCount = isToday ? list.filter { lab.isDone($0.id) }.count : 0
        let minutes = list.reduce(0) { $0 + $1.min }
        return VStack(alignment: .leading, spacing: 12) {
            LabKicker(isToday ? "TODAY'S SESSION" : "\(FULL_DAY[day] ?? day)'S SESSION")
            LabPanel {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 14) {
                        LabRing(value: Double(doneCount), goal: Double(max(1, list.count))) {
                            Text("\(doneCount)/\(list.count)").font(F.round(15, .bold)).foregroundStyle(C.creme)
                        }
                        .frame(width: 62, height: 62)
                        VStack(alignment: .leading, spacing: 4) {
                            Disp("\(LabPlan.group(store.answers.position).uppercased()) SESSION", size: 22)
                                .lineLimit(1).minimumScaleFactor(0.7)
                            Label("\(list.count) drills · about \(minutes) min", systemImage: "clock.fill")
                                .font(F.round(14, .semibold)).foregroundStyle(C.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    VStack(spacing: 10) {
                        ForEach(list) { d in LabDrillRow(drill: d, canTick: isToday) }
                    }
                    if !isToday {
                        Text("You can train these on the day itself.")
                            .font(F.round(13, .semibold)).foregroundStyle(C.muted)
                    } else if doneCount == list.count, !list.isEmpty {
                        Label("Session done. Nice work.", systemImage: "checkmark.seal.fill")
                            .font(F.round(15, .bold)).foregroundStyle(C.gold)
                    }
                }
            }
        }
    }

    // MARK: recovery day

    private var recovery: some View {
        let n = store.answers.trainingDaysPerWeek
        let light = LabPlan.recovery.filter { Library.shared.has($0) }.map { Library.shared.drill($0) }
        return VStack(alignment: .leading, spacing: 12) {
            LabKicker(isToday ? "TODAY · RECOVERY DAY" : "\(FULL_DAY[day] ?? day) · RECOVERY DAY")
            LabPanel {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 14) {
                        Image(systemName: "moon.zzz.fill").font(.system(size: 26, weight: .bold)).foregroundStyle(C.brandHi)
                            .frame(width: 62, height: 62).background(Circle().fill(C.brand.opacity(0.16)))
                        VStack(alignment: .leading, spacing: 4) {
                            Disp("RECOVERY DAY", size: 22)
                            Text("You train \(n) days a week. Today your body gets stronger.")
                                .font(F.round(14, .semibold)).foregroundStyle(C.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach([("drop.fill", "Drink plenty of water"), ("figure.flexibility", "Stretch for 10 minutes"),
                                 ("bed.double.fill", "Sleep 8 to 10 hours"), ("fork.knife", "Eat well to refuel")], id: \.1) { t in
                            Label(t.1, systemImage: t.0).font(F.round(15, .semibold)).foregroundStyle(C.creme2)
                        }
                    }
                    if !light.isEmpty {
                        Text("LIGHT MOBILITY, IF YOU FEEL LIKE IT").font(F.round(12, .bold)).kerning(1).foregroundStyle(C.muted)
                            .padding(.top, 4)
                        VStack(spacing: 10) {
                            ForEach(light) { d in LabDrillRow(drill: d, canTick: isToday) }
                        }
                    }
                    Button {
                        withAnimation(.snappy) { _ = trainAnyway.insert(day) }
                    } label: { Label("Train anyway", systemImage: "figure.soccer") }
                        .buttonStyle(.game(.charcoal, height: 52, font: 18))
                }
            }
        }
    }

    // MARK: fix list

    private var fixList: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabKicker("FIX LIST · FROM YOUR FILM")
            LabPanel {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Do each one \(Lab.fixGoal) times and it leaves the list.")
                        .font(F.round(14, .semibold)).foregroundStyle(C.muted)
                    ForEach(fixes) { d in
                        LabDrillRow(drill: d, note: "\(lab.fixCount[d.id] ?? 0) of \(Lab.fixGoal) done")
                    }
                }
            }
        }
    }

    // MARK: live run

    private var runCard: some View {
        let weekStart = dateOf("Mon")
        let mine = lab.runs.filter { $0.date >= weekStart }
        let km = mine.reduce(0) { $0 + $1.km }
        return VStack(alignment: .leading, spacing: 12) {
            LabKicker("RUNNING")
            LabPanel {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 14) {
                        Image(systemName: "figure.run").font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 54, height: 54)
                            .background(Circle().fill(labSkillColor("Runs")))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Live run").font(F.round(18, .bold)).foregroundStyle(C.creme)
                            Text(mine.isEmpty ? "Track distance, pace and your route with GPS."
                                 : "\(String(format: "%.1f", km)) km this week · \(mine.count) run\(mine.count == 1 ? "" : "s")")
                                .font(F.round(14, .semibold)).foregroundStyle(C.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    Button { running = true } label: { Label("START A RUN", systemImage: "location.fill") }
                        .buttonStyle(.game(.brand, height: 52, font: 20))
                    if let last = lab.runs.first {
                        HStack {
                            Text("Last run").font(F.round(13, .bold)).foregroundStyle(C.creme2)
                            Spacer()
                            Text("\(RunFormat.distance(last.meters)) km · \(RunFormat.time(last.seconds)) · \(RunFormat.pace(last.pace)) /km")
                                .font(F.round(13, .semibold)).foregroundStyle(C.muted)
                        }
                    }
                }
            }
        }
    }

    // MARK: drill library

    private var library: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabKicker("ALL DRILLS")
            NavigationLink(value: LabRoute.drills) {
                HStack(spacing: 12) {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(C.brand))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Drill library").font(F.round(17, .bold)).foregroundStyle(C.creme)
                        Text("\(Library.shared.drills.count) drills, sorted by skill")
                            .font(F.round(13, .semibold)).foregroundStyle(C.muted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .heavy)).foregroundStyle(C.muted)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(C.char800)
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(C.line, lineWidth: 1)))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: ready-made sessions

    private var readyMade: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabKicker("READY-MADE SESSIONS")
            VStack(spacing: 10) {
                ForEach(sessions) { s in
                    NavigationLink(value: s) {
                        HStack(spacing: 12) {
                            Image(systemName: s.kind == "workout" ? "bolt.fill" : s.kind == "hybrid" ? "flame.fill" : "soccerball")
                                .font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(s.kind == "workout" ? labSkillColor("Runs") : s.kind == "hybrid" ? labSkillColor("Shooting") : C.brand))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.title).font(F.round(17, .bold)).foregroundStyle(C.creme)
                                Text(s.kind == "workout" ? "Fitness" : s.kind == "hybrid" ? "Soccer and fitness" : "Technique")
                                    .font(F.round(13, .semibold)).foregroundStyle(C.muted)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .heavy)).foregroundStyle(C.muted)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(C.char800)
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(C.line, lineWidth: 1)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: free session

    private var free: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabKicker("TRAINED ON YOUR OWN?")
            Button { FreeStart.shared.request = FreeRequest(area: nil) } label: {
                Label("LOG A FREE SESSION", systemImage: "play.fill")
            }
            .buttonStyle(.game(.charcoal))
        }
    }
}

/// One drill: its skill's coloured icon, the name and dose (opens the drill page), and a tick on the right that
/// marks it done for today.
struct LabDrillRow: View {
    let drill: Drill
    var note: String? = nil
    var canTick = true
    @Environment(AppStore.self) private var store
    @State private var lab = Lab.shared

    var body: some View {
        let done = canTick && lab.isDone(drill.id)
        let tint = labSkillColor(drill.skill)
        HStack(spacing: 10) {
            NavigationLink(value: drill) {
                HStack(spacing: 12) {
                    Image(systemName: skillIcon(drill.skill))
                        .font(.system(size: 17, weight: .bold)).foregroundStyle(done ? C.muted : tint)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill((done ? C.muted : tint).opacity(0.18)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(drill.name).font(F.round(16, .bold)).foregroundStyle(done ? C.muted : C.creme)
                            .strikethrough(done, color: C.muted)
                        Text(note ?? "\(drill.reps) · \(drill.min) min")
                            .font(F.round(13, .semibold)).foregroundStyle(C.muted).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 2026-11-18: no tick button. Drills are done with the Start Drill timer on the drill page.
            if canTick {
                NavigationLink(value: drill) {
                    Image(systemName: done ? "checkmark.circle.fill" : "play.circle.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(done ? C.brand : C.brandHi)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(done ? "\(drill.name), done today. Train again" : "Start \(drill.name)")
            }
        }
        .padding(.vertical, 6).padding(.leading, 8).padding(.trailing, 4)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(C.char850))
    }
}

/// A ready-made session: pick a level, then tick its drills off.
struct LabSessionPage: View {
    let session: ProSession
    @State private var level = "Club"

    private var names: [String] { Library.shared.levels.map(\.name) }
    private var index: Int { names.firstIndex(of: level) ?? 0 }
    private var rows: [ProDrill] { session.levels[safe: index] ?? session.levels.last ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Disp(session.title.uppercased(), size: 32)
                Text(Library.shared.levels[safe: index]?.line ?? "")
                    .font(F.round(15, .semibold)).foregroundStyle(C.muted)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(names, id: \.self) { n in
                            Button(n) { level = n }
                                .font(F.round(14, .bold))
                                .foregroundStyle(n == level ? Color.white : C.creme2)
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .background(Capsule().fill(n == level ? C.brand : C.char800))
                                .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                VStack(spacing: 10) {
                    ForEach(rows, id: \.id) { r in
                        let d = Library.shared.drill(r.id)
                        LabDrillRow(drill: d, note: "\(r.sets ?? 3) sets · \(d.reps) · \(d.min) min")
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .page()
    }
}
