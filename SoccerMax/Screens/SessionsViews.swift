// Sessions ? tab 1 (2026-10-23: "remove the drills section and instead put sessions? create sessions where they get
// to choose reps of each drill? Each session should have a name.").
// v3 (2026-10-24): "remove the days from the sessions, also combine 'skills and fitness' into one page (keeping them
// separate on paper) and then the second tab should be your saved/created sessions easily editable."
//   TRAIN       = the training level (the five grounds as cut-out 3D models, LevelViews.swift), then SKILLS (real
//                 players + technique) and FITNESS (real players: Mbappé Speed, Kanté Engine?) one under the other.
//   MY SESSIONS = what you saved or made, Skills and Fitness apart; tap one = its edit page (rename, sets ?/+ right on
//                 each drill, drag to reorder, swipe to remove, + add drills), START any time. No days any more.
// The 408-drill library lives inside the drill picker (+ ADD DRILLS), grouped by skill, search + who.
import SwiftUI

/// `pro` = a premade session's page (a player's, a technique or a fitness one), `runPro` = run it as it is (notes/23).
enum SessionRoute: Hashable { case session(String), pick(String), run(String), done, pro(String), runPro(String) }

struct SessionsTab: View {
    @Environment(AppStore.self) private var store
    @State private var path: NavigationPath = {
        var p = NavigationPath()
        let r = DebugRoute.parts
        if r.first == "drill", let id = r[safe: 1] { p.append(Library.shared.drill(id)) }
        return p
    }()
    /// The side a new session is named for (nil = no sheet).
    @State private var naming: Bool?
    @State private var shown = false
    /// TRAIN (everything ready-made) or MY SESSIONS (yours, to change) ? 2026-10-24.
    @State private var tab: String = {
        let r = DebugRoute.parts
        if r.first == "logged" || (r.first == "sessions" && r[safe: 1] == "logged") { return "Logged" }
        return r.first == "mine" || (r.first == "sessions" && r[safe: 1] == "mine") ? "Saved" : "Discover"
    }()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    TabHeader(title: "SESSIONS") {
                        Button { naming = false } label: { Image(systemName: "plus").font(.system(size: 20, weight: .heavy)) }
                            .buttonStyle(.gameRound(.brand, size: 46))
                            .accessibilityLabel("New session")
                    }

                    Segments(options: ["Discover", "Saved", "Logged"], pick: $tab.animation(.snappy))
                        .padding(.top, 12)

                    if tab == "Discover" {
                        LevelCarousel().padding(.top, 10)
                        PremadeShelves().padding(.top, 18)
                    } else if tab == "Saved" {
                        MySessions(shown: shown) { naming = $0 }
                            .padding(.top, 18)
                    } else {
                        LoggedSessions().padding(.top, 18)   // every finished session (LoggedViews.swift)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                // DEBUG `-route sessions:shelves` / `sessions:fitness` / `sessions:mine` open the tab scrolled there;
                // `?:saved` saves a few premade sessions first, `?:saved:up` then sets World Class
                if DebugRoute.parts.first == "sessions" || DebugRoute.parts.first == "fitness" {
                    if DebugRoute.parts.contains("saved") {
                        for id in ["pro-messi", "tech-juggling", "fit-mbappe", "fit-kante"] { if let p = Library.shared.pro(id) { store.save(p) } }
                        if DebugRoute.parts.contains("up") { store.setLevel(4) }
                    }
                    let to = DebugRoute.parts.first == "fitness" ? "fitness" : DebugRoute.parts[safe: 1] ?? ""
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { scroller.scrollTo(to, anchor: .top) }
                }
            }
            }
            .overlay(alignment: .top) { TopScrim() }
            .tabRoot("Sessions")
            .page()
            .onAppear {
                shown = true
                if DebugRoute.parts.first == "session", path.isEmpty, let s = store.sessions[safe: Int(DebugRoute.parts[safe: 1] ?? "") ?? 0] {
                    tab = "Saved"
                    path.append(SessionRoute.session(s.id))
                    if DebugRoute.parts[safe: 2] == "pick" { path.append(SessionRoute.pick(s.id)) }
                    if DebugRoute.parts[safe: 2] == "run" { ActiveRun.shared.start(RunRequest(items: s.items, name: s.name, session: s.id, pro: s.pro)) }
                }
                if DebugRoute.parts == ["session", "new"] { naming = false }
                // pro:messi, pro:messi:run, pro:tech-juggling, pro:fit-mbappe
                if DebugRoute.parts.first == "pro", path.isEmpty, let raw = DebugRoute.parts[safe: 1] {
                    let id = ["tech-", "fit-", "fx-", "mix-"].contains { raw.hasPrefix($0) } ? raw : "pro-\(raw)"
                    path.append(SessionRoute.pro(id))
                    if DebugRoute.parts[safe: 2] == "run", let p = Library.shared.pro(id) {
                        ActiveRun.shared.start(RunRequest(items: p.items(store.trainingLevel), name: p.title, pro: p.id))
                    }
                }
            }
            .sheet(item: Binding(get: { naming.map { Side(fitness: $0) } }, set: { naming = $0?.fitness })) { side in
                NameSheet(title: side.fitness ? "NAME YOUR WORKOUT" : "NAME YOUR SESSION", button: "CREATE",
                          prompt: side.fitness ? "Sunday Runs" : "Morning Touches") { name in
                    let s = store.newSession(name, fitness: side.fitness)
                    naming = nil
                    tab = "Saved"
                    Haptics.play(.goal)
                    path.append(SessionRoute.session(s.id))
                    path.append(SessionRoute.pick(s.id))
                }
            }
            .sessionDestinations(path: $path)
            .navigationDestination(for: Drill.self) { DrillDetail(drill: $0) }
        }
        // a session just finished: back to the Sessions main page (not the session you just did), on the Sessions tab
        .onChange(of: ActiveRun.shared.finished) { _, _ in
            path = NavigationPath()
            Nav.shared.tab = .profile   // no Sessions tab any more
        }
    }

    private struct Side: Identifiable { let fitness: Bool; var id: Bool { fitness } }
}

extension View {
    /// The session pages, on both stacks (Sessions tab, and a Plan day's session).
    func sessionDestinations(path: Binding<NavigationPath>) -> some View {
        navigationDestination(for: SessionRoute.self) { r in SessionScreen(route: r, path: path) }
    }
}

struct SessionScreen: View {
    let route: SessionRoute
    @Binding var path: NavigationPath
    @Environment(AppStore.self) private var store
    var body: some View {
        switch route {
        case .session(let id): SessionDetail(id: id, path: $path)
        case .pick(let id): SessionPicker(id: id)
        case .run(let id):
            RunLauncher(path: $path, request: RunRequest(items: store.session(id)?.items ?? [], name: store.session(id)?.name, session: id, pro: store.session(id)?.pro))
        case .done: SessionDone(path: $path)
        case .pro(let id):
            if let p = Library.shared.pro(id) { ProSessionDetail(pro: p, path: $path) }
        case .runPro(let id):
            let p = Library.shared.pro(id)
            RunLauncher(path: $path, request: RunRequest(items: p?.items(store.trainingLevel) ?? [], name: p?.title, pro: id))
        }
    }
}

// MARK: - My sessions

/// The second tab: your sessions ? saved ones and ones you made ? Skills and Fitness apart, each ready to change.
struct MySessions: View {
    let shown: Bool
    /// Make a new session on this side (true = fitness).
    let make: (Bool) -> Void
    @Environment(AppStore.self) private var store
    /// A session waiting on "delete it?" (one the player built).
    @State private var removing: Session?

    var body: some View {
        let skills = store.sessions(fitness: false)
        let fitness = store.sessions(fitness: true)
        VStack(alignment: .leading, spacing: 0) {
            if (skills.isEmpty && fitness.isEmpty) || DebugRoute.parts == ["mine", "empty"] {   // DEBUG `-route mine:empty` = the empty page
                EmptySessions { make(false) }
            } else {
                group(title: "Skills", icon: "soccerball", list: skills, fitness: false)
                group(title: "Fitness", icon: "figure.run", list: fitness, fitness: true)
                    .padding(.top, 30)
                    .id("fitness")
            }
        }
        .id("mine")
        .confirmationDialog(removing.map { "Delete \($0.name)?" } ?? "",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible, presenting: removing) { s in
            Button("Delete", role: .destructive) { drop(s) }
        } message: { _ in Text("This can't be undone.") }
    }

    @ViewBuilder
    private func group(title: String, icon: String, list: [Session], fitness: Bool) -> some View {
        SideMark(title: title, icon: icon, count: list.count)
            .padding(.bottom, 12)
        VStack(spacing: 14) {
            ForEach(Array(list.enumerated()), id: \.element.id) { i, s in
                NavigationLink(value: SessionRoute.session(s.id)) { SessionCard(session: s) }
                    .buttonStyle(LipPress())
                    // a saved premade session: its green bookmark takes it back out in one tap
                    .overlay(alignment: .topTrailing) {
                        if s.pro != nil {
                            Button { remove(s) } label: { SavedMark().frame(width: 44, height: 44).contentShape(Rectangle()) }
                                .buttonStyle(.press(.unlatch))
                                .offset(x: 6, y: -8)
                                .accessibilityLabel("Remove \(s.name) from My sessions")
                        }
                    }
                    .contextMenu {
                        Button(s.pro != nil ? "Remove from My sessions" : "Delete session",
                               systemImage: s.pro != nil ? "bookmark.slash" : "trash", role: .destructive) { remove(s) }
                    }
            }
        }
        Button { make(fitness) } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus").font(.system(size: 17, weight: .heavy))
                Text(fitness ? "New fitness session" : "New skills session").font(F.round(17, .semibold))
            }
            .foregroundStyle(C.brand)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(C.brand.opacity(0.55), style: StrokeStyle(lineWidth: 2, dash: [6, 6])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.press(.pop))
        .padding(.top, list.isEmpty ? 0 : 16)
    }

    /// Unsave a premade copy straight away (it comes back with one tap); ask first before deleting your own.
    private func remove(_ s: Session) {
        if s.pro != nil { drop(s) } else { removing = s }
    }
    private func drop(_ s: Session) {
        Haptics.play(.unlatch)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { store.deleteSession(s.id) }
    }
}

/// A section's big label ? SKILLS (ball work) and FITNESS (no ball) are kept apart on the page.
struct SideMark: View {
    let title: String
    let icon: String
    var line: String? = nil
    var count: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(C.brandInk)
                    .frame(width: 34, height: 34)
                    .background(PanelShape(sides: 6).fill(C.brand).overlay(PanelShape(sides: 6).stroke(C.brandInk, lineWidth: 2)))
                VStack(alignment: .leading, spacing: 0) {
                    Disp(title.uppercased(), size: 26)
                    if let line { Text(line).font(F.round(14, .semibold)).foregroundStyle(C.muted) }
                }
                Spacer(minLength: 0)
                if let count { Text("\(count)").font(F.round(15, .semibold)).foregroundStyle(C.muted) }
            }
            // the ball's stitch, run under the label
            Line().stroke(C.creme.opacity(0.14), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                .frame(height: 2)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private struct Line: Shape {
        func path(in r: CGRect) -> Path { Path { $0.move(to: CGPoint(x: 0, y: r.midY)); $0.addLine(to: CGPoint(x: r.maxX, y: r.midY)) } }
    }
}

/// No sessions yet: the ball and one button.
struct EmptySessions: View {
    var fitness = false
    let make: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Mascot(lines: fitness
                   ? ["No fitness sessions yet!", "Runs, planks, core. No ball needed.", "Tap NEW SESSION and let's get fit!"]
                   : ["No sessions yet!", "Save one from Train, or make your own.", "Pick drills, set reps, name it. Easy!"],
                   size: 185)
                .id(fitness)
            Disp(fitness ? "MAKE A FITNESS SESSION" : "MAKE YOUR FIRST SESSION", size: 24)
            Button("+ NEW SESSION", action: make).buttonStyle(.gameLarge).padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(DayHero<EmptyView>.floor)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(C.line, lineWidth: 1))
    }
}

/// A session in My sessions: its picture, the name, size ? and an EDIT tag (tap = its edit page).
struct SessionCard: View {
    let session: Session

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 9) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.name.uppercased())
                        .font(F.display(20))
                        .foregroundStyle(C.creme)
                        .shadow(color: C.charInk, radius: 0, y: 2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(session.items.isEmpty ? "No drills yet" : session.summary)
                        .font(F.round(14, .semibold))
                        .foregroundStyle(C.muted)
                        .lineLimit(1)
                }
                HStack(spacing: 5) {
                    Image(systemName: "pencil").font(.system(size: 11, weight: .heavy))
                    Text("EDIT").font(F.round(12, .bold)).kerning(1.1)
                }
                .foregroundStyle(C.creme2)
                .padding(.horizontal, 10).frame(height: 26)
                .background(Capsule().fill(C.char700).overlay(Capsule().stroke(C.charInk, lineWidth: 2)))
            }
            Spacer(minLength: 0)
            if session.items.isEmpty {
                Image(systemName: "plus.circle.fill").font(.system(size: 30)).foregroundStyle(C.char600).padding(.trailing, 14)
            } else if let id = session.pro, let p = Library.shared.pro(id) {
                ProTile(pro: p)
            } else {
                CoverFan(drills: session.drills)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 14)
        .background(DaySurface(state: .upcoming))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens it to edit or start")
    }
}

// MARK: - a session (its edit page)

struct SessionDetail: View {
    let id: String
    @Binding var path: NavigationPath
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Int?
    @State private var renaming = false
    @State private var deleting = false

    var body: some View {
        if let s = store.session(id) {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Button { renaming = true } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Disp(s.name.uppercased(), size: 32)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.7)
                                Image(systemName: "pencil").font(.system(size: 16, weight: .bold)).foregroundStyle(C.muted)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Rename")
                        Text(s.items.isEmpty ? "Add drills to build it" : "\(s.summary) · \(s.items.reduce(0) { $0 + $1.sets }) sets")
                            .font(F.round(15, .semibold)).foregroundStyle(C.muted)
                            .contentTransition(.numericText())
                        if s.items.count > 1 {
                            Text("Sets: − / +  ·  Hold a drill to move it  ·  Swipe to remove")
                                .font(F.round(13, .medium)).foregroundStyle(C.muted.opacity(0.8))
                                .padding(.top, 4)
                        }
                    }
                    .padding(.top, 4)
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 14, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                Section {
                    ForEach(Array(s.items.enumerated()), id: \.element.drill) { i, it in
                        EditRow(item: it, open: { editing = i }) { n in
                            store.edit(id) { if $0.items.indices.contains(i) { $0.items[i].sets = n; $0.items[i].retime() } }
                        }
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    .onDelete { idx in store.edit(id) { $0.items.remove(atOffsets: idx) } }
                    .onMove { from, to in store.edit(id) { $0.items.move(fromOffsets: from, toOffset: to) } }

                    Button { path.append(SessionRoute.pick(id)) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "plus").font(.system(size: 17, weight: .heavy))
                            Text(s.items.isEmpty ? "Add drills" : "Add more drills").font(F.round(17, .semibold))
                        }
                        .foregroundStyle(C.brand)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(C.brand.opacity(0.55), style: StrokeStyle(lineWidth: 2, dash: [6, 6])))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.press(.pop))
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .screenTitle("SESSION")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Rename", systemImage: "pencil") { renaming = true }
                        Button(s.pro != nil ? "Remove from My sessions" : "Delete session",
                               systemImage: s.pro != nil ? "bookmark.slash" : "trash", role: .destructive) { deleting = true }
                    } label: { Image(systemName: "ellipsis.circle").font(.system(size: 18, weight: .semibold)) }
                }
            }
            .page()
            .dock {
                if !s.items.isEmpty {
                    HStack(spacing: 12) {
                        ShareButton(item: .session(s), size: 64)
                        Button { ActiveRun.shared.start(RunRequest(items: s.items, name: s.name, session: id, pro: s.pro)) } label: { Label("START", systemImage: "play.fill") }
                            .buttonStyle(.gameLarge)
                    }
                }
            }
            .sheet(isPresented: $renaming) {
                NameSheet(title: "RENAME", button: "SAVE", start: s.name) { name in
                    store.edit(id) { $0.name = name.trimmingCharacters(in: .whitespaces).isEmpty ? $0.name : name.trimmingCharacters(in: .whitespaces) }
                    renaming = false
                }
            }
            .sheet(item: Binding(get: { editing.map { Idx(i: $0) } }, set: { editing = $0?.i })) { e in
                if let it = s.items[safe: e.i] {
                    DoseEditor(item: it,
                               change: { new in store.edit(id) { if $0.items.indices.contains(e.i) { $0.items[e.i] = new } } },
                               view: { editing = nil; path.append(Library.shared.drill(it.drill)) },
                               remove: { store.edit(id) { $0.items.removeAll { $0.drill == it.drill } }; editing = nil })
                }
            }
            .confirmationDialog(s.pro != nil ? "Remove \(s.name) from My sessions?" : "Delete \(s.name)?", isPresented: $deleting, titleVisibility: .visible) {
                Button(s.pro != nil ? "Remove" : "Delete", role: .destructive) {
                    Haptics.play(.unlatch)
                    dismiss()
                    store.deleteSession(id)
                }
            } message: { Text(s.pro != nil ? "You can save it again from Train." : "This can't be undone.") }
        } else {
            Color.clear.page().onAppear { dismiss() }   // deleted (e.g. from the session player's trash button)
        }
    }
}

struct Idx: Identifiable { let i: Int; var id: Int { i } }

/// One drill on a session's edit page: tap it for reps + how-to; change the sets right here with ? and +.
struct EditRow: View {
    let item: PlanItem
    let open: () -> Void
    let sets: (Int) -> Void

    var body: some View {
        let d = Library.shared.drill(item.drill)
        HStack(spacing: 10) {
            Button(action: open) {
                HStack(spacing: 12) {
                    Cover(drill: d)
                        .frame(width: 60, height: 70)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(C.charInk, lineWidth: 2))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(d.name.uppercased())
                            .font(F.display(17))
                            .foregroundStyle(C.creme)
                            .shadow(color: C.charInk, radius: 0, y: 2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                        Text(item.reps == nil ? item.dose : "\(item.dose) · \(item.min) min")
                            .font(F.round(13, .semibold))
                            .foregroundStyle(C.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .contentTransition(.numericText())
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Change reps or see how to do it")

            // the sets, right on the row
            HStack(spacing: 6) {
                Button { Haptics.play(.press); sets(max(1, item.sets - 1)) } label: { Image(systemName: "minus").font(.system(size: 13, weight: .heavy)) }
                    .buttonStyle(.gameRound(.charcoal, size: 32))
                    .disabled(item.sets <= 1)
                    .accessibilityLabel("One set fewer")
                VStack(spacing: -2) {
                    Disp("\(item.sets)", size: 22).contentTransition(.numericText())
                    Text(item.sets == 1 ? "SET" : "SETS").font(F.round(9, .bold)).kerning(0.8).foregroundStyle(C.muted)
                }
                .frame(minWidth: 30)
                Button { Haptics.play(.press); sets(min(10, item.sets + 1)) } label: { Image(systemName: "plus").font(.system(size: 13, weight: .heavy)) }
                    .buttonStyle(.gameRound(.brand, size: 32))
                    .disabled(item.sets >= 10)
                    .accessibilityLabel("One more set")
            }
            .animation(.snappy, value: item.sets)
        }
        .padding(8)
        .padding(.trailing, 4)
        .background(DaySurface(state: .upcoming, radius: 18, chalk: false))
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(C.charInk).offset(y: 4))
        .padding(.bottom, 4)
    }
}

/// Change one drill's dose: sets and reps (or seconds / minutes), then the time it adds up to.
struct DoseEditor: View {
    @State var item: PlanItem
    let change: (PlanItem) -> Void
    let view: () -> Void
    let remove: () -> Void

    var body: some View {
        let d = Library.shared.drill(item.drill)
        VStack(spacing: 18) {
            VStack(spacing: 4) {
                Disp(d.name.uppercased(), size: 26)
                Text("\(item.dose) · about \(item.min) min").font(F.round(15, .semibold)).foregroundStyle(C.brand)
                    .contentTransition(.numericText())
            }
            HStack(spacing: 12) {
                Count(label: "SETS", value: item.sets, range: 1...10, step: 1) { item.sets = $0 }
                if let reps = item.reps {
                    let u = item.unit ?? ""
                    let step = u == "s" ? 5 : 1
                    Count(label: u == "s" ? "SECONDS" : u == "min" ? "MINUTES" : u.isEmpty ? "REPS" : u.uppercased(),
                          value: reps, range: (u == "s" ? 5 : 1)...(u == "s" ? 300 : u == "min" ? 30 : 100), step: step) { item.reps = $0 }
                }
            }
            HStack(spacing: 12) {
                Button("HOW TO", action: view).buttonStyle(.game(.charcoal, height: 50, font: 19))
                Button("REMOVE") { Haptics.play(.unlatch); remove() }.buttonStyle(.game(.charcoal, height: 50, font: 19))
            }
        }
        .padding(20)
        .onChange(of: item) { _, _ in
            var it = item
            it.retime()
            if it.min != item.min { item.min = it.min }
            change(it)
        }
        .presentationDetents([.height(item.reps == nil ? 300 : 330)])
        .presentationBackground(C.char850)
        .presentationCornerRadius(28)
    }
}

/// A number with ? and + (holds a press to repeat via the button's own repeat).
struct Count: View {
    let label: String
    let value: Int
    let range: ClosedRange<Int>
    let step: Int
    let set: (Int) -> Void
    var body: some View {
        VStack(spacing: 8) {
            Text(label).font(F.round(12, .bold)).kerning(1.2).foregroundStyle(C.muted).lineLimit(1).minimumScaleFactor(0.7)
            HStack(spacing: 10) {
                Button { set(max(range.lowerBound, value - step)) } label: { Image(systemName: "minus").font(.system(size: 18, weight: .heavy)) }
                    .buttonStyle(.gameRound(.charcoal, size: 44))
                    .disabled(value <= range.lowerBound)
                    .buttonRepeatBehavior(.enabled)
                Disp("\(value)", size: 34)
                    .frame(minWidth: 52)
                    .contentTransition(.numericText())
                Button { set(min(range.upperBound, value + step)) } label: { Image(systemName: "plus").font(.system(size: 18, weight: .heavy)) }
                    .buttonStyle(.gameRound(.brand, size: 44))
                    .disabled(value >= range.upperBound)
                    .buttonRepeatBehavior(.enabled)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(C.char900)
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(C.charInk, lineWidth: 2)))
    }
}

/// Name (or rename) a session.
struct NameSheet: View {
    let title: String
    let button: String
    var start = ""
    var prompt = "Morning Touches"
    let done: (String) -> Void
    @State private var name = ""
    @FocusState private var focus: Bool

    var body: some View {
        VStack(spacing: 18) {
            Disp(title, size: 24)
            TextField("", text: $name, prompt: Text(prompt).foregroundStyle(C.muted))
                .font(F.round(20, .semibold))
                .foregroundStyle(C.creme)
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .focused($focus)
                .onSubmit { done(name) }
                .frame(height: 56)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(C.char950)
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(C.charInk, lineWidth: 2)))
            Button(button) { done(name) }.buttonStyle(.gameLarge)
        }
        .padding(20)
        .onAppear { name = start; focus = true }
        .presentationDetents([.height(250)])
        .presentationBackground(C.char850)
        .presentationCornerRadius(28)
    }
}

/// Adding drills to a session: the whole library.
struct SessionPicker: View {
    let id: String
    @Environment(AppStore.self) private var store
    var body: some View {
        DrillPicker(title: "ADD TO \((store.session(id)?.name ?? "SESSION").uppercased())",
                    fitness: store.session(id)?.isFitness ?? false,
                    picked: Set(store.session(id)?.items.map(\.drill) ?? [])) { store.toggleDrill($0, in: id) }
    }
}
