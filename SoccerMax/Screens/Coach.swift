// AI COACH (SOCCER LAB, 2026-11-14). A chat with an AI coach (Claude Haiku 5.5) that knows the player: position,
// goals, today's session, the Fix List from Film, this week's training and today's food. The app sends a short summary
// of that with each message to our server (supabase/functions/coach), which holds the AI key and a daily limit; the
// conversation itself stays on this phone. Needs Sign in with Apple, like Team.
import SwiftUI

struct CoachMessage: Codable, Identifiable, Hashable {
    var id = UUID()
    /// "user" or "assistant"
    var role: String
    var text: String
    var date = Date()
    var isUser: Bool { role == "user" }
}

@MainActor @Observable
final class Coach {
    static let shared = Coach()

    private(set) var messages: [CoachMessage] = []
    private(set) var thinking = false
    /// The last send failed: this says why, and the chat offers to try again.
    private(set) var error: String?
    /// Messages left today, once the server has said.
    private(set) var remaining: Int?

    private static let key = "coach.chat.v1"
    /// One yes covers Coach, AI film reviews and food scans (AIVision.swift; v2 since 2026-11-15, so everyone is asked
    /// again with the wording that names film frames and meal photos).
    private static let consentKey = AIConsent.key

    /// The player agreed to send their messages and training summary to the AI company (App Store 5.1.2(i)).
    private(set) var consented = UserDefaults.standard.bool(forKey: AIConsent.key)
    func consent(_ yes: Bool) {
        consented = yes
        UserDefaults.standard.set(yes, forKey: Self.consentKey)
    }
    private static let keep = 60

    private init() {
        if let d = UserDefaults.standard.data(forKey: Self.key), let m = try? JSONDecoder().decode([CoachMessage].self, from: d) {
            messages = m
        }
        #if DEBUG
        if DebugRoute.parts.first == "coach", DebugRoute.parts.contains("demo") { messages = Self.demo; remaining = 27 }   // screenshots: nothing sent or saved
        #endif
    }

    /// Ask something new, or with no text, try the last question again.
    func send(_ text: String? = nil, store: AppStore) async {
        guard !thinking, consented || DebugRoute.parts.contains("demo") else { return }
        if let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            messages.append(CoachMessage(role: "user", text: String(t.prefix(1500))))
        }
        guard messages.last?.isUser == true else { return }
        error = nil
        thinking = true
        defer { thinking = false; save() }

        let history = messages.suffix(16).map { ["role": $0.role, "text": $0.text] }
        do {
            let (code, data) = try await Team.shared.api.function("coach", ["messages": history, "context": Self.context(store)])
            struct Reply: Decodable { let reply: String?; let error: String?; let remaining: Int? }
            let r = try? JSONDecoder().decode(Reply.self, from: data)
            if let left = r?.remaining { remaining = left }
            if (200..<300).contains(code), let t = r?.reply, !t.isEmpty {
                messages.append(CoachMessage(role: "assistant", text: t))
                Haptics.play(.pop)
            } else {
                error = r?.error ?? "Couldn't reach Coach. Try again."
            }
        } catch let e as SupabaseError {
            error = e.message
        } catch {
            self.error = "Couldn't reach Coach. Check your connection."
        }
    }

    func clear() {
        messages = []
        error = nil
        save()
    }

    /// Account deleted: the chat and the permission go too.
    func reset() {
        clear()
        consent(false)
        remaining = nil
    }

    private func save() {
        #if DEBUG
        if DebugRoute.parts.first == "coach" { return }
        #endif
        let m = Array(messages.suffix(Self.keep))
        UserDefaults.standard.set(try? JSONEncoder().encode(m), forKey: Self.key)
    }

    /// What Coach knows about the player, in plain lines. Only what the app already keeps on the phone.
    static func context(_ store: AppStore) -> String {
        let a = store.answers
        let lab = Lab.shared
        let lib = Library.shared
        var l: [String] = []
        l.append("Position: \(a.positionName)")
        if let f = a.foot { l.append("Strong foot: \(f)") }
        if let age = a.age { l.append("Age: \(age)") }
        if let lv = a.level { l.append("Level: \(lv)") }
        if let w = a.wants, !w.isEmpty { l.append("Wants from the app: \(w.joined(separator: ", "))") }
        if let g = a.goal { l.append("Goal: \(g)") }
        if !a.fix.isEmpty { l.append("Said they want to improve: \(a.fix.joined(separator: ", "))") }
        l.append("Usually trains: \(a.days.joined(separator: ", ")), about \(a.minutes) min, \(a.with.lowercased())")
        if !a.gear.isEmpty { l.append("Has: \(a.gear.joined(separator: ", "))") }
        l.append("Today: \(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))")

        let plan = LabPlan.today(position: a.position)
        if !plan.isEmpty {
            l.append("Today's session: " + plan.map { "\($0.name) (\($0.reps))\(lab.isDone($0.id) ? " - done" : "")" }.joined(separator: "; "))
        }
        let fixes = lab.fixList.filter { lib.has($0) }
        if !fixes.isEmpty {
            l.append("Fix List from film: " + fixes.map { "\(lib.drill($0).name) (\(lab.fixCount[$0] ?? 0) of \(Lab.fixGoal) done)" }.joined(separator: "; "))
        }
        for r in lab.reviews.prefix(3) {
            let when = r.date.formatted(.dateTime.day().month(.abbreviated))
            if let ai = r.ai {
                l.append("AI film review \"\(r.title)\" on \(when): \(ai.action), score \(ai.score)/100. To fix: " +
                         (ai.fixes.isEmpty ? "nothing" : ai.fixes.map(\.title).joined(separator: "; ")))
            } else {
                let found = r.mistakes.compactMap { FilmRules.find($0)?.label }
                l.append("Film review \"\(r.title)\" on \(when): " + (found.isEmpty ? "nothing to fix" : found.joined(separator: ", ")))
            }
        }
        l.append("Training this week: \(store.minutesThisWeek) min. Streak: \(store.air.days) days.")
        let weekStart = dateOf("Mon")
        let runs = lab.runs.filter { $0.date >= weekStart }
        if !runs.isEmpty {
            l.append("Running this week: \(String(format: "%.1f", runs.reduce(0) { $0 + $1.km })) km in \(runs.count) runs")
        }
        let d = lab.fuelToday
        let t = lab.targets
        let kcal = d.entries.reduce(0) { $0 + $1.kcal }
        let protein = Int(d.entries.reduce(0) { $0 + $1.protein }.rounded())
        // every drill in the app, by skill, so Coach recommends ones the player can open and follow
        let groups = Dictionary(grouping: lib.drills, by: \.skill)
        let skills = lib.categories.filter { groups[$0] != nil } + groups.keys.filter { !lib.categories.contains($0) }.sorted()
        l.append("Drills in the app, by skill: " + skills.map { s in "\(s): " + (groups[s] ?? []).map(\.name).joined(separator: ", ") }.joined(separator: " | "))
        l.append("Food today: \(kcal) of \(t.kcal) kcal, \(protein) of \(t.protein) g protein, water \(d.water) of \(t.water) glasses")
        if !d.entries.isEmpty { l.append("Eaten today: " + d.entries.suffix(8).map(\.name).joined(separator: ", ")) }
        return l.joined(separator: "\n")
    }

    #if DEBUG
    private static let demo: [CoachMessage] = [
        CoachMessage(role: "user", text: "What should I work on before Saturday's game?"),
        CoachMessage(role: "assistant", text: "Your last film review flagged holding the ball too long, so let's sharpen your scanning.\n\n- Scan and Turn: 3 x 10 passes. Look over your shoulder before every pass arrives.\n- Open-Up Touch: 3 x 12. First touch into space, away from pressure.\n\nKeep Friday light: 20 minutes of ball work and stretching, no hard running. Eat a good carb meal on Friday night and drink well."),
        CoachMessage(role: "user", text: "What should I eat on game day?"),
        CoachMessage(role: "assistant", text: "Three to four hours before kick-off, have a normal meal with carbs and some protein, like chicken and rice or pasta.\n\nAn hour before, a small snack such as a banana. Sip water through the morning and at every break.\n\nAfterwards, chocolate milk or a proper meal within an hour helps you recover."),
    ]
    #endif
}

// MARK: - the chat screen

struct CoachView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var coach = Coach.shared
    @State private var team = Team.shared
    @State private var draft = ""
    @State private var confirmClear = false
    @FocusState private var typing: Bool

    private var canChat: Bool { (team.signedIn && coach.consented) || DebugRoute.parts.contains("demo") }

    private let starters = [
        "What should I train today?",
        "How do I fix what my film review found?",
        "What should I eat before a match?",
        "Plan my week for me",
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if coach.messages.isEmpty { intro }
                        ForEach(coach.messages) { m in bubble(m).id(m.id) }
                        if coach.thinking { thinkingBubble.id("thinking") }
                        if let e = coach.error { errorRow(e).id("error") }
                        Color.clear.frame(height: 4).id("end")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .onAppear { proxy.scrollTo("end", anchor: .bottom) }
                .onChange(of: coach.messages.count) { _, _ in withAnimation(.snappy) { proxy.scrollTo("end", anchor: .bottom) } }
                .onChange(of: coach.thinking) { _, _ in withAnimation(.snappy) { proxy.scrollTo("end", anchor: .bottom) } }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottom }
        .background(AppBackground())
        .confirmationDialog("Clear this chat?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear chat", role: .destructive) { coach.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The messages are removed from this phone.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            CoachBadge(size: 46, talking: coach.thinking)
            VStack(alignment: .leading, spacing: 1) {
                Text("Socco").font(.system(size: 20, weight: .bold)).foregroundStyle(C.creme)
                Text(coach.thinking ? "Typing…" : "Your football buddy").font(F.round(13, .medium))
                    .foregroundStyle(coach.thinking ? C.brandHi : C.muted)
            }
            Spacer(minLength: 0)
            if !coach.messages.isEmpty {
                Button { confirmClear = true } label: {
                    Image(systemName: "trash").font(.system(size: 15, weight: .semibold)).foregroundStyle(C.muted)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Clear chat")
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(C.creme)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(C.char700))
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8).padding(.bottom, 10)
        .background(C.char900.opacity(0.6))
        .overlay(alignment: .bottom) { Rectangle().fill(C.line).frame(height: 1) }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Mascot(lines: ["Hey \(store.answers.firstName)! I'm Socco.", "Ask me anything about your game."], size: 120)
                    .frame(maxWidth: .infinity)
                Text("Hi \(store.answers.firstName), ask me anything.").font(.system(size: 22, weight: .bold)).foregroundStyle(C.creme)
                Text("I know your position, today's session, your Fix List and what you've eaten today, so my answers fit you. Ask for a drill and I'll pick from the ones in the app.")
                    .font(F.round(15, .medium)).foregroundStyle(C.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 14)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(starters, id: \.self) { s in
                    Button { ask(s) } label: {
                        HStack {
                            Text(s).font(F.round(15, .semibold)).foregroundStyle(C.creme).multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .bold)).foregroundStyle(C.brandHi)
                        }
                        .padding(.horizontal, 14).frame(minHeight: 48)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(C.char800)
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(C.line, lineWidth: 1)))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canChat)
                }
            }
        }
        .padding(.bottom, 8)
    }

    private func bubble(_ m: CoachMessage) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            if m.isUser { Spacer(minLength: 48) } else { CoachBadge(size: 30) }
            Text(verbatim: m.text)
                .font(F.round(15, .medium))
                .foregroundStyle(m.isUser ? Color.white : C.creme)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(m.isUser ? AnyShapeStyle(LinearGradient(colors: [C.brand, C.brandMid], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(C.char800))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(m.isUser ? Color.clear : C.line, lineWidth: 1))
                )
            if !m.isUser { Spacer(minLength: 24) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(m.isUser ? "You" : "Socco"): \(m.text)")
    }

    private var thinkingBubble: some View {
        HStack(alignment: .bottom, spacing: 8) {
            CoachBadge(size: 30, talking: true)
            HStack(spacing: 8) {
                ProgressView().tint(C.brandHi).controlSize(.small)
                Text("Socco is thinking…").font(F.round(14, .medium)).foregroundStyle(C.muted)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(C.char800))
            Spacer(minLength: 0)
        }
    }

    private func errorRow(_ e: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(C.gold)
            Text(e).font(F.round(14, .semibold)).foregroundStyle(C.creme2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if coach.messages.last?.isUser == true, coach.remaining != 0 {
                Button("Try again") { Task { await coach.send(store: store) } }
                    .font(F.round(14, .bold)).foregroundStyle(C.brandHi)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(C.gold.opacity(0.10)))
    }

    @ViewBuilder private var bottom: some View {
        VStack(spacing: 8) {
            if team.signedIn && !coach.consented && !DebugRoute.parts.contains("demo") {
                consentPanel
            } else if canChat {
                HStack(alignment: .bottom, spacing: 10) {
                    TextField("", text: $draft, prompt: Text("Ask Socco…").foregroundStyle(C.muted), axis: .vertical)
                        .lineLimit(1...5)
                        .font(F.round(16, .medium)).foregroundStyle(C.creme)
                        .focused($typing)
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(C.char800)
                            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(typing ? C.brand.opacity(0.6) : C.line, lineWidth: 1)))
                    let empty = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    Button { ask(draft) } label: {
                        Image(systemName: "arrow.up").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(empty || coach.thinking ? C.char700 : C.brand))
                    }
                    .disabled(empty || coach.thinking)
                    .accessibilityLabel("Send")
                }
                HStack {
                    Text("Socco can get things wrong. Not medical advice.")
                    Spacer(minLength: 8)
                    if let left = coach.remaining { Text("\(left) left today").monospacedDigit() }
                }
                .font(F.round(11, .medium)).foregroundStyle(C.muted)
            } else {
                VStack(spacing: 10) {
                    Text("Sign in to talk to Coach. It keeps your chats safe and your daily messages fair.")
                        .font(F.round(14, .medium)).foregroundStyle(C.muted).multilineTextAlignment(.center)
                    AppleSignIn()
                    if let e = team.error { Text(e).font(F.round(13, .semibold)).foregroundStyle(C.gold) }
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 8)
        .background(C.char900.opacity(0.92).ignoresSafeArea())
        .overlay(alignment: .top) { Rectangle().fill(C.line).frame(height: 1) }
    }

    /// Asked once, before the first message (App Store 5.1.2(i): say who the data goes to, and get a yes first).
    private var consentPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Before you start").font(.system(size: 17, weight: .bold)).foregroundStyle(C.creme)
            Text(AIConsent.text)
                .font(F.round(14, .medium)).foregroundStyle(C.creme2)
                .fixedSize(horizontal: false, vertical: true)
            Link("How your data is used", destination: Legal.privacy)
                .font(F.round(14, .semibold)).foregroundStyle(C.brandHi)
            HStack(spacing: 10) {
                Button("Not now") { dismiss() }
                    .buttonStyle(.game(.charcoal, height: 48, font: 17))
                Button("I agree") { coach.consent(true); Haptics.play(.latch) }
                    .buttonStyle(.game(.brand, height: 48, font: 17))
            }
        }
    }

    private func ask(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !coach.thinking, canChat else { return }
        draft = ""
        Haptics.play(.stud)
        Task { await coach.send(t, store: store) }
    }
}

/// Coach's little round mark: a glowing blue circle with a chat-and-ball symbol.
struct CoachBadge: View {
    var size: CGFloat = 40
    /// Socco's mouth moves (while he's answering).
    var talking = false
    var body: some View {
        // ASK SOCCO (2026-11-21, Fasih: the AI coach is Socco, the mascot, alive and answering): his face, not a sparkle
        MascotDrawn(talking: talking)
            .frame(width: size * 1.12, height: size * 1.12)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The old sparkle badge (kept for reference; not used).
private struct SparkleBadge: View {
    var size: CGFloat = 40
    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: size * 0.44, weight: .bold)).foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(LinearGradient(colors: [C.brandHi, C.brand], startPoint: .topLeading, endPoint: .bottomTrailing)))
            .shadow(color: C.brand.opacity(0.5), radius: size * 0.2)
            .accessibilityHidden(true)
    }
}
