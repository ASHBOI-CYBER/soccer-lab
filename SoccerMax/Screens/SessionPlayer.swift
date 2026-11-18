// The session player (2026-10-28): "When a drill is started, make a live activity, full screen the session, and put
// a segmented bar on top based on how many drills the person is doing. Then make the image or video full screened for
// that drill with liquid glass buttons in the top right for descriptions/text? A timer should be going on the whole
// time, when finished the user should click pause on the timer then a resume and finished button should appear and
// next drill goes on. Also add a second liquid glass button for removing the session/deleting it."
//
// Every START (a session, a premade session, today's plan) opens this over the whole app (`ActiveRun`). Nothing is
// written until the session is FINISHED (or "End and save"): then each drill's real time goes into the log, the
// session lands in LOGGED (Sessions tab + Settings), XP, the team feed ? notes/19 "SESSION PLAYER".
import ActivityKit
import PostHog
import SwiftUI

struct RunRequest: Identifiable {
    let id = UUID()
    let items: [PlanItem]
    let name: String?
    /// The player's session this came from (the trash button can delete it from My sessions).
    var session: String? = nil
    var pro: String? = nil
    /// Today's plan (Plan tab): FINISH also marks the day done.
    var planDay = false
}

/// The session running full screen right now (one at a time, over every tab).
@Observable
final class ActiveRun {
    static let shared = ActiveRun()
    var request: RunRequest?
    /// Goes up each time a session is FINISHED ? the Sessions tab pops back to its main page behind the done screen
    /// (2026-10-30: "return to the sessions page instead of going back to the same saved session you just completed").
    var finished = 0

    func start(_ r: RunRequest) {
        guard !r.items.isEmpty else { return }
        PostHogSDK.shared.capture("session_started", properties: [
            "drill_count": r.items.count,
            "session_type": r.planDay ? "plan" : r.pro == nil ? "custom" : "premade"
        ])
        if TEAMS_ON { Task { @MainActor in SessionSpot.shared.refresh() } }   // MAP tab: where this session is played
        Haptics.play(.kick)
        request = r
    }
}

// MARK: - the Live Activity

enum LiveRun {
    private static var activity: Activity<SessionActivityAttributes>?

    static func start(_ session: String, _ state: SessionActivityAttributes.ContentState) {
        endAll()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        activity = try? Activity.request(attributes: SessionActivityAttributes(session: session),
                                         content: .init(state: state, staleDate: nil), pushType: nil)
    }
    static func update(_ state: SessionActivityAttributes.ContentState) {
        guard let a = activity else { return }
        Task { await a.update(.init(state: state, staleDate: nil)) }
    }
    static func end() {
        let a = activity
        activity = nil
        Task { await a?.end(nil, dismissalPolicy: .immediate) }
    }
    /// Any left over from a run the app was closed in the middle of.
    static func endAll() {
        let old = Activity<SessionActivityAttributes>.activities.filter { $0.id != activity?.id }
        Task { for a in old { await a.end(nil, dismissalPolicy: .immediate) } }
    }
}

// MARK: - the player

struct SessionPlayer: View {
    let req: RunRequest
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var idx = 0
    /// Running since (nil = paused). The clock = `banked` + time since this.
    @State private var since: Date? = Date()
    @State private var banked: TimeInterval = 0
    @State private var done: [(item: PlanItem, seconds: Double)] = []
    @State private var info = false
    @State private var ending = false
    @State private var finished = false
    /// The drill's animation is frozen (its own pause, apart from the timer) ? 2026-10-29: "allow the user to pause
    /// the animation playing". Tap the video or the glass play/pause button; a new drill always starts playing.
    @State private var still = false

    private var item: PlanItem { req.items[min(idx, req.items.count - 1)] }
    private var drill: Drill { Library.shared.drill(item.drill) }
    /// Only Blender videos move ? the coach boards are still pictures, so they get no pause.
    private var hasVideo: Bool { DrillVideo.url(item.drill) != nil }
    private func toggleAnimation() {
        Haptics.play(.press)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { still.toggle() }
    }
    private var isLast: Bool { idx >= req.items.count - 1 }
    private var title: String { req.name ?? "Training" }
    private func elapsed(_ now: Date = Date()) -> TimeInterval { banked + (since.map { now.timeIntervalSince($0) } ?? 0) }

    var body: some View {
        ZStack {
            C.char900.ignoresSafeArea()
            if finished {
                NavigationStack {
                    SessionDone(path: .constant(NavigationPath())) { dismiss() }
                }
                .transition(.opacity)
            } else {
                stage
            }
        }
        .statusBarHidden(!finished)
        .onAppear {
            // DEBUG `-route session:0:run:paused` opens straight on the paused state
            if DebugRoute.parts.contains("paused") { banked = 74; since = nil }
            // DEBUG `?:run:still` = drill 2 (a video) with its animation paused; `?:run:drill2` = drill 2 playing
            if DebugRoute.parts.contains("still") { idx = min(1, req.items.count - 1); still = true }
            if DebugRoute.parts.contains("drill2") { idx = min(1, req.items.count - 1) }
            // DEBUG `?:run:finish` = 25 min of drill 1 done, then FINISH ? the done screen (and the Sessions pop)
            if DebugRoute.parts.contains("finish") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { done = [(item, 25 * 60)]; save() }
            }
            LiveRun.start(title, liveState)
        }
        .sheet(isPresented: $info) { DrillInfo(drill: drill, item: item, index: idx, count: req.items.count) }
        .confirmationDialog("End \(title)?", isPresented: $ending, titleVisibility: .visible) {
            if !done.isEmpty || elapsed() >= 5 {
                Button("End and save") { endAndSave() }
            }
            Button("Discard session", role: .destructive) { close() }
            if let id = req.session, let s = store.session(id) {
                Button(s.pro != nil ? "Remove from My sessions" : "Delete \(s.name)", role: .destructive) {
                    close()
                    store.deleteSession(id)
                }
            }
        } message: {
            Text("Discard = nothing is logged. Delete also takes it out of My sessions.")
        }
    }

    // MARK: the full-screen drill

    private var stage: some View {
        ZStack {
            DrillStageView(id: drill.id, fit: true, paused: still)
                .id(drill.id)
                .ignoresSafeArea()
                .transition(.opacity)
                .contentShape(Rectangle())
                .onTapGesture { if hasVideo { toggleAnimation() } }

            // paused animation: a big play mark in the middle (tap it, or the video, to play on)
            if still && hasVideo {
                Image(systemName: "play.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(C.creme)
                    .frame(width: 86, height: 86)
                    .modifier(GlassCircleBig())
                    .transition(.scale(0.7).combined(with: .opacity))
                    .allowsHitTesting(false)
            }

            // dark fades so the bar, buttons and timer read on any picture
            VStack(spacing: 0) {
                LinearGradient(colors: [C.char950.opacity(0.85), C.char950.opacity(0)], startPoint: .top, endPoint: .bottom).frame(height: 210)
                Spacer()
                LinearGradient(colors: [C.char950.opacity(0), C.char950.opacity(0.92), C.char950], startPoint: .top, endPoint: .bottom).frame(height: 400)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                TimelineView(.periodic(from: .now, by: 0.5)) { t in
                    let frac = min(1, elapsed(t.date) / Double(max(1, item.min) * 60))
                    SegmentBar(count: req.items.count, index: idx, progress: frac)
                }
                .padding(.top, 8)

                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DRILL \(idx + 1) OF \(req.items.count)").font(F.round(13, .bold)).kerning(1.2).foregroundStyle(C.brand)
                        Text(title.uppercased()).font(F.round(15, .bold)).foregroundStyle(C.creme2).lineLimit(1)
                    }
                    Spacer()
                    if hasVideo {
                        GlassIcon(symbol: still ? "play.fill" : "pause.fill",
                                  label: still ? "Play the animation" : "Pause the animation") { toggleAnimation() }
                    }
                    GlassIcon(symbol: "text.alignleft", label: "How to do this drill") { info = true }
                    GlassIcon(symbol: "trash", label: "End or delete the session") { ending = true }
                }
                .padding(.top, 14)

                Spacer()
                bottom
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private var bottom: some View {
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                Disp(drill.name.uppercased(), size: 34)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                Text(item.dose).font(F.round(18, .semibold)).foregroundStyle(C.brand)
            }

            TimelineView(.periodic(from: .now, by: 1)) { t in
                Text(clock(Int(elapsed(t.date))))
                    .font(.system(size: 76, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(since == nil ? C.gold : C.creme)
                    .contentTransition(.numericText())
            }
            .accessibilityLabel("Drill timer")

            if since != nil {
                Button { pause() } label: { Label("PAUSE", systemImage: "pause.fill") }
                    .buttonStyle(.gameLarge(.charcoal, feel: .latch))
                    .transition(.scale(0.9).combined(with: .opacity))
            } else {
                HStack(spacing: 12) {
                    Button { resume() } label: { Label("RESUME", systemImage: "play.fill") }
                        .buttonStyle(.gameLarge(.charcoal, feel: .latch))
                    Button { next() } label: { Label(isLast ? "FINISH" : "DONE", systemImage: "checkmark") }
                        .buttonStyle(.gameLarge(isLast ? .gold : .brand, feel: .goal))
                }
                .transition(.scale(0.9).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: since == nil)
    }

    // MARK: timer + flow

    private var liveState: SessionActivityAttributes.ContentState {
        let e = elapsed()
        return .init(drill: drill.name, dose: item.dose, index: idx, count: req.items.count,
                     startedAt: Date().addingTimeInterval(-e), paused: since == nil ? Int(e) : nil)
    }

    private func pause() {
        banked = elapsed()
        since = nil
        LiveRun.update(liveState)
    }
    private func resume() {
        since = Date()
        LiveRun.update(liveState)
    }
    /// DONE: this drill's time is kept, the next drill starts with its clock running.
    private func next() {
        done.append((item, elapsed()))
        if isLast { save(); return }
        withAnimation(.easeInOut(duration: 0.3)) {
            idx += 1
            still = false
            banked = 0
            since = Date()
        }
        LiveRun.update(liveState)
    }
    private func endAndSave() {
        if elapsed() >= 5 { done.append((item, elapsed())) }
        save()
    }

    /// Everything is written here, once: drill times ? today's log, the session ? LOGGED + XP + the team feed.
    private func save() {
        LiveRun.end()
        for d in done { store.logDrill(d.item, seconds: d.seconds) }
        let secs = Int(done.reduce(0) { $0 + $1.seconds }.rounded())
        let logged = done.map { LoggedDrill(drill: $0.item.drill, name: Library.shared.drill($0.item.drill).name, dose: $0.item.dose, seconds: Int($0.seconds.rounded())) }
        let m = Double(secs) / 60
        let sessionType = req.planDay ? "plan" : req.pro == nil ? "custom" : "premade"
        PostHogSDK.shared.capture("session_completed", properties: [
            "completed_drill_count": done.count,
            "duration_seconds": secs,
            "session_type": sessionType
        ])
        PostHogExportLogger.info("training session completed", attributes: [
            "completed_drill_count": done.count,
            "duration_seconds": secs,
            "session_type": sessionType
        ])
        store.complete(req.name, minutes: m, seconds: secs, drills: logged)
        Team.shared.log(session: title, minutes: Int(m.rounded()), items: done.map(\.item), pro: req.pro)
        Team.shared.syncStats(store)
        if req.planDay { store.finish(todayKey()) }
        withAnimation(.easeInOut(duration: 0.35)) { finished = true }
        ActiveRun.shared.finished += 1
    }

    private func close() {
        LiveRun.end()
        Haptics.play(.unlatch)
        dismiss()
    }
}

/// One segment per drill: done = green, this one fills with its time (drill minutes), the rest wait.
struct SegmentBar: View {
    let count: Int
    let index: Int
    let progress: Double
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<max(1, count), id: \.self) { i in
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(C.creme.opacity(0.22))
                        Capsule().fill(C.brand)
                            .frame(width: g.size.width * (i < index ? 1 : i == index ? max(0.04, progress) : 0))
                    }
                }
                .frame(height: 6)
            }
        }
        .animation(.linear(duration: 0.5), value: progress)
        .animation(.spring(response: 0.35), value: index)
        .accessibilityElement()
        .accessibilityLabel("Drill \(index + 1) of \(count)")
    }
}

/// A round Liquid Glass button (iOS 26); frosted material before that.
struct GlassIcon: View {
    let symbol: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button {
            Haptics.play(.press)
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(C.creme)
                .frame(width: 50, height: 50)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .modifier(GlassCircle())
        .accessibilityLabel(label)
    }
}

private struct GlassCircleBig: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .circle)
        } else {
            content.background(.ultraThinMaterial, in: Circle())
        }
    }
}

private struct GlassCircle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .circle)
        } else {
            content.background(.ultraThinMaterial, in: Circle())
        }
    }
}

// MARK: - everything about the drill

/// The text button: every word the drill has ? what you need, the space, setup, steps, the dose, keys, harder.
struct DrillInfo: View {
    let drill: Drill
    let item: PlanItem
    let index: Int
    let count: Int

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("DRILL \(index + 1) OF \(count)").font(F.round(13, .bold)).kerning(1.2).foregroundStyle(C.brand)
                    Disp(drill.name.uppercased(), size: 30)
                    Text("\(drill.levelName) · \(drill.who) · about \(item.min) min").font(F.round(15, .semibold)).foregroundStyle(C.muted)
                }

                Part("DO IT") {
                    Text(item.dose).font(F.round(20, .bold)).foregroundStyle(C.brand)
                }

                Part("YOU NEED") {
                    VStack(alignment: .leading, spacing: 12) {
                        if !drill.kit.isEmpty { GearRow(kit: drill.kit) }
                        line("Gear", drill.gear.isEmpty ? "Nothing" : drill.gear.joined(separator: ", "))
                        line("Space", drill.space)
                        line("Who", drill.who)
                    }
                }

                Part("SETUP") { para(drill.setup) }

                Part("HOW TO DO IT") {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(drill.how.enumerated()), id: \.offset) { i, step in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text("\(i + 1)").font(F.display(22)).foregroundStyle(C.brand).frame(width: 20, alignment: .leading)
                                para(step)
                            }
                        }
                    }
                }

                if !drill.points.isEmpty {
                    Part("KEYS") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(drill.points, id: \.self) { p in
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Circle().fill(C.brand).frame(width: 8, height: 8).offset(y: -2)
                                    para(p)
                                }
                            }
                        }
                    }
                }

                if let h = drill.progression { Part("HARDER") { para(h) } }

                if !drill.stats.isEmpty {
                    Part("BUILDS") { para(drill.stats.compactMap { STAT_NAME[$0] }.joined(separator: " · ")) }
                }
            }
            .padding(20)
            .padding(.top, 8)
        }
        .scrollIndicators(.hidden)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(C.char900)
    }

    private func para(_ s: String) -> some View {
        Text(s).font(F.round(17)).foregroundStyle(C.creme).fixedSize(horizontal: false, vertical: true)
    }
    private func line(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(k.uppercased()).font(F.round(13, .bold)).kerning(1).foregroundStyle(C.muted).frame(width: 60, alignment: .leading)
            Text(v).font(F.round(17)).foregroundStyle(C.creme).fixedSize(horizontal: false, vertical: true)
        }
    }
}
