// The drill library (notes/21, notes/22): a row = the setup picture + the name + one line; a drill page = the drill in
// 3D (the 3D guy plays it when it has an animation, else the still setup ? drag to turn it), the gear as 3D objects,
// the steps, the keys, harder, the next rung.
// Since 2026-10-23 there's no Drills tab: the library opens as the DrillPicker when building a session or a day.
import SwiftUI

/// The whole library to pick from: search, who, grouped by skill (sticky headers), easiest first.
/// Tap a row to add or remove it; the ? opens the drill page.
struct DrillPicker: View {
    let title: String
    let picked: Set<String>
    let toggle: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var who = "All"
    /// Skills = ball work, Fitness = no ball (2026-10-24). Opens on the session's own side.
    @State private var side: String
    private let lib = Library.shared

    init(title: String, fitness: Bool = false, picked: Set<String>, toggle: @escaping (String) -> Void) {
        self.title = title
        self.picked = picked
        self.toggle = toggle
        _side = State(initialValue: fitness ? "Fitness" : "Skills")
    }

    var body: some View {
        let sided = lib.drills.filter { $0.usesBall == (side == "Skills") }
        let pool = who == "All" ? sided : sided.filter { $0.who == who }
        let list = lib.search(query, in: pool)
        ScrollView {
            VStack(spacing: 14) {
                Segments(options: ["Skills", "Fitness"], pick: $side)
                SearchField(text: $query, prompt: "Search \(sided.count) \(side == "Skills" ? "skill" : "fitness") drills")
                Segments(options: ["All", "Solo", "Partner", "Group"], pick: $who)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)

            if list.isEmpty {
                Text(query.isEmpty ? "No drills here." : "Nothing for \"\(query)\". Try \"wall\", \"turn\" or \"keeper\".")
                    .font(F.round(16)).foregroundStyle(C.muted)
                    .padding(30)
            } else {
                let groups = Dictionary(grouping: list, by: \.skill)
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    // the Fitness side leads with its own groups (runs, core, agility, stretches), then footwork drills
                    let lead = side == "Fitness" ? ["Runs", "Core", "Fitness", "Stretching"] : []
                    // DEBUG `-route session:0:pick:dribbling` opens on the Dribbling group (App Store screenshot, notes/19)
                    let skip: Set<String> = DebugRoute.parts.contains("dribbling") ? ["Ball mastery"] : []
                    ForEach((lead + lib.categories.filter { !lead.contains($0) && !skip.contains($0) }).filter { groups[$0] != nil }, id: \.self) { c in
                        Section {
                            ForEach(groups[c]!) { d in
                                let on = picked.contains(d.id)
                                HStack(spacing: 0) {
                                    Button {
                                        Haptics.play(on ? .unlatch : .pop)
                                        toggle(d.id)
                                    } label: {
                                        HStack(spacing: 0) {
                                            DrillRow(drill: d).padding(.trailing, -10)
                                            Image(systemName: on ? "checkmark.circle.fill" : "plus.circle")
                                                .font(.system(size: 27, weight: .semibold))
                                                .foregroundStyle(on ? C.brand : C.muted)
                                                .contentTransition(.symbolEffect(.replace))
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.press(.stud))
                                    NavigationLink(value: d) {
                                        Image(systemName: "info.circle").font(.system(size: 20, weight: .semibold)).foregroundStyle(C.char600)
                                            .frame(width: 44, height: 62)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.trailing, 8)
                                }
                            }
                            Color.clear.frame(height: 18)
                        } header: {
                            SkillHeader(title: c, count: groups[c]!.count)
                        }
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .screenTitle(title)
        .page()
        .dock {
            Button(picked.isEmpty ? "DONE" : "DONE · \(picked.count) DRILL\(picked.count == 1 ? "" : "S")") { dismiss() }
                .buttonStyle(.gameLarge)
        }
    }
}

/// A sticky skill header over its rows: the name in the bubble face + how many.
struct SkillHeader: View {
    let title: String
    let count: Int
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Disp(title.uppercased(), size: 22)
            Spacer()
            Text("\(count)").font(F.round(15, .bold)).foregroundStyle(C.muted)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(C.char900)
    }
}

/// One row of the list: the setup picture, the name, one line.
struct DrillRow: View {
    let drill: Drill
    var body: some View {
        HStack(spacing: 14) {
            Cover(drill: drill)
                .frame(width: 74, height: 74)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(C.charInk, lineWidth: 2))
            VStack(alignment: .leading, spacing: 3) {
                Text(drill.name)
                    .font(F.round(18, .bold))
                    .foregroundStyle(C.creme)
                    .lineLimit(1)
                Text("\(drill.levelName) · \(drill.who) · \(drill.min) min")
                    .font(F.round(14, .semibold))
                    .foregroundStyle(C.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

/// A drill's thumbnail: a frame of its video, else its flat board, else the icon ball (2026-10-30: no more Covers stills).
struct Cover: View {
    let drill: Drill
    var body: some View {
        ZStack {
            C.char900
            if DrillVideo.url(drill.id) != nil {
                // a video drill: a frame of its own video (the current 3D guy in the kit), never the old Covers still
                // every drill has a video now (2026-10-30), so no ? badge ? it sat on the feet and the ball
                DrillFrameImage(id: drill.id) { IconBall(size: 28) }
            } else if let board = drill.board {
                DrillBoard(board: board)  // no video: the flat board
            } else {
                IconBall(size: 30)
            }
        }
        .clipped()
    }
}

/// A quiet capsule of choices (one picked, green).
struct Segments: View {
    let options: [String]
    @Binding var pick: String
    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { o in
                Button {
                    Haptics.play(.press)
                    pick = o
                } label: {
                    Text(o.uppercased())
                        .font(F.round(13, .bold)).kerning(1)
                        .foregroundStyle(pick == o ? C.brandInk : C.creme)
                        .frame(maxWidth: .infinity).frame(height: 36)
                        .background(Capsule().fill(pick == o ? C.brand : .clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(C.char800).overlay(Capsule().stroke(C.charInk, lineWidth: 2)))
    }
}

struct DrillDetail: View {
    let drill: Drill
    @Environment(AppStore.self) private var store
    @State private var picking = false
    @State private var added: String?
    /// The Start Drill timer (2026-11-18). Test builds: `-route tab:training:drill.<id>:timer`.
    @State private var timing = DebugRoute.parts.contains("timer")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // a drill the 3D guy plays gets a taller box (the players stay big); a still setup keeps 330
                StageBox(params: .setup(id: drill.id), height: drill.hasVideo ? 420 : 330, interactive: true)
                    .overlay {
                        // the 3D floor fades into the page at both edges (no hard seam)
                        VStack(spacing: 0) {
                            LinearGradient(colors: [C.char900, C.char900.opacity(0)], startPoint: .top, endPoint: .bottom).frame(height: 40)
                            Spacer()
                            LinearGradient(colors: [C.char900.opacity(0), C.char900], startPoint: .top, endPoint: .bottom).frame(height: 40)
                        }
                        .allowsHitTesting(false)
                    }

                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Disp(drill.name.uppercased(), size: 32)
                        Text("\(drill.levelName) · \(drill.who) · \(drill.min) min · \(drill.space)")
                            .font(F.round(15, .semibold)).foregroundStyle(C.muted)
                    }

                    if !drill.kit.isEmpty {
                        Part("YOU NEED") { GearRow(kit: drill.kit) }
                    }

                    Part("HOW TO DO IT") {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(Array(drill.how.enumerated()), id: \.offset) { i, step in
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Text("\(i + 1)").font(F.display(22)).foregroundStyle(C.brand).frame(width: 20, alignment: .leading)
                                    Text(step).font(F.round(18)).foregroundStyle(C.creme)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            (Text("Do it: ").foregroundColor(C.creme2) + Text(drill.reps).foregroundColor(C.brand))
                                .font(F.round(18, .bold))
                                .padding(.top, 2)
                        }
                    }

                    Part("KEYS") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(drill.points, id: \.self) { p in
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Circle().fill(C.brand).frame(width: 8, height: 8).offset(y: -2)
                                    Text(p).font(F.round(17)).foregroundStyle(C.creme)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }

                    if let h = drill.progression {
                        Part("HARDER") {
                            Text(h).font(F.round(17)).foregroundStyle(C.creme2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if let next = Library.shared.next(after: drill) {
                        NavigationLink(value: next) {
                            HStack(spacing: 14) {
                                Cover(drill: next).frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("NEXT UP").font(F.round(12, .bold)).foregroundStyle(C.muted).kerning(1)
                                    Text(next.name.uppercased()).font(F.display(20)).foregroundStyle(C.creme).lineLimit(1).minimumScaleFactor(0.7)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 15, weight: .bold)).foregroundStyle(C.muted)
                            }
                            .gameCard(padding: 10, radius: 18)
                        }
                        .buttonStyle(.press(.stud))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .top) { TopScrim() }
        .page()
        .screenTitle("")
        .dock {
            // 2026-11-18: no more one-tap "Mark as done". The drill is trained with the timer and earns XP for the time.
            let done = Lab.shared.isDone(drill.id)
            VStack(spacing: 6) {
                Button { timing = true } label: { Label(done ? "Train again" : "Start Drill", systemImage: "play.fill") }
                    .buttonStyle(.gameLarge(.brand, feel: .kick))
                if done {
                    Label("Done today", systemImage: "checkmark.circle.fill").font(F.round(13, .bold)).foregroundStyle(C.brandHi)
                }
            }
        }
        .fullScreenCover(isPresented: $timing) { DrillTimer(drill: drill) }
        .sheet(isPresented: $picking) {
            DayPicker { day in
                store.add(drill.id, to: day)
                added = day
                picking = false
                Haptics.play(.goal)
            }
            .presentationDetents([.height(250)])
            .presentationBackground(C.char850)
            .presentationCornerRadius(28)
        }
    }
}

/// A labelled part of the drill page.
struct Part<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(F.round(13, .bold)).kerning(1.4).foregroundStyle(C.muted)
            content
        }
    }
}

/// The equipment as 3D objects, each with its count ("5 cones").
struct GearRow: View {
    let kit: [GearPiece]
    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(kit, id: \.self) { g in
                    VStack(spacing: 6) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(C.char850)
                                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(C.charInk, lineWidth: 2))
                            if let img = g.image {
                                Image(uiImage: img).resizable().scaledToFit().padding(8)
                            } else {
                                // no picture for this piece: a plain symbol instead of a letter (2026-11-13)
                                let l = g.label.lowercased()
                                Image(systemName: l.contains("cone") ? "cone.fill" : l.contains("ball") ? "soccerball"
                                      : l.contains("goal") ? "sportscourt.fill" : l.contains("wall") ? "square.fill" : "checkmark")
                                    .font(.system(size: 26, weight: .semibold)).foregroundStyle(C.brandHi)
                            }
                        }
                        .frame(width: 76, height: 76)
                        Text(g.label).font(F.round(13, .semibold)).foregroundStyle(C.creme2)
                            .lineLimit(2).multilineTextAlignment(.center)
                            .frame(width: 80)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }
}

/// "Which day?" ? seven big day buttons.
struct DayPicker: View {
    var title = "WHICH DAY?"
    let pick: (String) -> Void
    var body: some View {
        VStack(spacing: 20) {
            Disp(title, size: 24)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 12) {
                ForEach(DAYS, id: \.self) { d in
                    Button(d) { pick(d) }
                        .buttonStyle(.game(d == todayKey() ? .brand : .charcoal, height: 50, font: 19, feel: .pop))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
    }
}

// MARK: - Start Drill timer (2026-11-18)

/// The drill, trained for real: Start the clock when you begin, pause if you need to, Finish when you're done. XP is
/// worked out from the time trained and the drill's level (Lab.drillXP), then shown. Replaces the old "Mark as done".
/// Test builds: `-route tab:training:drill.<id>:timer` opens it, add `:running` for a clock part-way, `:done` for the result.
struct DrillTimer: View {
    let drill: Drill
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// When the clock was last started (nil = stopped), and the time banked before the last pause.
    @State private var startedAt: Date?
    @State private var banked: TimeInterval = DebugRoute.parts.contains("running") ? 154 : 0
    @State private var earned: Lab.Earned? = DebugRoute.parts.contains("timer") && DebugRoute.parts.contains("done")
        ? Lab.Earned(drill: 27, session: 0, seconds: 312) : nil
    @State private var quitting = false

    private var target: TimeInterval { Double(drill.min) * 60 }
    private var running: Bool { startedAt != nil }
    private func elapsed(_ now: Date) -> TimeInterval { banked + (startedAt.map { now.timeIntervalSince($0) } ?? 0) }

    var body: some View {
        ZStack {
            C.char900.ignoresSafeArea()
            if let e = earned { result(e) } else { clock }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .confirmationDialog("Stop this drill?", isPresented: $quitting, titleVisibility: .visible) {
            Button("Finish and get my XP") { finish() }
            Button("Leave without saving", role: .destructive) { dismiss() }
            Button("Keep training", role: .cancel) {}
        } message: { Text("Your time only counts if you finish.") }
    }

    // the clock

    private var clock: some View {
        VStack(spacing: 18) {
            HStack {
                Button {
                    if elapsed(Date()) > 0 { quitting = true } else { dismiss() }
                } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(C.creme)
                        .frame(width: 44, height: 44).background(Circle().fill(C.char800))
                }
                .accessibilityLabel("Close")
                Spacer()
                Label("\(drill.min) min drill", systemImage: "clock").font(F.round(14, .bold)).foregroundStyle(C.muted)
            }
            VStack(spacing: 6) {
                Text(drill.name.uppercased()).font(F.display(30)).foregroundStyle(C.creme)
                    .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.6)
                Text(drill.reps).font(F.round(15, .semibold)).foregroundStyle(C.muted).multilineTextAlignment(.center)
            }
            TimelineView(.periodic(from: .now, by: 0.25)) { tl in
                let t = elapsed(tl.date)
                VStack(spacing: 14) {
                    ZStack {
                        Circle().stroke(C.char800, lineWidth: 16)
                        Circle().trim(from: 0, to: min(1, t / max(target, 1)))
                            .stroke(LinearGradient(colors: [C.brandHi, C.brand], startPoint: .top, endPoint: .bottom),
                                    style: StrokeStyle(lineWidth: 16, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 4) {
                            Text(Self.clock(t)).font(.system(size: 64, weight: .heavy, design: .rounded)).monospacedDigit()
                                .foregroundStyle(C.creme)
                            Text(t >= target ? "Full time! +5 XP bonus" : "\(Self.clock(target - t)) to full time")
                                .font(F.round(14, .bold)).foregroundStyle(t >= target ? C.gold : C.muted)
                        }
                    }
                    .frame(width: 250, height: 250)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(Int(t) / 60) minutes \(Int(t) % 60) seconds trained")
                    Label(t < Lab.minDrillSeconds ? "Train 30 seconds to start earning XP" : "+\(Lab.drillXP(drill, seconds: t)) XP so far",
                          systemImage: "bolt.fill")
                        .font(F.round(16, .heavy)).foregroundStyle(t < Lab.minDrillSeconds ? C.muted : C.brandHi)
                }
            }
            if let tip = drill.points.first {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lightbulb.fill").foregroundStyle(C.gold)
                    Text(tip).font(F.round(15, .medium)).foregroundStyle(C.creme2).fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(C.char850))
            }
            Spacer(minLength: 0)
            buttons
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    @ViewBuilder private var buttons: some View {
        if !running && banked == 0 {
            Button { start() } label: { Label("Start", systemImage: "play.fill") }
                .buttonStyle(.gameLarge(.brand, feel: .kick))
        } else {
            HStack(spacing: 12) {
                Button {
                    if running { pause() } else { start() }
                } label: { Label(running ? "Pause" : "Resume", systemImage: running ? "pause.fill" : "play.fill") }
                    .buttonStyle(.game(.charcoal, height: 64, font: 22))
                TimelineView(.periodic(from: .now, by: 1)) { tl in
                    Button { finish() } label: { Label("Finish", systemImage: "flag.checkered") }
                        .buttonStyle(.game(.brand, height: 64, font: 22, feel: .goal))
                        .disabled(elapsed(tl.date) < Lab.minDrillSeconds)
                }
            }
        }
    }

    private func start() { startedAt = Date(); Haptics.play(.stud) }
    private func pause() { banked = elapsed(Date()); startedAt = nil }
    private func finish() {
        let t = elapsed(Date())
        startedAt = nil; banked = t
        guard t >= Lab.minDrillSeconds else { dismiss(); return }
        let got = Lab.shared.complete(drill, store: store, seconds: t)
        withAnimation(.snappy) { earned = got }
        Haptics.play(.goal)
    }

    static func clock(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.rounded(.down)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    // the result

    private func result(_ e: Lab.Earned) -> some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 76, weight: .bold)).foregroundStyle(C.brand)
                .shadow(color: C.brand.opacity(0.6), radius: 24)
            Text("DRILL DONE").font(F.display(34)).foregroundStyle(C.creme)
            Text(drill.name).font(F.round(17, .semibold)).foregroundStyle(C.muted).multilineTextAlignment(.center)
            Text("+\(e.total) XP").font(.system(size: 56, weight: .heavy, design: .rounded)).foregroundStyle(C.gold)
                .monospacedDigit()
            VStack(spacing: 10) {
                row("Time trained", Self.clock(e.seconds))
                row("Drill XP", "+\(e.drill)")
                if e.session > 0 { row("Today's session done", "+\(e.session)") }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(C.char850))
            Spacer(minLength: 0)
            Button("Done") { dismiss() }.buttonStyle(.gameLarge)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private func row(_ a: String, _ b: String) -> some View {
        HStack {
            Text(a).font(F.round(15, .semibold)).foregroundStyle(C.creme2)
            Spacer()
            Text(b).font(F.round(16, .heavy)).foregroundStyle(C.creme).monospacedDigit()
        }
    }
}
