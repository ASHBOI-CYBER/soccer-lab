// 2026-10-24: the Plan TAB is gone ("the session page should replace the weekly plan page") ? Sessions is the home
// tab. This file still holds the shared pieces Sessions uses: RunSession (training a session), SessionRow,
// SessionDone. PlanTab / DayDetail / AddDrills / Templates are no longer reachable.
// Plan: the week (saved on the phone), a day, adding sessions or raw drills, templates and the Today session.
// A day holds the player's named sessions (Sessions tab) and/or drills put on it by themselves.
// Habit-tracker look (pieces in PlanCards.swift): ONE hero on top (today's first drill live in 3D + its ring),
// then the week as a rail of date medallions and day cards. Sets are logged by date, so each week starts clean.
import SwiftUI

enum PlanRoute: Hashable { case day(String), add(String), templates, today, done }

/// The rail between two days (or drills) is green when the training on both sides of it is done.
func chainLinks(_ count: Int, training: (Int) -> Bool, done: (Int) -> Bool) -> [Bool] {
    (0..<max(0, count - 1)).map { i in
        guard let a = (0...i).reversed().first(where: training),
              let b = ((i + 1)..<count).first(where: training) else { return false }
        return done(a) && done(b)
    }
}

struct PlanTab: View {
    @Environment(AppStore.self) private var store
    @State private var path: NavigationPath = {
        var p = NavigationPath()
        let r = DebugRoute.parts
        guard r.first == "plan", r.count > 1 else { return p }
        switch r[1] {
        case "today": p.append(PlanRoute.today)
        case "templates": p.append(PlanRoute.templates)
        case "done": p.append(PlanRoute.done)
        case "day": p.append(PlanRoute.day(r[safe: 2] ?? "Wed"))
        case "add": p.append(PlanRoute.add(r[safe: 2] ?? "Wed"))
        default: break
        }
        return p
    }()
    @State private var shown = false

    var body: some View {
        NavigationStack(path: $path) {
            let today = todayKey()
            let items = store.items(today)
            let links = chainLinks(DAYS.count, training: { !store.items(DAYS[$0]).isEmpty }, done: { store.isDone(DAYS[$0]) })
            let planned = DAYS.filter { !store.items($0).isEmpty && store.state($0) != .before }.count
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    TabHeader(title: "MY WEEK") { StreakChip(n: store.streak) }

                    WeekBallHero(onTapDay: { path.append(PlanRoute.day($0)) }) {
                        if items.isEmpty {
                            Button("+ ADD TRAINING") { path.append(PlanRoute.day(today)) }.buttonStyle(.gameLarge(.charcoal))
                        } else if store.state(today) != .done {
                            Button { path.append(PlanRoute.today) } label: {
                                Label(store.doneSets(today) > 0 ? "KEEP GOING" : "START", systemImage: "play.fill")
                            }
                            .buttonStyle(.gameLarge)
                        }
                    }
                    .padding(.top, 2)

                    HStack(alignment: .firstTextBaseline) {
                        Text("This week").font(F.round(20, .bold)).foregroundStyle(C.creme)
                        Spacer()
                        Text("\(store.sessionsThisWeek) of \(planned) done")
                            .font(F.round(15, .semibold))
                            .foregroundStyle(store.sessionsThisWeek > 0 && store.sessionsThisWeek == planned ? C.brand : C.muted)
                            .contentTransition(.numericText())
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 30)
                    .padding(.bottom, 10)

                    VStack(spacing: 0) {
                        ForEach(Array(DAYS.enumerated()), id: \.element) { i, d in
                            WeekRow(day: d, up: i == 0 ? nil : links[i - 1], down: i == DAYS.count - 1 ? nil : links[i])
                                .opacity(shown ? 1 : 0)
                                .offset(y: shown ? 0 : 18)
                                .animation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.05 + Double(i) * 0.045), value: shown)
                        }
                    }

                    NavigationLink(value: PlanRoute.templates) {
                        HStack(spacing: 12) {
                            Image(systemName: "square.grid.2x2.fill").font(.system(size: 17, weight: .bold)).foregroundStyle(C.brand)
                            Text("Start from a template").font(F.round(17, .semibold)).foregroundStyle(C.creme)
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).foregroundStyle(C.muted)
                        }
                        .padding(.horizontal, 18)
                        .frame(height: 56)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(C.char850)
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(C.charInk, lineWidth: 2)))
                    }
                    .buttonStyle(.press(.stud))
                    .padding(.top, 22)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .overlay(alignment: .top) { TopScrim() }
            .tabRoot("My week")
            .page()
            .onAppear { shown = true }
            .navigationDestination(for: PlanRoute.self) { r in
                switch r {
                case .day(let d): DayDetail(day: d, path: $path)
                case .add(let d): AddDrills(day: d)
                case .templates: Templates(path: $path)
                case .today:
                    RunLauncher(path: $path, request: RunRequest(items: store.items(todayKey()), name: store.label(todayKey()), planDay: true))
                case .done: SessionDone(path: $path)
                }
            }
            .sessionDestinations(path: $path)
            .navigationDestination(for: Drill.self) { DrillDetail(drill: $0) }
        }
    }
}

/// A day: its hero, then the training as a rail ? each session's drills under its name, then the raw drills.
/// Each drill's ring fills with its sets.
struct DayDetail: View {
    let day: String
    @Binding var path: NavigationPath
    @Environment(AppStore.self) private var store
    @State private var editing: EntrySource?
    @State private var picking = false

    var body: some View {
        let entries = store.entries(day)
        let state = store.state(day)
        let full: (Int) -> Bool = { i in state == .done || store.setsDone(day, entries[i].item.drill) >= entries[i].item.sets }
        let links = chainLinks(entries.count, training: { _ in true }, done: full)
        let indexed = Array(entries.enumerated())
        let rawCount = store.raw(day).count
        List {
            Section {
                DayHero(day: day, stageHeight: 230, names: false) {
                    if !entries.isEmpty && day == todayKey() && state != .done {
                        Button { path.append(PlanRoute.today) } label: {
                            Label(store.doneSets(day) > 0 ? "KEEP GOING" : "START", systemImage: "play.fill")
                        }
                        .buttonStyle(.gameLarge)
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 22, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            ForEach(store.sessions(on: day)) { s in
                Section {
                    ForEach(indexed.filter { if case .session(s.id, _) = $0.element.source { true } else { false } }, id: \.element.item.drill) { i, e in
                        row(i, e, full: full(i), links: links, count: entries.count)
                    }
                    .deleteDisabled(true)
                    .moveDisabled(true)
                } header: {
                    GroupHeader(title: s.name, sub: s.summary) {
                        Menu {
                            Button("Open session", systemImage: "list.bullet") { path.append(SessionRoute.session(s.id)) }
                            Button("Take off \(FULL_DAY[day]!.lowercased())", systemImage: "minus.circle", role: .destructive) {
                                Haptics.play(.unlatch)
                                store.toggle(s.id, on: day)
                            }
                        } label: { Image(systemName: "ellipsis.circle").font(.system(size: 20, weight: .semibold)).foregroundStyle(C.muted) }
                    }
                }
            }
            if rawCount > 0 {
                Section {
                    ForEach(indexed.filter { if case .raw = $0.element.source { true } else { false } }, id: \.element.item.drill) { i, e in
                        row(i, e, full: full(i), links: links, count: entries.count)
                    }
                    .onDelete { idx in
                        let raws = indexed.filter { if case .raw = $0.element.source { true } else { false } }
                        idx.forEach { store.remove(raws[$0].element.item.drill, from: day) }
                    }
                    .onMove { store.move(day: day, from: $0, to: $1) }
                } header: {
                    if !store.sessions(on: day).isEmpty { GroupHeader(title: "Drills", sub: "on their own") { EmptyView() } }
                }
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(6)
        .screenTitle(FULL_DAY[day] ?? day)
        .toolbar { if rawCount > 1 { EditButton().font(F.round(17, .semibold)) } }
        .page()
        .dock {
            HStack(spacing: 12) {
                Button("+ SESSION") { picking = true }.buttonStyle(.game(.brand))
                Button("+ DRILL") { path.append(PlanRoute.add(day)) }.buttonStyle(.game(.charcoal))
            }
        }
        .sheet(isPresented: $picking) { SessionDayPicker(day: day) }
        .sheet(item: Binding(get: { editing.map(EditSource.init) }, set: { editing = $0?.source })) { e in
            if let it = item(e.source) {
                DoseEditor(item: it,
                           change: { new in
                               switch e.source {
                               case .session(let id, let i): store.edit(id) { if $0.items.indices.contains(i) { $0.items[i] = new } }
                               case .raw(let i): store.setRaw(new, day: day, index: i)
                               }
                           },
                           view: { editing = nil; path.append(Library.shared.drill(it.drill)) },
                           remove: {
                               switch e.source {
                               case .session(let id, _): store.edit(id) { $0.items.removeAll { $0.drill == it.drill } }
                               case .raw: store.remove(it.drill, from: day)
                               }
                               editing = nil
                           })
            }
        }
    }

    private func item(_ src: EntrySource) -> PlanItem? {
        switch src {
        case .session(let id, let i): store.session(id)?.items[safe: i]
        case .raw(let i): store.raw(day)[safe: i]
        }
    }

    private func row(_ i: Int, _ e: DayEntry, full: Bool, links: [Bool], count: Int) -> some View {
        SessionRow(day: day, index: i, item: e.item, full: full,
                   up: i == 0 ? nil : links[i - 1], down: i == count - 1 ? nil : links[i]) { editing = e.source }
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

private struct EditSource: Identifiable { let source: EntrySource; var id: EntrySource { source } }

/// A group's name over its rows on a day page (a session, or the raw drills).
struct GroupHeader<Right: View>: View {
    let title: String
    let sub: String
    @ViewBuilder var right: Right
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Disp(title.uppercased(), size: 20)
                Text(sub).font(F.round(13, .semibold)).foregroundStyle(C.muted)
            }
            Spacer()
            right
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(C.char900)
        .listRowInsets(EdgeInsets())
    }
}

/// "Which sessions on this day?" ? tap to put one on (green check) or take it off.
struct SessionDayPicker: View {
    let day: String
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var naming = false

    var body: some View {
        VStack(spacing: 16) {
            Disp("SESSIONS ON \(day.uppercased())", size: 24).padding(.top, 24)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(store.sessions) { s in
                        let on = store.isOn(s.id, day)
                        Button {
                            Haptics.play(on ? .unlatch : .pop)
                            store.toggle(s.id, on: day)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(s.name.uppercased()).font(F.display(18)).foregroundStyle(C.creme).lineLimit(1)
                                    Text(s.items.isEmpty ? "No drills yet" : s.summary).font(F.round(14, .semibold)).foregroundStyle(C.muted)
                                }
                                Spacer()
                                Image(systemName: on ? "checkmark.circle.fill" : "plus.circle")
                                    .font(.system(size: 27, weight: .semibold))
                                    .foregroundStyle(on ? C.brand : C.muted)
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 66)
                            .background(DaySurface(state: on ? .today : .upcoming, radius: 18, chalk: false))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.press(.stud))
                    }
                    Button { naming = true } label: {
                        Text("+ New session").font(F.round(17, .semibold)).foregroundStyle(C.brand)
                            .frame(maxWidth: .infinity).frame(height: 54)
                            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(C.brand.opacity(0.55), style: StrokeStyle(lineWidth: 2, dash: [6, 6])))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.press(.pop))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
            Button("DONE") { dismiss() }.buttonStyle(.gameLarge).padding(.horizontal, 16).padding(.bottom, 8)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(C.char850)
        .presentationCornerRadius(28)
        .sheet(isPresented: $naming) {
            NameSheet(title: "NAME YOUR SESSION", button: "CREATE") { name in
                let s = store.newSession(name)
                store.toggle(s.id, on: day)
                naming = false
                Haptics.play(.goal)
            }
        }
    }
}

/// One drill in a day's session: its step ring on the rail, then the drill card (green pitch once every set is done).
struct SessionRow: View {
    let day: String
    let index: Int
    let item: PlanItem
    let full: Bool
    /// Show today's ticked sets (off on a session page, which isn't tied to a day).
    var track = true
    var up: Bool?
    var down: Bool?
    let tap: () -> Void
    @Environment(AppStore.self) private var store

    var body: some View {
        let d = Library.shared.drill(item.drill)
        let done = track ? min(item.sets, store.setsDone(day, item.drill)) : 0
        HStack(spacing: 10) {
            DayMedallion(label: "\(index + 1)", state: full ? .done : .today,
                         progress: Double(done) / Double(item.sets), size: 40)
                .frame(width: 44)
            Button(action: tap) {
                HStack(spacing: 12) {
                    Cover(drill: d)
                        .frame(width: 50, height: 62)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(C.charInk, lineWidth: 2))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(d.name.uppercased())
                            .font(F.display(18))
                            .foregroundStyle(full ? .white : C.creme)
                            .shadow(color: full ? C.brandInk : C.charInk, radius: 0, y: 2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(done > 0 && !full ? "\(item.dose) · \(done) of \(item.sets) sets" : item.dose)
                            .font(F.round(14, .semibold))
                            .foregroundStyle(full ? C.brandInk : C.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(8)
                .padding(.trailing, 6)
                .background(DaySurface(state: full ? .done : .upcoming, radius: 18, chalk: false))
                .contentShape(Rectangle())
            }
            .buttonStyle(LipPress(lip: full ? C.brandLip : C.charInk, radius: 18, depth: 4))
        }
        .padding(.vertical, 6)
        .background(alignment: .topLeading) {
            GeometryReader { g in
                let mid = g.size.height / 2
                ZStack(alignment: .topLeading) {
                    if let up { Capsule().fill(up ? C.brand : C.char700).frame(width: 4, height: mid + 1).offset(x: 20) }
                    if let down { Capsule().fill(down ? C.brand : C.char700).frame(width: 4, height: mid + 1).offset(x: 20, y: mid) }
                }
            }
        }
    }
}

/// Raw drills on a day (no session): the whole library.
struct AddDrills: View {
    let day: String
    @Environment(AppStore.self) private var store
    var body: some View {
        DrillPicker(title: "ADD TO \(day.uppercased())", picked: Set(store.raw(day).map(\.drill))) { id in
            store.raw(day).contains { $0.drill == id } ? store.remove(id, from: day) : store.add(id, to: day)
        }
    }
}

struct Templates: View {
    @Binding var path: NavigationPath
    @Environment(AppStore.self) private var store
    @State private var confirm: Template?

    var body: some View {
        List(Library.shared.templates) { t in
            Button { confirm = t } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(t.name).font(F.display(20)).foregroundStyle(C.creme)
                        Spacer()
                        Text(t.sub).font(F.round(14)).foregroundStyle(C.muted)
                    }
                    HStack(spacing: 6) {
                        ForEach(DAYS, id: \.self) { d in
                            Text(String(d.prefix(1)))
                                .font(F.round(13, .bold))
                                .foregroundStyle(t.days.contains(d) ? C.brandInk : C.muted)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(t.days.contains(d) ? C.brand : C.char700))
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .listRowBackground(C.char800)
        }
        .listStyle(.insetGrouped)
        .screenTitle("TEMPLATES")
        .page()
        .confirmationDialog("Replace your week with \(confirm?.name ?? "")?", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), titleVisibility: .visible) {
            Button("Use \(confirm?.name ?? "")") {
                if let t = confirm { store.apply(t) }
                Haptics.play(.goal)
                path = NavigationPath()
            }
        }
    }
}

/// An old pushed "run" route: opens the full-screen session player (SessionPlayer.swift) and steps back off the stack.
struct RunLauncher: View {
    @Binding var path: NavigationPath
    let request: RunRequest
    var body: some View {
        Color.clear.page().onAppear {
            if !path.isEmpty { path.removeLast() }
            ActiveRun.shared.start(request)
        }
    }
}

/// The payoff (v2 2026-10-30, user: "the session done thing still shows the old panels stitched. Only show the XP
/// gained with a nice animation, current level, and streak"): +XP counts up ? the level bar fills from where it was
/// (a LEVEL UP flips the number) ? the streak fire. NICE closes; the Sessions tab is already back on its main page.
struct SessionDone: View {
    @Binding var path: NavigationPath
    /// Set when shown inside the session player: NICE closes it.
    var close: (() -> Void)? = nil
    /// DEBUG `-route done:demo`: pretend this much XP was just earned ? nothing is saved (safe on a real phone).
    var demoXP: Int? = nil
    @Environment(AppStore.self) private var store
    @State private var shownXP = 0
    @State private var lv = 1
    @State private var fill = 0.0
    @State private var levelUp = false
    @State private var showStreak = false
    @State private var pop = false

    /// XP this session earned (0 when it was under a minute ? nothing gets logged then).
    private var gained: Int {
        if let demoXP { return demoXP }
        guard let c = store.completions.last, Date().timeIntervalSince(c.date) < 600 else { return 0 }
        return c.xp
    }

    var body: some View {
        let now = demoXP.map { Level(xp: store.xp + $0) } ?? store.level
        let streak = store.air
        VStack(spacing: 0) {
            Spacer()
            Disp("SESSION DONE!", size: 40)
                .scaleEffect(pop ? 1 : 0.6).opacity(pop ? 1 : 0)
            Text("+\(shownXP) XP")
                .font(.system(size: 84, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(C.gold)
                .contentTransition(.numericText(value: Double(shownXP)))
                .shadow(color: C.gold.opacity(0.35), radius: 14)
                .padding(.top, 6)
                .scaleEffect(pop ? 1 : 0.4)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .lastTextBaseline) {
                    Disp("LEVEL \(lv)", size: 36).contentTransition(.numericText(value: Double(lv)))
                    Spacer(minLength: 8)
                    Text(levelUp ? "LEVEL UP!" : LevelBadge.of(lv).name.uppercased())
                        .font(F.round(15, .heavy)).kerning(1)
                        .foregroundStyle(levelUp ? C.gold : C.muted)
                        .contentTransition(.opacity)
                }
                XPBar(progress: fill, height: 22).padding(.top, -6)
            }
            .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 20)
            .gameCard(padding: 0)
            .scaleEffect(levelUp ? 1.04 : 1)
            .padding(.horizontal, 20).padding(.top, 26)

            HStack(spacing: 6) {
                StreakFire(heat: max(0.35, streak.air()), size: 120, interactive: false)
                    .frame(width: 96, height: 110)
                VStack(alignment: .leading, spacing: 2) {
                    Disp("\(streak.days)-DAY", size: 36)
                    Text("STREAK").font(F.round(15, .heavy)).kerning(1.2).foregroundStyle(C.muted)
                }
                Spacer()
            }
            .padding(.horizontal, 30).padding(.top, 18)
            .opacity(showStreak ? 1 : 0).offset(y: showStreak ? 0 : 24)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .navigationBarBackButtonHidden()
        .page()
        .dock { Button("NICE") { if let close { close() } else { path = NavigationPath() } }.buttonStyle(.gameLarge(.gold, feel: .kick)) }
        .onAppear { play(to: now) }
    }

    /// The show: count the XP up, then run the bar from the old XP to the new one (through each level crossed).
    private func play(to now: Level) {
        let gain = gained
        let before = demoXP != nil ? store.level : Level(xp: max(0, store.xp - gain))
        lv = before.lv
        fill = before.progress
        withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { pop = true }
        Haptics.play(.pop)
        // count up over ~0.9 s in 18 ticks
        let steps = 18
        for i in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 + Double(i) * 0.05) {
                withAnimation(.snappy(duration: 0.12)) { shownXP = gain * i / steps }
                if i % 3 == 0 { Haptics.play(.stud) }
            }
        }
        var t = 1.35
        if now.lv > before.lv {
            // fill to the top, flip the number, start the new level from empty
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { withAnimation(.easeIn(duration: 0.5)) { fill = 1 } }
            t += 0.55
            DispatchQueue.main.asyncAfter(deadline: .now() + t) {
                fill = 0
                withAnimation(.spring(response: 0.35, dampingFraction: 0.45)) { lv = now.lv; levelUp = true }
                Haptics.play(.goal)
            }
            t += 0.15
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + t) { withAnimation(.spring(response: 0.8, dampingFraction: 0.85)) { fill = now.progress } }
        t += 0.6
        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { showStreak = true }
            Haptics.play(.heartbeat)
        }
    }
}
