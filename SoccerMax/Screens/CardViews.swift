// Pieces the Profile tab (ProfileViews.swift) pushes: one stat's page, settings ? plus the old
// spider-chart card (PlayerRadarCard), no longer on a tab since the Card tab became Profile (2026-10-24).
import Charts
import PhotosUI
import SwiftUI
import RevenueCatUI
import StoreKit

enum CardRoute: Hashable { case stat(String), settings }

private let lib = Library.shared
private func signed(_ d: Int) -> String { d > 0 ? "+\(d)" : "\(d)" }

struct PlayerRadarCard: View {
    var onSelect: ((String) -> Void)?
    @Environment(AppStore.self) private var store

    var body: some View {
        let a = store.answers
        let avg = Int((Double(lib.now.values.reduce(0, +)) / Double(lib.now.count)).rounded())
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 0) {
                    Disp("\(avg)", size: 52, color: C.brand)
                    Text("OVR").font(F.round(13, .bold)).foregroundStyle(C.muted)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Disp(a.firstName.uppercased(), size: 24)
                    Text("\(a.foot ?? "Right") foot · \(a.level ?? "Club")").font(F.round(15)).foregroundStyle(C.muted)
                }
                .padding(.top, 6)
                Spacer()
                Text(a.position)
                    .font(F.display(22)).foregroundStyle(.white)
                    .frame(width: 64, height: 70)
                    .background(Hexagon().fill(LinearGradient(colors: [C.brandHi, C.brand, C.brandMid], startPoint: .top, endPoint: .bottom)))
                    .overlay(Hexagon().stroke(C.brandInk, lineWidth: 2.5))
            }
            Radar(axes: lib.axes, now: lib.now, start: lib.start, onSelect: onSelect)
                .frame(height: 290)
            HStack(spacing: 22) {
                HStack(spacing: 6) { Capsule().fill(C.brand).frame(width: 20, height: 3); Text("Now") }
                HStack(spacing: 6) {
                    HStack(spacing: 3) { ForEach(0..<3, id: \.self) { _ in Capsule().fill(C.creme).frame(width: 4, height: 2) } }
                    Text("When you started")
                }
            }
            .font(F.round(14)).foregroundStyle(C.creme2)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x24302A), C.char850], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(C.brand.opacity(0.55), lineWidth: 2))
    }
}

struct Hexagon: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let pts = (0..<6).map { i -> CGPoint in
            let a = Double(i) * .pi / 3 - .pi / 2
            return CGPoint(x: r.midX + cos(a) * r.width / 2, y: r.midY + sin(a) * r.height / 2)
        }
        p.addLines(pts)
        p.closeSubpath()
        return p
    }
}

/// Spider chart: where you started (creme, dashed) under where you are now (green, solid). Tap an axis.
struct Radar: View {
    let axes: [Axis]
    let now: [String: Int]
    let start: [String: Int]
    var onSelect: ((String) -> Void)?

    private func point(_ i: Int, _ v: Double, _ r: Double, _ c: CGPoint) -> CGPoint {
        let a = -Double.pi / 2 + Double(i) / Double(axes.count) * .pi * 2
        return CGPoint(x: c.x + cos(a) * r * v / 100, y: c.y + sin(a) * r * v / 100)
    }
    private func ring(_ v: Double, _ r: Double, _ c: CGPoint) -> Path {
        var p = Path()
        p.addLines((0..<axes.count).map { point($0, v, r, c) })
        p.closeSubpath()
        return p
    }
    private func poly(_ vals: [String: Int], _ r: Double, _ c: CGPoint) -> Path {
        var p = Path()
        p.addLines(axes.indices.map { point($0, Double(vals[axes[$0].key] ?? 0), r, c) })
        p.closeSubpath()
        return p
    }
    private func spokes(_ r: Double, _ c: CGPoint) -> Path {
        var p = Path()
        for i in axes.indices { p.move(to: c); p.addLine(to: point(i, 100, r, c)) }
        return p
    }

    var body: some View {
        GeometryReader { g in
            let c = CGPoint(x: g.size.width / 2, y: g.size.height / 2)
            let r = Double(min(g.size.width, g.size.height)) * 0.36
            ZStack {
                ForEach([25.0, 50, 75, 100], id: \.self) { v in
                    ring(v, r, c).stroke(C.char600, lineWidth: v == 100 ? 1.25 : 1)
                }
                spokes(r, c).stroke(C.char600, lineWidth: 1)
                poly(start, r, c).stroke(C.creme.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round, dash: [4, 4]))
                poly(now, r, c).fill(C.brand.opacity(0.14))
                poly(now, r, c).stroke(C.brand, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                ForEach(axes.indices, id: \.self) { i in
                    dot(point(i, Double(now[axes[i].key] ?? 0), r, c))
                    label(axes[i]).position(point(i, 100, r + 30, c))
                }
            }
        }
    }

    private func dot(_ p: CGPoint) -> some View {
        Circle().fill(C.brand).overlay(Circle().stroke(C.char850, lineWidth: 2)).frame(width: 9, height: 9).position(p)
    }

    private func label(_ ax: Axis) -> some View {
        Button { onSelect?(ax.key) } label: {
            Text(ax.label.uppercased())
                .font(.system(size: 10.5, weight: .bold, design: .monospaced)).kerning(0.8)
                .foregroundStyle(C.muted)
                .multilineTextAlignment(.center)
                .frame(width: 80, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.press(.stud))
        .disabled(onSelect == nil)
    }
}

struct StatTile: View {
    let value: String
    let label: String
    var flame = false
    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .top, spacing: 2) {
                Disp(value, size: 30)
                if flame { Image(systemName: "flame.fill").font(.system(size: 15)).foregroundStyle(C.gold) }
            }
            Text(label).font(F.round(12, .bold)).foregroundStyle(C.creme2).multilineTextAlignment(.center).lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 92)
        .gameCard(padding: 8, radius: 20)
    }
}

struct StatBar: View {
    let was: Int
    let now: Int
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(C.char950)
                Capsule().fill(C.brand).frame(width: g.size.width * Double(now) / 100)
                Capsule().fill(C.creme.opacity(0.35)).frame(width: g.size.width * Double(was) / 100)
            }
        }
        .frame(height: 8)
    }
}

struct StatDetail: View {
    let key: String
    var body: some View {
        let a = lib.axes.first { $0.key == key } ?? lib.axes[0]
        let s = lib.start[a.key]!, n = lib.now[a.key]!
        let hist = [s, s + 2, s + 3, s + 3, s + 5, n - 1, n]
        List {
            Section {
                VStack(spacing: 10) {
                    Disp("\(n)", size: 72, color: C.brand)
                    Text("\(signed(n - s)) since you started")
                        .font(F.round(15, .bold)).foregroundStyle(C.brandInk)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Capsule().fill(C.brand))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
            }
            Section {
                Chart(Array(hist.enumerated()), id: \.offset) { i, v in
                    LineMark(x: .value("Week", i), y: .value("Rating", v)).foregroundStyle(C.brand).lineStyle(StrokeStyle(lineWidth: 3))
                    PointMark(x: .value("Week", i), y: .value("Rating", v)).foregroundStyle(C.brand)
                }
                .chartYScale(domain: (hist.min()! - 4)...(hist.max()! + 4))
                .chartXAxis(.hidden)
                .frame(height: 160)
                .padding(.vertical, 10)
                .listRowBackground(C.char800)
            } header: { Text("Last 6 weeks").font(F.round(15, .bold)).foregroundStyle(C.muted).textCase(nil) }
            Section {
                ForEach(["cone-slalom", "receive-across", "shadow-1v1"], id: \.self) { id in
                    let d = lib.drill(id)
                    NavigationLink(value: d) {
                        HStack {
                            Text(d.name).font(F.round(17, .semibold)).foregroundStyle(C.creme)
                            Spacer()
                            Text("+1 per session").font(F.round(13)).foregroundStyle(C.muted)
                        }
                    }
                    .listRowBackground(C.char800)
                }
            } header: { Text("What builds it: \(a.builds.lowercased())").font(F.round(15, .bold)).foregroundStyle(C.muted).textCase(nil) }
            footer: { Text("A training rating: it goes up when you train, not a measured ability.").font(F.round(13)).foregroundStyle(C.muted) }
        }
        .listStyle(.insetGrouped)
        .screenTitle(a.label.uppercased())
        .page()
    }
}

/// Settings ? Test onboarding: jump into the flow at any step. It runs over the app (nothing is reset); BACK TO APP
/// closes it and puts the real answers + week back, so testing never changes the player's profile.
struct TestOnboardingPicker: View {
    @Environment(AppStore.self) private var store
    @State private var start: OBStep?
    @State private var saved: (Answers, Week, [String: [String]])?

    var body: some View {
        List(Array(OBStep.allCases.enumerated()), id: \.element) { i, s in
            Button {
                saved = (store.answers, store.week, store.daySessions)
                start = s
            } label: {
                HStack(spacing: 12) {
                    Text("\(i + 1)").font(F.round(14, .bold)).foregroundStyle(C.muted).frame(width: 26, alignment: .leading)
                    Text(s.label).foregroundStyle(C.creme)
                    Spacer()
                    Image(systemName: "play.fill").font(.system(size: 12)).foregroundStyle(C.brand)
                }
            }
        }
        .font(F.round(17, .medium))
        .screenTitle("TEST ONBOARDING")
        .page()
        .fullScreenCover(item: $start, onDismiss: restore) { s in
            OnboardingFlow(start: s, exitTest: { start = nil })
                .environment(store)
                .preferredColorScheme(.dark)
        }
    }

    private func restore() {
        guard let (a, w, d) = saved else { return }
        store.answers = a; store.week = w; store.daySessions = d
        saved = nil
    }
}

extension OBStep: Identifiable { var id: String { rawValue } }

// SETTINGS v4 (2026-11-08, user: "update settings completely with the new app"): YOU = photo · name · position ·
// gender · strong foot (age / level / usually train dropped with onboarding v3); TRAINING = logged sessions + streak
// reminders toggle; new SPREAD THE WORD = invite a friend + rate (the rate-us page left onboarding).
// SETTINGS v2 (2026-10-30). The user: "make the settings look a lot better. Right now they are filled with unnecessary
// stuff that's already in the onboarding." Cut: the GO MAX upsell (the app is already paid), the dead Reminders + Units
// controls and the version line. v3 (same day): "allow the user to edit things like their position, name, strong foot,
// etc." ? a YOU group of one-tap menus is back (name · age · level · position · foot · train with); the plan hero is a
// real coloured card (gold LIFETIME / green YEARLY·MONTHLY) and a subscription card is a button with an arrow ? the
// "why are you leaving?" flow (Screens/CancelFlow.swift) before Apple's own cancel sheet.

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @AppStorage("sm.haptics") private var haptics = true
    /// DEBUG "Change plan": fakes the plan card (and the cancel flow) without buying anything. "" = your real plan.
    @AppStorage("sm.debug.plan") private var debugPlan = ""
    @State private var confirmReset = false
    @State private var manage = false
    @State private var cancelling = DebugRoute.parts.contains("cancel")
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var deleteResult: Bool?
    @State private var restoring = false
    /// RevenueCat Customer Center: manage / cancel / refund / plan change, all in-app (notes/39).
    @State private var billing = false
    @State private var editName = false
    @State private var first = ""
    @State private var last = ""
    @State private var ends: Date?
    @State private var renews = true
    @State private var team = Team.shared
    @State private var photo: PhotosPickerItem?
    @State private var remindersBlocked = false
    /// The toggle flips at once; rolled back if iOS says no.
    @State private var remindersOn = false
    private let pay = Purchases.shared

    static let positions = ["GK", "CB", "LB", "RB", "LWB", "RWB", "CDM", "CM", "CAM", "LM", "RM", "LW", "RW", "ST"]

    var body: some View {
        let a = store.answers
        ScrollView {
            VStack(spacing: 22) {
                PlanCard(plan: plan, ends: ends, renews: renews) {
                    if renews { cancelling = true } else { manage = true }
                }
                group("YOU") {
                    PhotosPicker(selection: $photo, matching: .images) {
                        SettingRow(icon: "camera.fill", title: "Photo") {
                            Avatar(size: 34).allowsHitTesting(false); Chevron()
                        }
                    }
                    .contextMenu {
                        if store.avatar != nil { Button("Remove photo", role: .destructive) { store.setAvatar(nil) } }
                    }
                    line
                    Button {
                        first = a.first; last = a.last; editName = true
                    } label: {
                        SettingRow(icon: "person.fill", title: "Name") {
                            Text(fullName).foregroundStyle(C.muted).lineLimit(1); Chevron()
                        }
                    }
                    line
                    pick("mappin.and.ellipse", "Position", a.position, Self.positions,
                         label: { p in Library.shared.positions[p].map { "\(p) · \($0)" } ?? p }) { store.answers.position = $0 }
                    line
                    pick("figure.stand", "Gender", a.gender, ["Male", "Female", "Prefer not to say"]) { store.answers.gender = $0 }
                    line
                    pick("shoeprints.fill", "Strong foot", a.foot, ["Right", "Left", "Both"]) { store.answers.foot = $0 }
                }
                group("TRAINING") {
                    NavigationLink { LoggedPage() } label: {
                        SettingRow(icon: "checkmark.seal.fill", title: "Logged sessions") {
                            Text("\(store.completions.count)").foregroundStyle(C.muted); Chevron()
                        }
                    }
                    line
                    SettingRow(icon: "bell.fill", title: "Streak reminders") {
                        Toggle("", isOn: Binding(get: { remindersOn }, set: { on in remindersOn = on; Task { await setReminders(on) } }))
                            .labelsHidden().tint(C.brand)
                    }
                }
                group("APP") {
                    SettingRow(icon: "iphone.radiowaves.left.and.right", title: "Haptics") {
                        Toggle("", isOn: $haptics).labelsHidden().tint(C.brand)
                    }
                }
                group("SPREAD THE WORD") {
                    ShareLink(item: URL(string: "https://soccermax.app")!,
                              message: Text("Train with me on Soccer Lab. Join my team!")) {
                        SettingRow(icon: "person.2.wave.2.fill", title: "Invite a friend") { Chevron(out: true) }
                    }
                    line
                    Link(destination: URL(string: "https://apps.apple.com/app/id6828180179?action=write-review")!) {
                        SettingRow(icon: "star.fill", title: "Rate Soccer Lab") { Chevron(out: true) }
                    }
                }
                group("HELP") {
                    Link(destination: URL(string: "mailto:support@soccermax.app")!) {
                        SettingRow(icon: "envelope.fill", title: "Email support") { Chevron(out: true) }
                    }
                    line
                    Button { billing = true } label: {
                        SettingRow(icon: "creditcard.fill", title: "Billing & subscription") { Chevron() }
                    }
                    line
                    Button {
                        restoring = true
                        Task { await pay.restore(); restoring = false }
                    } label: {
                        SettingRow(icon: "arrow.clockwise", title: "Restore purchases") {
                            if restoring { ProgressView() }
                        }
                    }
                    line
                    Link(destination: Legal.privacy) { SettingRow(icon: "hand.raised.fill", title: "Privacy") { Chevron(out: true) } }
                    line
                    Link(destination: Legal.terms) { SettingRow(icon: "doc.text.fill", title: "Terms") { Chevron(out: true) } }
                }
                #if DEBUG
                group("REVIEW · DEBUG ONLY") {
                    NavigationLink { TestOnboardingPicker() } label: {
                        SettingRow(icon: "list.number", title: "Test onboarding") { Chevron() }
                    }
                    line
                    Button { confirmReset = true } label: {
                        SettingRow(icon: "arrow.counterclockwise", title: "Start onboarding again") { EmptyView() }
                    }
                    line
                    pick("creditcard.fill", "Change plan", debugPlan.isEmpty ? "Real" : debugPlan.capitalized,
                         ["Real", "Lifetime", "Yearly", "Monthly", "Trial"]) {
                        debugPlan = $0 == "Real" ? "" : $0.lowercased()
                    }
                }
                #endif
                if team.signedIn || DebugRoute.parts.contains("account") {   // DEBUG `-route card:settings:account`
                    VStack(alignment: .leading, spacing: 8) {
                        group("ACCOUNT") {
                            Button { confirmDelete = true } label: {
                                SettingRow(icon: "trash.fill", title: "Delete account", danger: true) {
                                    if deleting { ProgressView() }
                                }
                            }
                            .disabled(deleting)
                        }
                        Text("Deletes your profile, your teams, your messages and your backup. Cancel your subscription from your plan at the top.")
                            .font(F.round(13)).foregroundStyle(C.muted).padding(.horizontal, 6)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .defaultScrollAnchor(DebugRoute.parts.contains("bottom") ? .bottom : .top)
        .screenTitle("SETTINGS")
        .manageSubscriptionsSheet(isPresented: $manage)
        .presentCustomerCenter(isPresented: $billing, onDismiss: { Task { await pay.refresh(); await loadRenewal() } })
        .sheet(isPresented: $cancelling) { CancelFlow(plan: plan) }
        .page()
        .task { await loadRenewal() }
        // on only if they said yes AND iOS still allows it (they may have turned it off in the Settings app)
        .task { let denied = await Reminders.denied(); remindersOn = store.answers.notify == true && !denied }
        .onChange(of: debugPlan) { _, _ in Task { await loadRenewal() } }
        .onChange(of: cancelling) { _, open in if !open { Task { await pay.refresh(); await loadRenewal() } } }
        .onChange(of: haptics) { _, v in if v { Haptics.play(.latch) } }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    store.setAvatar(img); Haptics.play(.pop)
                }
                photo = nil
            }
        }
        .alert("Reminders are off in iOS", isPresented: $remindersBlocked) {
            Button("Open Settings") { if let u = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(u) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Turn on notifications for Soccer Lab in the Settings app, then switch this back on.") }
        .alert("Your name", isPresented: $editName) {
            TextField("First name", text: $first).textInputAutocapitalization(.words)
            TextField("Last name", text: $last).textInputAutocapitalization(.words)
            Button("Save") {
                store.answers.first = first.trimmingCharacters(in: .whitespaces)
                store.answers.last = last.trimmingCharacters(in: .whitespaces)
                Haptics.play(.latch)
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) {
                deleting = true
                Task { deleteResult = await team.deleteAccount(); deleting = false }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This can't be undone. You'll leave every team and your messages and backup are deleted. Training on this phone stays.") }
        .alert(deleteResult == true ? "Account deleted" : "Couldn't delete your account",
               isPresented: Binding(get: { deleteResult != nil }, set: { if !$0 { deleteResult = nil } })) { Button("OK") {} } message: {
            Text(deleteResult == true ? "Your account and team data are gone. Don't forget to cancel your subscription in your App Store settings if you have one."
                 : "Check your signal and try again, or email support@soccermax.app and we'll delete it for you.")
        }
        .confirmationDialog("Start onboarding again? Your answers are cleared.", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Start again", role: .destructive) { store.resetOnboarding() }
        }
    }

    /// On ? ask iOS + schedule (Data/Reminders.swift); iOS said no before ? point at the Settings app. Off ? cancel.
    private func setReminders(_ on: Bool) async {
        Haptics.play(.latch)
        if on {
            let ok = await Reminders.turnOn(store.answers)
            store.answers.notify = ok
            remindersOn = ok
            if !ok, await Reminders.denied() { remindersBlocked = true }
        } else {
            Reminders.turnOff()
            store.answers.notify = false
        }
    }

    private var fullName: String {
        let a = store.answers
        let l = a.last.trimmingCharacters(in: .whitespaces)
        return l.isEmpty ? a.firstName : "\(a.firstName) \(l)"
    }

    // MARK: the plan you're on

    private var plan: PlanKind {
        #if DEBUG
        if let k = PlanKind(rawValue: debugPlan) { return k }
        for k in [PlanKind.lifetime, .yearly, .monthly, .trial] where DebugRoute.parts.contains(k.rawValue) { return k }
        #endif
        let o = pay.owned
        if o.contains(PayID.lifetime) || team.freeForLife { return .lifetime }
        if o.contains(PayID.yearly) || o.contains(PayID.yearlyNoTrial) || o.contains(PayID.stay) { return .yearly }
        if o.contains(PayID.monthly) { return .monthly }
        if team.onTrial { return .trial }
        return .member
    }

    /// When the subscription renews (or ends, if auto-renew is off).
    private func loadRenewal() async {
        #if DEBUG
        if !debugPlan.isEmpty || ([PlanKind.yearly, .monthly].contains(plan) && pay.owned.isEmpty) {
            let days = ["yearly": 300, "monthly": 21, "trial": 5][plan.rawValue]
            ends = days.flatMap { Calendar.current.date(byAdding: .day, value: $0, to: .now) }
            renews = plan.subscription
            return
        }
        #endif
        if plan == .trial { ends = team.trialUntil; renews = false; return }
        await pay.refresh()
        if let e = pay.entitlement, e.isActive, let end = e.expirationDate { ends = end; renews = e.willRenew }
    }

    // MARK: building blocks

    private var line: some View { Rectangle().fill(C.creme.opacity(0.06)).frame(height: 1).padding(.leading, 58) }

    private func pick(_ icon: String, _ title: String, _ value: String?, _ options: [String],
                      label: @escaping (String) -> String = { $0 }, set: @escaping (String) -> Void) -> some View {
        Menu {
            ForEach(options, id: \.self) { o in
                Button {
                    set(o); Haptics.play(.latch)
                } label: {
                    if o == value { Label(label(o), systemImage: "checkmark") } else { Text(label(o)) }
                }
            }
        } label: {
            SettingRow(icon: icon, title: title) {
                Text(value ?? "Pick").foregroundStyle(value == nil ? C.brand : C.muted).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .heavy)).foregroundStyle(C.muted)
            }
        }
    }

    private func group<V: View>(_ title: String, @ViewBuilder _ rows: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(F.round(13, .heavy)).kerning(1.6).foregroundStyle(C.creme2).padding(.horizontal, 6)
            VStack(spacing: 0) { rows() }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LinearGradient(colors: [C.char800, C.char850], startPoint: .top, endPoint: .bottom)))
        }
    }
}

enum PlanKind: String {
    case lifetime, yearly, monthly, trial, member
    var name: String { ["lifetime": "LIFETIME", "yearly": "YEARLY", "monthly": "MONTHLY", "trial": "FREE WEEK", "member": "MEMBER"][rawValue]! }
    var subscription: Bool { self == .yearly || self == .monthly }
}

/// The hero at the top of Settings: gold for Lifetime, green for a subscription (a button with an arrow ? the cancel
/// flow), a plain soft surface for a free week / member. v4 (2026-11-08): borderless like the Sessions tab ? no ink
/// stroke, no stitched edge, no lip.
struct PlanCard: View {
    let plan: PlanKind
    let ends: Date?
    let renews: Bool
    let open: () -> Void

    private var tint: Tint { plan == .lifetime ? .gold : plan.subscription ? .brand : .charcoal }

    var body: some View {
        if plan.subscription {
            Button(action: open) { card }.buttonStyle(.press(.pop))
                .accessibilityHint("Manage or cancel your plan")
        } else { card }
    }

    private var line: String {
        let d = ends.map { $0.formatted(.dateTime.month(.abbreviated).day()) }
        switch plan {
        case .lifetime: return Team.shared.freeForLife && !Purchases.shared.owned.contains(PayID.lifetime)
            ? "Free for life with a code. Yours forever." : "Paid once. Yours forever."
        case .yearly, .monthly:
            let price = Purchases.shared.price(plan == .yearly ? PayID.yearly : PayID.monthly)
            let per = plan == .yearly ? "year" : "month"
            guard let d else { return "\(price) a \(per)" }
            return renews ? "\(price) a \(per) · renews \(d)" : "Ends \(d) · won't renew"
        case .trial: return d.map { "Free until \($0)" } ?? "Free from your team"
        case .member: return "Every drill, every session."
        }
    }

    private var card: some View {
        let ink = tint.ink
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        return HStack(spacing: 16) {
            // the real app icon (user: "use the real app icon not the made up one")
            Image("AppIconImage").resizable().scaledToFill()
                .frame(width: 70, height: 70)
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
            VStack(alignment: .leading, spacing: 3) {
                Text("SOCCER LAB").font(F.round(13, .bold)).tracking(1.4)
                    .foregroundStyle(plan.subscription || plan == .lifetime ? ink.opacity(0.8) : C.brand)
                Disp(plan.name, size: 36, color: .white, ink: ink)
                Text(line).font(F.round(15, .semibold))
                    .foregroundStyle(plan.subscription || plan == .lifetime ? ink : C.muted)
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
            if plan.subscription {
                Image(systemName: "chevron.right").font(.system(size: 18, weight: .black)).foregroundStyle(ink)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(.white.opacity(0.3)))
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            shape.fill(plan.subscription || plan == .lifetime
                ? AnyShapeStyle(LinearGradient(colors: [tint.hi, tint.face, tint.lo], startPoint: .topLeading, endPoint: .bottomTrailing))
                : AnyShapeStyle(LinearGradient(colors: [C.char800, C.char850], startPoint: .top, endPoint: .bottom)))
        )
    }
}

/// One settings row: an icon tile, a title, and whatever sits on the right.
private struct SettingRow<Trailing: View>: View {
    let icon: String
    let title: String
    var danger = false
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(danger ? Color.red : C.brandHi)
                .frame(width: 36, height: 36)
                .background(Circle().fill(danger
                    ? AnyShapeStyle(Color.red.opacity(0.15))
                    : AnyShapeStyle(RadialGradient(colors: [C.brand.opacity(0.38), C.brand.opacity(0.10)], center: .center, startRadius: 0, endRadius: 22))))
            Text(title).font(F.round(17, .semibold)).foregroundStyle(danger ? Color.red : C.creme)
            Spacer(minLength: 8)
            trailing.font(F.round(16, .medium))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

private struct Chevron: View {
    var out = false
    var body: some View {
        Image(systemName: out ? "arrow.up.right" : "chevron.right")
            .font(.system(size: 13, weight: .heavy)).foregroundStyle(C.muted)
    }
}
