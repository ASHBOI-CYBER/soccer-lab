// The onboarding flow, native: one screen per step, answers save as you go (AppStore.answers).
// v3 (2026-11-08, user: "make it short but also optimize the app for the user's retention"): only name, position,
// gender, strong foot ? WHAT DO YOU WANT MOST (several picks, social first) ? where did you find us ? notifications ?
// Apple account ? an optional profile-photo popup ? the app, on the tab that matches what they want most.
// v3.1 (2026-11-08): optional last name, no progress bar, quick fade on back, "want most" = become a better player etc.,
// NO PAYWALL ? the app is free for now (`Purchases.freeForNow`).
// The old long flow (skills, self-rating, training setup, days, goal, drills, pledge penalty, building, reveal, first
// week, rate us) is gone ? notes/19 top. The MASCOT still asks every question in a speech bubble (notes/30).
import PhotosUI
import PostHog
import StoreKit
import SwiftUI
import UserNotifications

enum OBStep: String, CaseIterable {
    case welcome, name, position, gender, foot, body, level, routine, goal, fuel, wants, source, team, account

    /// The steps in order; "Join a team" only while teams are on (Nav.teamsOn).
    static var allCases: [OBStep] {
        [.welcome, .name, .position, .gender, .foot, .body, .level, .routine, .goal, .fuel, .wants, .source, .team, .account]
            .filter { $0 != .team || TEAMS_ON }
    }

    /// Name shown in Settings ? Test onboarding.
    var label: String {
        switch self {
        case .foot: return "Strong foot"
        case .body: return "Age, height, weight"
        case .level: return "Experience"
        case .routine: return "Training routine"
        case .goal: return "Main goal"
        case .fuel: return "Food goal"
        case .wants: return "What you want most"
        case .source: return "Where did you find us"
        case .team: return "Join a team"
        default: return rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }

}

struct OnboardingFlow: View {
    @Environment(AppStore.self) private var store
    @State private var step: OBStep
    @State private var forward = true
    /// TEST MODE (Settings ? Test onboarding): set = the flow runs over the app, a BACK TO APP pill sits on top,
    /// and finishing just closes it (never touches `onboarded`).
    private let exitTest: (() -> Void)?

    init(start: OBStep? = nil, exitTest: (() -> Void)? = nil) {
        self.exitTest = exitTest
        // Paid but quit before making the account ? straight back to the account step, not the whole flow again.
        _step = State(initialValue: start
            ?? OBStep(rawValue: DebugRoute.parts.first == "ob" ? DebugRoute.parts[safe: 1] ?? "" : "")
            ?? (!Purchases.freeForNow && Purchases.shared.hasAccess ? .account : .welcome))
    }

    var body: some View {
        ZStack {
            AppBackground()
            if step == .welcome { MownPitch() }
            screen
                .id(step)
                .duoColumn(fill: false)   // iPhone Duo inner display: pages in a centered column, the background stays full width
                // forward = slide in from the right; BACK = a quick crossfade into the previous page (user, 2026-11-08)
                .transition(forward
                    ? .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                  removal: .move(edge: .leading).combined(with: .opacity))
                    : .opacity)
        }
        .animation(forward ? .spring(response: 0.42, dampingFraction: 0.88) : .easeInOut(duration: 0.3), value: step)
        .overlay(alignment: .bottomLeading) {
            if let exitTest {
                Button { Haptics.play(.unlatch); exitTest() } label: {
                    Label("BACK TO APP", systemImage: "xmark")
                        .font(F.round(14, .bold))
                        .foregroundStyle(C.char950)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Capsule().fill(C.gold))
                }
                .buttonStyle(.plain)
                .padding(.leading, 16)
                .padding(.bottom, 110)   // clear of the CONTINUE dock
            }
        }
    }

    private func go(_ s: OBStep) {
        if exitTest == nil { OBTrack.left(step, store.answers) }
        forward = true; step = s
    }
    private func next() {
        let all = OBStep.allCases
        go(all[min(all.count - 1, all.firstIndex(of: step)! + 1)])
    }
    private func back() {
        let all = OBStep.allCases
        forward = false
        step = all[max(0, all.firstIndex(of: step)! - 1)]
    }
    private func finish() {
        if let exitTest { exitTest() } else {
            PostHogSDK.shared.capture("onboarding_completed", properties: OBTrack.all(store.answers),
                                      userProperties: OBTrack.all(store.answers))
            // retention: open on what they said they want most. Anything social (or nothing picked) ? the Team tab,
            // where MAKE A TEAM / JOIN WITH A CODE waits; only the training picks ? the Sessions tab (tap an area, clock starts).
            if !Wants.social(store.answers.wants ?? []), !(store.answers.wants ?? []).isEmpty, Team.shared.pendingCode == nil {
                Nav.shared.tab = .home
            }
            Lab.shared.setBody(from: store.answers)
            store.onboarded = true
        }
    }

    @ViewBuilder private var screen: some View {
        let ctx = OBContext(step: step, next: next, back: back, go: go, finish: finish, testing: exitTest != nil)
        let n = store.answers.firstName
        switch step {
        case .welcome: Welcome(ctx: ctx)
        case .name: NameStep(ctx: ctx)
        case .position: PositionStep(ctx: ctx)
        case .gender: PickStep(ctx: ctx, title: "Tell us about you, \(n)", options: ["Male", "Female", "Prefer not to say"], key: \.gender)
        case .foot: PickStep(ctx: ctx, title: "Which is your strong foot?", options: ["Right", "Left", "Both"], key: \.foot)
        case .body: BodyStep(ctx: ctx)
        case .level: PickStep(ctx: ctx, title: "What level do you play at?", sub: "So your drills start at the right level.",
                              options: ["Just for fun", "School team", "Club", "Academy", "College", "Semi-pro +"], key: \.level)
        case .routine: PickStep(ctx: ctx, title: "How often do you train?", sub: "Team practice and training on your own both count.",
                                options: ["1-2 days", "3-4 days", "5-6 days", "Every day"], key: \.trainDays)
        case .goal: PickStep(ctx: ctx, title: "What's your main goal, \(n)?",
                             options: ["Make my team", "Become a starter", "Get scouted", "Improve my skills", "Get fitter and faster", "Play for fun"], key: \.goal)
        case .fuel: PickStep(ctx: ctx, title: "What do you want from your food?", sub: "We'll set your calories and protein around it.",
                             options: ["Build muscle", "Stay lean and fast", "More energy for games", "Just eat better"], key: \.fuelGoal)
        case .wants: WantsStep(ctx: ctx)
        case .source: PickStep(ctx: ctx, title: "Where did you find us?", options: ["TikTok", "Instagram", "YouTube", "A friend", "App Store", "Other"], key: \.source,
                               icon: { AnyView(SourceLogo(source: $0)) })
        case .team: JoinTeamStep(ctx: ctx)
        case .account: AccountStep(ctx: ctx)
        }
    }
}

struct OBContext {
    let step: OBStep
    let next: () -> Void
    let back: () -> Void
    let go: (OBStep) -> Void
    let finish: () -> Void
    /// Settings ? Test onboarding: pages that skip themselves for a real player (the account page when you're already
    /// signed in) stay open so they can be looked at.
    var testing = false
}

// MARK: - shell

struct OBShell<Content: View>: View {
    let ctx: OBContext
    let title: String
    var sub: Text? = nil
    var cta: String? = "Continue"
    var canNext = true
    var onNext: (() -> Void)? = nil
    var scrolls = true
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {   // back, and how far through the questions you are (2026-11-13)
                SlowBack(action: ctx.back)
                ProgressBar(value: progress)
                    .padding(.trailing, 8)
                    .accessibilityLabel("Step \((OBStep.allCases.firstIndex(of: ctx.step) ?? 0)) of \(OBStep.allCases.count - 1)")
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            Group {
                if scrolls {
                    ScrollView { inner }.scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
                } else {
                    inner
                }
            }
        }
        .dock {
            if let cta {
                Button(cta) { (onNext ?? ctx.next)() }
                    .buttonStyle(.gameLarge)
                    .disabled(!canNext)
            }
        }
    }

    private var progress: Double {
        let all = OBStep.allCases
        return Double(all.firstIndex(of: ctx.step) ?? 0) / Double(max(1, all.count - 1))
    }

    private var inner: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 26, weight: .bold)).foregroundStyle(C.creme)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)
                .accessibilityAddTraits(.isHeader)
            if let sub {
                sub.font(F.round(16, .medium)).foregroundStyle(C.muted).padding(.top, 8)
            }
            content.padding(.top, 22)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One-answer question.
struct PickStep: View {
    let ctx: OBContext
    let title: String
    var sub: String? = nil
    let options: [String]
    let key: WritableKeyPath<Answers, String?>
    var icon: ((String) -> AnyView?)? = nil
    @Environment(AppStore.self) private var store

    var body: some View {
        OBShell(ctx: ctx, title: title, sub: sub.map { Text($0) }, canNext: store.answers[keyPath: key] != nil) {
            Options(options: options, value: store.answers[keyPath: key], icon: icon) { store.answers[keyPath: key] = $0 }
        }
    }
}

// MARK: - act 1

/// The welcome page's mown pitch. Also drawn edge to edge behind the onboarding column on the iPhone Duo inner display.
struct MownPitch: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<14, id: \.self) { i in
                (i % 2 == 0 ? Color(hex: 0x1668E8) : Color(hex: 0x125CD4)).frame(maxHeight: .infinity)
            }
        }
        .overlay(LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .center, endPoint: .bottom))
        .ignoresSafeArea()
    }
}

struct Welcome: View {
    let ctx: OBContext
    @Environment(AppStore.self) private var store
    @State private var team = Team.shared
    @State private var entering = false
    @State private var signingIn = false

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                Spacer(minLength: 20)
                ZStack {
                    Circle().fill(C.brand.opacity(0.28)).frame(width: 190, height: 190).blur(radius: 55)
                    Image("AppBall").resizable().scaledToFit().frame(width: 150, height: 150)
                        .shadow(color: C.brand.opacity(0.5), radius: 24)
                        .accessibilityHidden(true)
                }
                HStack(spacing: 0) {
                    Text("SOCCER ").foregroundStyle(C.creme)
                    Text("LAB").foregroundStyle(C.brand)
                }
                .font(.system(size: 34, weight: .heavy)).kerning(2)
                .padding(.top, 18)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Soccer Lab")
                Text("Your training, built around how you play.")
                    .font(F.round(17, .medium)).foregroundStyle(C.creme2)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                VStack(alignment: .leading, spacing: 14) {
                    welcomeRow("figure.soccer", "A session every day, made for your position")
                    welcomeRow("video.fill", "Review your clips and get the drills that fix them")
                    welcomeRow("fork.knife", "Nutrition targets and a simple food log")
                }
                .padding(.top, 30)
                .padding(.horizontal, 28)
                Spacer(minLength: 20)
            }
        }
        .dock(fade: .clear) {
            VStack(spacing: 12) {
                Button("Get started") { ctx.go(.name) }.buttonStyle(.gameLarge)
                // an invite link's code (or one typed here) waits for the end of onboarding: after the Apple account
                // the app opens the Team page with it ready to use (ShareLinks, notes/19 "SHARE LINKS")
                Button { entering = true } label: {
                    Label(team.pendingCode.map { "Code \($0)" } ?? "I have a code",
                          systemImage: team.pendingCode == nil ? "ticket.fill" : "checkmark.circle.fill")
                }
                .buttonStyle(.game(team.pendingCode == nil ? .charcoal : .brand))
                Button("I already have an account") { signingIn = true }
                    .font(F.round(15, .semibold)).foregroundStyle(C.muted)
                    .frame(minHeight: 44)
            }
        }
        .sheet(isPresented: $entering) { InviteCodeSheet { ctx.go(.name) } }
        .sheet(isPresented: $signingIn) {
            SignBackInSheet(back: { signingIn = false; ctx.finish() }, none: { signingIn = false; ctx.go(.name) })
        }
    }
}

extension Welcome {
    /// One line of what the app does, on the welcome screen.
    func welcomeRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 16, weight: .bold)).foregroundStyle(C.brandHi)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(C.brand.opacity(0.18)))
            Text(text).font(F.round(15, .semibold)).foregroundStyle(C.creme)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

/// Welcome ? I HAVE AN ACCOUNT: Sign in with Apple, and the saved player comes back from the cloud backup
/// (Data/Backup.swift) ? sessions, set log, streak days, stats, photo. No saved player ? build one.
struct SignBackInSheet: View {
    let back: () -> Void
    let none: () -> Void
    @Environment(AppStore.self) private var store
    @State private var team = Team.shared
    @State private var backup = Backup.shared

    var body: some View {
        VStack(spacing: 18) {
            Disp("WELCOME BACK", size: 34).padding(.top, 26)
            if backup.found == false {
                Text("No saved player on that account yet. Set one up now.")
                    .font(F.round(16, .semibold)).foregroundStyle(C.muted).multilineTextAlignment(.center)
                Button("BUILD MY PLAYER") { none() }.buttonStyle(.gameLarge)
            } else if team.signedIn && backup.found == nil {
                ProgressView().tint(C.brand).padding(.vertical, 18)
                Text("Bringing your player back…").font(F.round(15, .semibold)).foregroundStyle(C.muted)
            } else {
                Text("Sign in with the same Apple ID. Your sessions, streak and stats come right back.")
                    .font(F.round(16, .semibold)).foregroundStyle(C.muted).multilineTextAlignment(.center)
                AppleSignIn()
                if let e = team.error { Text(e).font(F.round(14, .semibold)).foregroundStyle(C.gold) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .presentationDetents([.height(330)])
        .presentationBackground(C.char900)
        .onChange(of: backup.found) { _, f in if f == true { back() } }
        .task {
            // already signed in on this phone (the Keychain survived the delete) ? look now
            if team.signedIn, backup.found == nil, await backup.pull(store) { back() }
        }
    }
}

/// First screen ? "I HAVE AN INVITE CODE": paste (or type) the code from a friend's link, then build your player.
/// Joining happens at the end, on the Team tab, after Sign in with Apple.
struct InviteCodeSheet: View {
    let done: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var team = Team.shared
    @State private var code = ""

    var body: some View {
        VStack(spacing: 16) {
            Disp("HAVE A CODE?", size: 32).padding(.top, 26)
            Text(TEAMS_ON ? "Got a team code from a friend? You'll join their team as soon as you're in."
                 : "Got a 6-digit code from a creator? Enter it and they get credit when you subscribe. Your price stays the same.")
                .font(F.round(15, .semibold)).foregroundStyle(C.creme2).multilineTextAlignment(.center)
            CodeEntry(code: $code)
                .onChange(of: code) { _, v in let c = Team.clean(v); if c != v { code = c } }
            PasteButton(payloadType: String.self) { got in
                let digits = (got.first ?? "").filter(\.isNumber)
                if digits.count >= 6 { code = String(digits.prefix(6)); Haptics.play(.latch) }
            }
            .buttonBorderShape(.capsule)
            .tint(C.brand)
            Spacer()
            Button("CONTINUE") {
                team.pendingCode = code
                Haptics.play(.goal)
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { done() }
            }
            .buttonStyle(.gameLarge)
            .disabled(code.count != 6)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
        .presentationDetents([.large])
        .presentationBackground(C.char900)
        .onAppear { if let c = team.pendingCode { code = c } }
    }
}

struct NameStep: View {
    let ctx: OBContext
    @Environment(AppStore.self) private var store
    @FocusState private var focus: Int?

    var body: some View {
        @Bindable var store = store
        OBShell(ctx: ctx, title: "What's your name?", sub: Text("So your plan feels like yours."),
                canNext: !store.answers.first.trimmingCharacters(in: .whitespaces).isEmpty) {
            VStack(spacing: 14) {
                // Last name back (user, 2026-11-08) but OPTIONAL: only the first name unlocks CONTINUE ? on launch night
                // (2026-11-05) people stalled when a last name was required (notes/38).
                NameField(placeholder: "First name", text: $store.answers.first, max: 14).focused($focus, equals: 0)
                    .textContentType(.givenName).submitLabel(.next)
                    .onSubmit { focus = 1 }
                NameField(placeholder: "Last name (optional)", text: $store.answers.last, max: 18).focused($focus, equals: 1)
                    .textContentType(.familyName).submitLabel(.done)
            }
        }
    }
}

private struct NameField: View {
    let placeholder: String
    @Binding var text: String
    let max: Int
    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(C.char600))
            .font(F.display(24))
            .foregroundStyle(C.creme)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.words)
            .padding(.horizontal, 20)
            .frame(height: 60)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(C.char950)
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(C.line, lineWidth: 1)))
            .onChange(of: text) { _, v in
                if v.count > max { text = String(v.prefix(max)) }
                Haptics.play(.stud)
            }
    }
}

private let SPOTS: [(String, CGFloat, CGFloat)] = [
    ("ST", 50, 13), ("LW", 17, 21), ("RW", 83, 21), ("CAM", 50, 31), ("LM", 13, 43), ("CM", 50, 46), ("RM", 87, 43),
    ("CDM", 50, 60), ("LWB", 12, 62), ("RWB", 88, 62), ("LB", 17, 76), ("CB", 50, 79), ("RB", 83, 76), ("GK", 50, 93),
]

struct PositionStep: View {
    let ctx: OBContext
    @Environment(AppStore.self) private var store

    var body: some View {
        OBShell(ctx: ctx, title: "Where do you play, \(store.answers.firstName)?") {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    Text(store.answers.position).font(.system(size: 22, weight: .bold)).foregroundStyle(C.brandHi)
                    Text(store.answers.positionName).font(F.round(16, .medium)).foregroundStyle(C.creme2)
                    Spacer()
                }
                GeometryReader { g in
                    let w = g.size.width, h = g.size.height
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(LinearGradient(colors: [Color(hex: 0x0E1420), Color(hex: 0x070A10)], startPoint: .top, endPoint: .bottom))
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(C.line, lineWidth: 1))
                        PitchLines().stroke(C.brand.opacity(0.35), lineWidth: 1)
                        ForEach(SPOTS, id: \.0) { id, x, y in
                            let on = store.answers.position == id
                            Button { store.answers.position = id } label: {
                                Text(id).font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(on ? Color.white : C.creme2)
                                    .frame(width: 46, height: 46)
                                    .background(Circle().fill(on ? C.brand : C.char700))
                                    .overlay(Circle().stroke(on ? C.brandHi : C.line, lineWidth: 1))
                                    .shadow(color: on ? C.brand.opacity(0.7) : .clear, radius: 10)
                            }
                            .buttonStyle(.press(.pop))
                            .position(x: w * x / 100, y: h * y / 100)
                        }
                    }
                }
                .aspectRatio(100 / 140, contentMode: .fit)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: store.answers.position)
            }
        }
    }
}

private struct PitchLines: Shape {
    func path(in r: CGRect) -> Path {
        let sx = r.width / 100, sy = r.height / 140
        func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x * sx, y: y * sy, width: w * sx, height: h * sy) }
        var p = Path()
        p.addRoundedRect(in: R(4, 4, 92, 132), cornerSize: CGSize(width: 2, height: 2))
        p.move(to: CGPoint(x: 4 * sx, y: 70 * sy)); p.addLine(to: CGPoint(x: 96 * sx, y: 70 * sy))
        p.addEllipse(in: R(39, 59, 22, 22))
        p.addRect(R(24, 4, 52, 19)); p.addRect(R(37, 4, 26, 7))
        p.addRect(R(24, 117, 52, 19)); p.addRect(R(37, 129, 26, 7))
        return p
    }
}

// MARK: - what you want most (social first)

enum Wants {
    static let all: [(String, String)] = [
        ("Become a better player", "arrow.up.right"),
        ("Get fitter and faster", "bolt.fill"),
        ("Build my confidence", "flame.fill"),
        ("Make the team", "star.fill"),
        ("Track my training", "chart.bar.fill"),
    ]
    /// The picks that live on the Team tab. (v3.1, 2026-11-08: "keep a streak going" + "beat my friends on the
    /// leaderboard" cut by the user; "become a better player" + "make the team" added.)
    static let socialPicks: Set<String> = ["Join my team", "Train with my friends"]
    static func social(_ w: [String]) -> Bool { w.contains { socialPicks.contains($0) } }
}

struct WantsStep: View {
    let ctx: OBContext
    @Environment(AppStore.self) private var store

    var body: some View {
        let picked = store.answers.wants ?? []
        OBShell(ctx: ctx, title: "What do you want most from Soccer Lab, \(store.answers.firstName)?", sub: Text("Pick all that fit."),
                canNext: !picked.isEmpty) {
            VStack(spacing: 12) {
                ForEach(Wants.all, id: \.0) { w, sym in
                    let on = picked.contains(w)
                    Button {
                        Haptics.play(on ? .unlatch : .pop)
                        store.answers.wants = on ? picked.filter { $0 != w } : Wants.all.map(\.0).filter { $0 == w || picked.contains($0) }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: sym).font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? C.brand : C.char700))
                            Text(w).font(F.round(18, .semibold)).foregroundStyle(C.creme)
                                .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 6)
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? C.brand : C.char950).frame(width: 28, height: 28)
                                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(on ? C.brandInk : C.char600, lineWidth: 2.5))
                                if on { Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white) }
                            }
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 66)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(on ? C.brand.opacity(0.16) : C.char800)
                                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(on ? C.brand : C.charInk, lineWidth: 2.5))
                                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(on ? C.brandLip : C.charInk).offset(y: 4))
                        )
                    }
                    .buttonStyle(.press(.pop))
                }
            }
        }
    }
}

// MARK: - join a team (replaced the notifications page, 2026-11-08)

/// "Let's get you on a team": three ways, any or all ? teams near me (location), friends in contacts (OUR explainer
/// first, then Apple's one prompt), a team code. Each turns green once done. None is required.
/// (Streak reminders now live only in Settings ? Streak reminders.)
struct JoinTeamStep: View {
    let ctx: OBContext
    @Environment(AppStore.self) private var store
    @State private var where_ = Locator.shared
    @State private var book = FriendsBook.shared
    @State private var team = Team.shared
    @State private var explaining = false
    @State private var coding = false

    var body: some View {
        let any = where_.allowed || book.allowed || team.pendingCode != nil
        OBShell(ctx: ctx, title: "Join a team, \(store.answers.firstName)",
                sub: Text("Pick any of these. You can always do them later."),
                cta: any ? "CONTINUE" : "SKIP FOR NOW") {
            VStack(spacing: 12) {
                option("location.fill", "Find teams near me", "See local teams and ask to join",
                       done: where_.allowed, off: where_.denied ? "Location is off. You can turn it on in Settings." : nil) {
                    where_.ask()
                }
                option("person.2.fill", "Find friends in contacts", "Invite your friends to train with you",
                       done: book.allowed, off: book.denied ? "Contacts are off. You can turn them on later." : nil) {
                    if book.undecided { explaining = true }
                }
                option("number", "I have a team code",
                       team.pendingCode.map { "Code \($0). You'll join once you're in." } ?? "From a friend or your coach",
                       done: team.pendingCode != nil, off: nil) {
                    coding = true
                }
            }
        }
        .sheet(isPresented: $explaining) { ContactsExplainer() }
        .sheet(isPresented: $coding) { InviteCodeSheet {} }
        .onAppear { book.recheck() }
    }

    private func option(_ icon: String, _ title: String, _ sub: String, done: Bool, off: String?, tap: @escaping () -> Void) -> some View {
        Button { Haptics.play(.pop); tap() } label: {
            HStack(spacing: 14) {
                GlowIcon(symbol: icon, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(F.round(18, .bold)).foregroundStyle(C.creme)
                    Text(off ?? sub).font(F.round(14, .semibold)).foregroundStyle(off == nil ? C.muted : C.gold)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                ZStack {
                    Circle().fill(done ? C.brand : C.char700).frame(width: 30, height: 30)
                    Image(systemName: done ? "checkmark" : "chevron.right").font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(done ? .white : C.muted)
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(done ? AnyShapeStyle(C.brand.opacity(0.14))
                           : AnyShapeStyle(LinearGradient(colors: [C.char800, C.char850], startPoint: .top, endPoint: .bottom))))
            .contentShape(Rectangle())
        }
        .buttonStyle(.press(.pop))
        .disabled(done && icon != "number")
        .animation(.snappy, value: done)
    }
}

struct PaywallStep: View {
    let ctx: OBContext
    var body: some View { PaywallView(done: ctx.next) }   // paid ? make the account (AccountStep), then the app
}

/// Shown instead of the tabs when onboarding is done but there's no access (never paid, sub or team trial ran out).
/// Buying flips Purchases.hasAccess and the app swaps to the tabs on its own.
struct PaywallGate: View {
    var body: some View {
        ZStack { AppBackground(); PaywallView(done: {}) }
    }
}

// The paywall itself lives in Paywall.swift.

/// The last step: CREATE YOUR ACCOUNT ? Sign in with Apple, the same account the Team tab uses.
/// v5 (2026-11-08, user: "much much more simple like 'create your account' with a soccer ball that animates as you
/// create your account"): one ball, one title, one button. The ball floats while waiting, juggles fast while Apple
/// signs you in, then flies off as "YOU'RE IN!" and the app opens. The photo popup lives in the app (`PhotoNudge`).
struct AccountStep: View {
    let ctx: OBContext
    @Environment(AppStore.self) private var store
    @State private var team = Team.shared
    @State private var phase: AccountBall.Phase = .idle
    @State private var done = false

    /// Into the app ? once (the button's callback and the signed-in change can both fire).
    private func signedIn() {
        guard !done else { return }
        done = true
        Haptics.play(.goal)
        withAnimation(.snappy) { phase = .scored }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { ctx.finish() }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack { SlowBack(action: ctx.back); Spacer() }
                .padding(.horizontal, 16).padding(.top, 4)
            Spacer()
            AccountBall(phase: phase).frame(height: 300)
            Disp(phase == .scored ? "YOU'RE IN!" : "CREATE YOUR ACCOUNT", size: 36)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
                .padding(.top, 8)
            Text(phase == .working ? "Creating your account…" : "Save your training and your progress.")
                .font(F.round(16, .semibold)).foregroundStyle(C.muted)
                .contentTransition(.opacity)
                .padding(.top, 8)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 20)
        .dock {
            VStack(spacing: 10) {
                AppleSignIn(onDone: signedIn,
                            onStart: { withAnimation(.snappy) { phase = .working } },
                            onCancel: { withAnimation(.snappy) { phase = .idle } })
                    .opacity(phase == .scored ? 0 : 1)
                if let e = team.error {
                    Text(e).font(F.round(14, .semibold)).foregroundStyle(C.gold).multilineTextAlignment(.center)
                } else {
                    Label("One tap · No password", systemImage: "lock.fill")
                        .font(F.round(13, .semibold)).foregroundStyle(C.muted)
                }
                #if DEBUG
                // Test builds only (never in the App Store build): a simulator has no Apple ID to sign in with,
                // so this goes into the app without an account. Team features stay signed out.
                Button("Skip sign-in (test build)") { signedIn() }
                    .font(F.round(13, .semibold)).foregroundStyle(C.muted)
                #endif
            }
        }
        .onAppear {
            // already signed in ? straight into the app. NOT while testing: you're always signed in then
            // (user, 2026-10-30: "it crashes every time I open [the account page]").
            if team.signedIn && !ctx.testing { signedIn() }
        }
        .onChange(of: team.signedIn) { _, now in if now && !ctx.testing { signedIn() } }
    }
}

/// The account page's ball: floats and turns slowly (idle), juggles high and spins fast (working), then shoots up and
/// away (scored). A soft shadow on the grass shrinks as it rises; a green glow sits behind it. Spin speed changes
/// without jumping (the angle carries over between phases).
struct AccountBall: View {
    enum Phase { case idle, working, scored }
    let phase: Phase
    @State private var since = Date()
    @State private var angle0 = 0.0

    private func spin(_ p: Phase) -> Double { p == .idle ? 50 : p == .working ? 520 : 900 }

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSince(since)
            let angle = angle0 + t * spin(phase)
            let lift: Double = {
                switch phase {
                case .idle: return 10 + abs(sin(t * 2.0)) * 26
                case .working: return 10 + abs(sin(t * 6.0)) * 70
                case .scored: return 10 + pow(min(1, t / 0.8), 2) * 520
                }
            }()
            let scale = phase == .scored ? max(0.3, 1 - t / 0.8 * 0.6) : 1
            let s = 150.0
            ZStack(alignment: .bottom) {
                RadialGradient(colors: [C.brand.opacity(phase == .working ? 0.4 : 0.25), .clear], center: .center, startRadius: 10, endRadius: 170)
                    .frame(width: 340, height: 340)
                    .offset(y: -90)
                Ellipse().fill(.black.opacity(0.35 * max(0.15, 1 - lift / 200)))
                    .frame(width: s * max(0.3, 1 - lift / 260), height: 16)
                    .blur(radius: 4)
                IconBall(size: s)
                    .rotationEffect(.degrees(angle))
                    .scaleEffect(scale)
                    .offset(y: -lift - 6)
                    .opacity(phase == .scored ? max(0, 1 - t / 0.8) : 1)
            }
            .frame(maxWidth: .infinity)
        }
        .onChange(of: phase) { old, _ in
            angle0 += Date().timeIntervalSince(since) * spin(old)
            since = Date()
        }
        .accessibilityHidden(true)
    }
}

/// A soft green-lit circle with an SF symbol (the Sessions tab / Settings icon language).
struct GlowIcon: View {
    let symbol: String
    var size: CGFloat = 46
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.4, weight: .bold))
            .foregroundStyle(C.brandHi)
            .frame(width: size, height: size)
            .background(Circle().fill(RadialGradient(colors: [C.brand.opacity(0.38), C.brand.opacity(0.10)],
                                                     center: .center, startRadius: 0, endRadius: size / 2)))
    }
}

/// The ADD A PHOTO popup (Photos picker ? `store.setAvatar`) or Skip. Shown from MainTabs (`PhotoNudge`): the first
/// time they get into the app, then every 4th open while there's still no photo.
struct PhotoAsk: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var pick: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 16) {
            Avatar(size: 120).padding(.top, 28)
            Disp("ADD A PHOTO?", size: 32)
            Text("So your plan feels like yours.")
                .font(F.round(16, .semibold)).foregroundStyle(C.creme2).multilineTextAlignment(.center)
            Spacer(minLength: 0)
            if store.avatar == nil {
                PhotosPicker(selection: $pick, matching: .images) { Text("ADD A PHOTO") }
                    .buttonStyle(.gameLarge)
                Button("Skip") { track(false); dismiss() }
                    .font(F.round(17, .semibold)).foregroundStyle(C.muted).frame(height: 40)
            } else {
                Button("LET'S GO") { dismiss() }.buttonStyle(.gameLarge)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
        .presentationDetents([.height(440)])
        .presentationBackground(C.char900)
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    store.setAvatar(img)
                    Haptics.play(.goal)
                    track(true)
                }
                pick = nil
            }
        }
    }

    private func track(_ added: Bool) { PostHogSDK.shared.capture("onboarding_photo", properties: ["added": added]) }
}

/// Onboarding answers ? PostHog (notes/38): one `onboarding_step` per page left (drop-off + the answer given), the
/// "Where did you find us?" pick as `found_us`, and every answer on `onboarding_completed` + the person.
/// NEVER the player's name (privacy page) ? only the multiple-choice picks.
@MainActor
enum OBTrack {
    static func answer(_ s: OBStep, _ a: Answers) -> Any? {
        switch s {
        case .position: a.position
        case .gender: a.gender
        case .foot: a.foot
        case .wants: a.wants?.joined(separator: ", ")
        case .source: a.source
        case .team: [Locator.shared.allowed ? "location" : nil, FriendsBook.shared.allowed ? "contacts" : nil,
                     Team.shared.pendingCode != nil ? "code" : nil].compactMap { $0 }.joined(separator: ", ")
        default: nil
        }
    }

    static func left(_ s: OBStep, _ a: Answers) {
        var p: [String: Any] = ["step": s.rawValue, "step_index": OBStep.allCases.firstIndex(of: s) ?? 0]
        if let v = answer(s, a) { p["answer"] = v }
        PostHogSDK.shared.capture("onboarding_step", properties: p)
        if s == .source, let src = a.source {
            PostHogSDK.shared.capture("found_us", properties: ["source": src], userProperties: ["found_us": src])
        }
    }

    static func all(_ a: Answers) -> [String: Any] {
        var p: [String: Any] = ["position": a.position, "onboarding_version": 3]
        for (k, v) in [("found_us", a.source), ("foot", a.foot), ("gender", a.gender)] { if let v { p[k] = v } }
        if let w = a.wants { p["wants"] = w }
        p["team_location"] = Locator.shared.allowed
        p["team_contacts"] = FriendsBook.shared.allowed
        p["team_code"] = Team.shared.pendingCode != nil
        return p
    }
}

/// When the ADD A PHOTO popup shows (user, 2026-11-08: "time the photo popup for once they get into the app and then
/// if they don't have a photo still once every 4 app opens"). Counts opens = launches + coming back from the
/// background. First time in the app (no photo) ? ask; after that every 4th open until there's a photo.
/// Never on top of a running session. DEBUG `-route photo` = ask now.
private struct PhotoNudge: ViewModifier {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var phase
    @AppStorage("sm.photo.asked") private var askedOnce = false
    @AppStorage("sm.photo.opens") private var opensSinceAsk = 0
    @State private var launched = false
    @State private var asking = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard !launched else { return }
                launched = true
                if DebugRoute.parts.first == "photo" { ask(); return }
                opened()
            }
            .onChange(of: phase) { old, p in if p == .active && old == .background { opened() } }
            .sheet(isPresented: $asking) { PhotoAsk() }
    }

    private func opened() {
        guard store.avatar == nil else { return }
        if !askedOnce { ask(); return }
        opensSinceAsk += 1
        if opensSinceAsk >= 4 { ask() }
    }

    private func ask() {
        askedOnce = true
        opensSinceAsk = 0
        // let the tab land first, and never over a running session
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            guard ActiveRun.shared.request == nil, FreeStart.shared.request == nil else { return }
            asking = true
        }
    }
}

extension View {
    func photoNudge() -> some View { modifier(PhotoNudge()) }
}
