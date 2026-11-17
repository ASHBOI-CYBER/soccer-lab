// TRAINING tab, Drills and Fitness parts (2026-11-15). The tab now has three parts: PLAN (this week, today's
// session, the Fix List - TrainingTab.swift), DRILLS (tools, ready-made sessions, quick drills by skill) and FITNESS
// (live run, workouts, fitness drills, the free session logger). Plus the voice drills: the phone calls out moves or
// cone colours and the player reacts (AVSpeechSynthesizer, on the phone, no internet).
import AVFoundation
import SwiftUI

enum TrainingPart: String, CaseIterable, Identifiable {
    case plan = "Plan", drills = "Drills", fitness = "Fitness"
    var id: String { rawValue }
    var icon: String { self == .plan ? "calendar" : self == .drills ? "soccerball" : "bolt.fill" }
}

struct TrainingPartPicker: View {
    @Binding var part: TrainingPart
    var body: some View {
        HStack(spacing: 4) {
            ForEach(TrainingPart.allCases) { p in
                let on = p == part
                Button {
                    withAnimation(.snappy) { part = p }
                    Haptics.play(.stud)
                } label: {
                    Label(p.rawValue, systemImage: p.icon)
                        .font(F.round(14, .bold))
                        .foregroundStyle(on ? Color.white : C.creme2)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(Capsule().fill(on ? C.brand : Color.clear))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(C.char800).overlay(Capsule().stroke(C.line, lineWidth: 1)))
    }
}

// MARK: - DRILLS

struct TrainingDrillsPart: View {
    @Environment(AppStore.self) private var store
    // test builds: `-route tab:training:drillstab:voice` (cones) / `:voicemoves` open a voice drill
    @State private var voice: VoiceDrill.Mode? = DebugRoute.parts.contains("voicemoves") ? .moves : DebugRoute.parts.contains("voice") ? .cones : nil
    @State private var skill = "For you"

    private var lib: Library { Library.shared }
    private var sessions: [ProSession] { lib.technique + lib.hybrid }
    /// Ball-work skills (no-ball ones live under Fitness).
    private var skills: [String] {
        ["For you"] + lib.categories.filter { c in
            !["Fitness", "Runs", "Core", "Stretching"].contains(c) && lib.drills.contains { $0.skill == c }
        }
    }
    private var quick: [Drill] {
        if skill == "For you" {
            let ids = LabPlan.focus(LabPlan.group(store.answers.position)) + LabPlan.core
            var seen = Set<String>()
            return ids.filter { lib.has($0) && seen.insert($0).inserted }.map { lib.drill($0) }
        }
        return lib.drills.filter { $0.skill == skill }.sorted { $0.level < $1.level }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 12) {
                LabKicker("TRAINING TOOLS")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    tool("Live Callouts", "Voice-called moves, you react", "speaker.wave.2.fill", Color(hex: 0xFF9F43)) { voice = .moves }
                    tool("Cone Reaction", "Hands-free colour calls", "triangle.fill", Color(hex: 0x2BB673)) { voice = .cones }
                    NavigationLink(value: LabRoute.drills) {
                        toolFace("Drill Library", "Every drill, \(lib.drills.count) of them", "square.grid.2x2.fill", C.brand)
                    }
                    .buttonStyle(.plain)
                    tool("AI Coach", "Ask anything", "sparkles", Color(hex: 0xA78BFA)) { Nav.shared.coach = true }
                }
            }

            if !sessions.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    LabKicker("READY-MADE SESSIONS")
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(sessions) { s in sessionCard(s) }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    LabKicker("QUICK DRILLS")
                    Spacer()
                    NavigationLink(value: LabRoute.drills) {
                        Text("Browse all").font(F.round(14, .bold)).foregroundStyle(C.brandHi)
                    }
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(skills, id: \.self) { s in labChip(s, on: s == skill) { skill = s } }
                    }
                }
                .scrollIndicators(.hidden)
                VStack(spacing: 10) {
                    ForEach(quick) { d in LabDrillRow(drill: d) }
                }
            }
        }
        .fullScreenCover(item: $voice) { m in VoiceDrill(mode: m) }
    }

    private func tool(_ title: String, _ sub: String, _ icon: String, _ tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) { toolFace(title, sub, icon, tint) }.buttonStyle(.plain)
    }

    private func toolFace(_ title: String, _ sub: String, _ icon: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(F.round(16, .bold)).foregroundStyle(C.creme)
                Text(sub).font(F.round(12, .semibold)).foregroundStyle(C.muted).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(C.char800)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(C.line, lineWidth: 1)))
    }

    private func sessionCard(_ s: ProSession) -> some View {
        let level = min(max(store.trainingLevel, 0), max(0, s.levels.count - 1))
        let items = s.items(level)
        return NavigationLink(value: s) {
            VStack(alignment: .leading, spacing: 10) {
                Text((s.kind == "hybrid" ? "SOCCER + FITNESS" : "TECHNIQUE")).font(F.round(10, .heavy)).kerning(1).foregroundStyle(C.brandHi)
                Text(s.title).font(F.round(17, .bold)).foregroundStyle(C.creme).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    Label("\(items.count) drills", systemImage: "square.grid.2x2").font(F.round(12, .semibold))
                    Label("\(s.minutes(level)) min", systemImage: "clock").font(F.round(12, .semibold))
                }
                .foregroundStyle(C.muted)
                Text("Start session").font(F.round(14, .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 38)
                    .background(Capsule().fill(C.brand))
            }
            .padding(12)
            .frame(width: 210, height: 172, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(C.char800)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(C.line, lineWidth: 1)))
        }
        .buttonStyle(.plain)
    }
}

/// A filter chip (shared by Drills and Fitness).
func labChip(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
    Button(action: { action(); Haptics.play(.stud) }) {
        Text(label).font(F.round(14, .bold))
            .foregroundStyle(on ? Color.white : C.creme2)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Capsule().fill(on ? C.brand : C.char800))
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(on ? .isSelected : [])
}

// MARK: - FITNESS

struct TrainingFitnessPart<RunCard: View, Free: View>: View {
    @ViewBuilder var runCard: RunCard
    @ViewBuilder var free: Free
    @State private var kind = "All"

    private var lib: Library { Library.shared }
    private let kinds = ["Runs", "Fitness", "Core", "Stretching"]
    private var drills: [Drill] {
        lib.drills.filter { kind == "All" ? kinds.contains($0.skill) : $0.skill == kind }.sorted { ($0.skill, $0.level) < ($1.skill, $1.level) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            runCard
            if !lib.workouts.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    LabKicker("WORKOUTS")
                    VStack(spacing: 10) {
                        ForEach(lib.workouts) { s in
                            NavigationLink(value: s) {
                                HStack(spacing: 12) {
                                    Image(systemName: "bolt.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                                        .frame(width: 44, height: 44).background(Circle().fill(labSkillColor("Runs")))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(s.title).font(F.round(17, .bold)).foregroundStyle(C.creme)
                                        Text("No ball needed").font(F.round(13, .semibold)).foregroundStyle(C.muted)
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
            VStack(alignment: .leading, spacing: 12) {
                LabKicker("FITNESS DRILLS")
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(["All"] + kinds.filter { k in lib.drills.contains { $0.skill == k } }, id: \.self) { k in
                            labChip(k, on: k == kind) { kind = k }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                VStack(spacing: 10) {
                    ForEach(drills) { d in LabDrillRow(drill: d) }
                }
            }
            free
        }
    }
}

// MARK: - voice drills

/// The phone calls out a move (Coach calls) or a cone colour (Colour cones) every few seconds; the player reacts.
struct VoiceDrill: View {
    enum Mode: String, Identifiable {
        case moves, cones
        var id: String { rawValue }
        var title: String { self == .moves ? "Live Callouts" : "Cone Reaction" }
        /// The library drill this ticks off when finished (content/make_library.py).
        var drillID: String { self == .moves ? "coach-calls" : "colour-cones" }
        var steps: [String] {
            self == .moves
                ? ["Dribble in a small space, about 10 big steps square.",
                   "When you hear a move, do it straight away.",
                   "Keep the ball close and go again until the next call.",
                   "Prop your phone up nearby so you can hear it."]
                : ["Put 4 cones (red, blue, yellow, green) in a square, about 6 big steps across. Any 4 objects work: say which is which.",
                   "Stand in the middle with the ball.",
                   "When a colour is called, dribble round that cone and back to the middle.",
                   "Be back before the next call."]
        }
    }

    let mode: Mode
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    @State private var lab = Lab.shared
    @State private var minutes = 4
    @State private var pace = 1
    @State private var running = false
    @State private var finished = false
    @State private var call = ""
    @State private var left = 0
    @State private var calls = 0
    @State private var loop: Task<Void, Never>?
    @State private var voice = AVSpeechSynthesizer()

    private static let moves = ["Cruyff turn", "Step-over", "Drag back", "Scissors", "Inside cut", "Outside cut",
                                "Sole roll", "Stop and go", "Fake shot", "Burst", "La croqueta", "Hop turn"]
    private static let colours: [(String, Color)] = [("Red", Color(hex: 0xE5484D)), ("Blue", Color(hex: 0x1E78FF)),
                                                     ("Yellow", Color(hex: 0xF5C542)), ("Green", Color(hex: 0x2BB673))]
    private let paces = [("Easy", 6.0), ("Medium", 4.0), ("Hard", 3.0)]

    var body: some View {
        ZStack {
            C.char900.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Disp(mode.title.uppercased(), size: 30)
                        Spacer()
                        Button { stop(); dismiss() } label: {
                            Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).foregroundStyle(C.creme)
                                .frame(width: 40, height: 40).background(Circle().fill(C.char800))
                        }
                        .accessibilityLabel("Close")
                    }
                    .padding(.top, 12)

                    stage
                    if !running && !finished { setup }
                    controls
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .onDisappear { stop() }
    }

    // the big picture: what's being called

    private var stage: some View {
        VStack(spacing: 14) {
            if mode == .cones {
                ZStack {
                    ForEach(Array(Self.colours.enumerated()), id: \.offset) { i, c in
                        let lit = running && call == c.0
                        Image(systemName: "triangle.fill")
                            .font(.system(size: lit ? 46 : 34, weight: .bold))
                            .foregroundStyle(c.1.opacity(running && !lit ? 0.35 : 1))
                            .shadow(color: lit ? c.1 : .clear, radius: 16)
                            .offset(x: [0, 90, 0, -90][i], y: [-80, 0, 80, 0][i])
                            .animation(.snappy, value: call)
                    }
                    Image(systemName: "figure.soccer").font(.system(size: 30, weight: .bold)).foregroundStyle(C.creme)
                        .frame(width: 60, height: 60).background(Circle().fill(C.char800))
                }
                .frame(height: 220)
            }
            Text(running ? (call.isEmpty ? "Get ready…" : call.uppercased()) : finished ? "DONE!" : "READY?")
                .font(.system(size: mode == .moves ? 40 : 34, weight: .heavy))
                .foregroundStyle(mode == .cones ? (Self.colours.first { $0.0 == call }?.1 ?? C.creme) : C.creme)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6).lineLimit(2)
                .contentTransition(.opacity)
                .animation(.snappy, value: call)
            if running {
                Text(String(format: "%d:%02d left · %d calls", left / 60, left % 60, calls))
                    .font(F.round(15, .bold)).foregroundStyle(C.muted).monospacedDigit()
            } else if finished {
                Text("\(calls) calls in \(minutes) minutes. It's ticked off for today.")
                    .font(F.round(15, .semibold)).foregroundStyle(C.creme2).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: mode == .moves ? 180 : 300)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(C.char800))
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                LabKicker("HOW LONG")
                HStack(spacing: 8) {
                    ForEach([2, 4, 6], id: \.self) { m in
                        labChip("\(m) min", on: minutes == m) { minutes = m }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                LabKicker("HOW FAST")
                HStack(spacing: 8) {
                    ForEach(paces.indices, id: \.self) { i in
                        labChip("\(paces[i].0) · \(Int(paces[i].1)) s", on: pace == i) { pace = i }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                LabKicker("HOW IT WORKS")
                ForEach(Array(mode.steps.enumerated()), id: \.offset) { i, s in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(i + 1)").font(F.round(13, .heavy)).foregroundStyle(C.char900)
                            .frame(width: 22, height: 22).background(Circle().fill(C.brandHi))
                        Text(s).font(F.round(14, .semibold)).foregroundStyle(C.creme2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var controls: some View {
        Group {
            if running {
                Button("STOP") { stop() }.buttonStyle(.gameLarge(.charcoal))
            } else {
                Button(finished ? "GO AGAIN" : "START") { start() }.buttonStyle(.gameLarge(.brand, feel: .kick))
            }
        }
    }

    // the loop

    private func start() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        UIApplication.shared.isIdleTimerDisabled = true
        running = true
        finished = false
        calls = 0
        call = ""
        left = minutes * 60
        let gap = paces[pace].1
        let total = Double(minutes * 60)
        loop = Task { @MainActor in
            say("Get ready")
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            let began = Date()
            var next = 0.0
            var last = ""
            while !Task.isCancelled {
                let t = Date().timeIntervalSince(began)
                left = max(0, Int((total - t).rounded(.up)))
                if t >= total { break }
                if t >= next {
                    let pool = mode == .moves ? Self.moves : Self.colours.map(\.0)
                    var c = pool.randomElement() ?? ""
                    while c == last, pool.count > 1 { c = pool.randomElement() ?? "" }
                    last = c
                    call = c
                    calls += 1
                    say(c)
                    Haptics.play(.kick)
                    next += gap
                }
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
            if !Task.isCancelled { finish() }
        }
    }

    private func finish() {
        running = false
        finished = true
        call = ""
        say("Time. Well done.")
        Haptics.play(.goal)
        UIApplication.shared.isIdleTimerDisabled = false
        if Library.shared.has(mode.drillID) {
            lab.complete(Library.shared.drill(mode.drillID), store: store)
        } else {
            store.logDrill(PlanItem(mode.drillID), seconds: Double(minutes * 60))
        }
    }

    private func stop() {
        loop?.cancel()
        loop = nil
        if running { running = false; call = "" }
        voice.stopSpeaking(at: .immediate)
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func say(_ text: String) {
        let u = AVSpeechUtterance(string: text)
        u.rate = 0.52
        u.volume = 1
        u.voice = AVSpeechSynthesisVoice(language: "en-GB") ?? AVSpeechSynthesisVoice(language: "en-US")
        voice.stopSpeaking(at: .immediate)
        voice.speak(u)
    }
}
