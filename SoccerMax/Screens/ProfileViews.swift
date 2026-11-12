// PROFILE tab (2026-10-24, was the Card tab). The user: "change the 'card' section to be profile. Then, put in a pfp,
// name, training level (with a new unsplash cool image) and then your fifa style card with all your stats. Then, find
// a way to get every local soccer team in a list so the user can pick their club."
// 2026-10-26: the training level banner was removed ("keep that to the top of sessions") ? the level lives only in the
// Sessions tab's stadium slider. Top to bottom: photo + name + team chip ? the FC card (club crest on it) with its six
// stats spelled out ? share. Clubs come from Hat Trick Local (Data/Club.swift).
// 2026-10-26: "add the player's level and streak into the profile" ? under the name: ONE row of three tiles ?
// STREAK (small live fire + days) · LEVEL (number + mini bar) · RANK (badge + name); tap level/rank ? all badges.
// 2026-10-27: the FC card + six stat tiles ? ONE spider graph (UI/SpiderGraph.swift): photo or name in the middle,
// onboarding stats (dashed START) grown by training (green NOW), OVR + "+N FROM TRAINING" only.
import PhotosUI
import SwiftUI

struct ProfileTab: View {
    @Environment(AppStore.self) private var store
    @State private var path: NavigationPath = {
        var p = NavigationPath()
        let r = DebugRoute.parts
        guard ["card", "profile"].contains(r.first), r.count > 1 else { return p }
        switch r[1] {
        case "settings": p.append(CardRoute.settings)
        case "stat": p.append(CardRoute.stat(r[safe: 2] ?? "passing"))
        default: break
        }
        return p
    }()
    @State private var showTeams = DebugRoute.parts.first == "profile" && DebugRoute.parts[safe: 1] == "teams"
    @AppStorage(ShownTeam.key) private var shownTeam = ""
    @State private var editName = false
    @State private var first = ""
    @State private var last = ""
    @State private var photo: PhotosPickerItem?
    @State private var showBadges = false
    @State private var showYear = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 22) {
                    TabHeader(title: "Profile") {
                        Button { path.append(CardRoute.settings) } label: { Image(systemName: "gearshape.fill").font(.system(size: 18, weight: .bold)) }
                            .buttonStyle(.gameRound(.charcoal, size: 46))
                    }
                    identity
                    numbers
                    // the big flame is gone (2026-11-13): the streak is the first tile above
                    // v3 (2026-11-08, user): no rank card; tap the level bar ? every level
                    Button { showBadges = true } label: { LevelBar(level: store.level, showsMore: true) }
                        .buttonStyle(.press)
                    TrainingChart()
                    StatsPair(best: store.air.best)   // all time + this month, side by side
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
            .defaultScrollAnchor(DebugRoute.parts.contains("bottom") ? .bottom : .top)
            .tabRoot("Profile")
            .page()
            .navigationDestination(for: CardRoute.self) { r in
                switch r {
                case .stat(let k): StatDetail(key: k)
                case .settings: SettingsView()
                }
            }
            .navigationDestination(for: Drill.self) { DrillDetail(drill: $0) }
            .navigationDestination(for: Completion.self) { LoggedDetail(c: $0) }   // a session picked on the graph
            .sheet(isPresented: $showTeams) { TeamDisplayPicker() }
            .sheet(isPresented: $showBadges) { LevelsSheet() }
            .sheet(isPresented: $showYear) { YearSheet() }
            .alert("Your name", isPresented: $editName) {
                TextField("First name", text: $first).textInputAutocapitalization(.words)
                TextField("Last name", text: $last).textInputAutocapitalization(.words)
                Button("Save") {
                    store.answers.first = first.trimmingCharacters(in: .whitespaces)
                    store.answers.last = last.trimmingCharacters(in: .whitespaces)
                    Haptics.play(.latch)
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Your last name goes on your card.") }
            .onAppear {
                #if DEBUG
                if DebugRoute.parts.contains("spider") { store.seedSpiderDemo() }
                #endif
            }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        store.setAvatar(img)
                        Haptics.play(.pop)
                    }
                    photo = nil
                }
            }
        }
    }

    /// Four numbers at a glance (2026-11-13): streak, this week's minutes, this week's running, film reviews.
    private var numbers: some View {
        let lab = Lab.shared
        let weekStart = dateOf("Mon")
        let km = lab.runs.filter { $0.date >= weekStart }.reduce(0) { $0 + $1.km }
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                numberTile("\(store.air.days)", "Day streak", "flame.fill", C.gold)
                numberTile("\(store.minutesThisWeek)", "Minutes this week", "clock.fill", C.brandHi)
            }
            HStack(spacing: 10) {
                numberTile(String(format: "%.1f", km), "Km run this week", "figure.run", labSkillColor("Runs"))
                numberTile("\(lab.reviews.count)", "Film reviews", "video.fill", labSkillColor("Defending"))
            }
        }
    }

    private func numberTile(_ value: String, _ label: String, _ icon: String, _ tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 16, weight: .bold)).foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.16)))
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.system(size: 21, weight: .bold)).foregroundStyle(C.creme)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(label).font(F.round(12, .semibold)).foregroundStyle(C.muted).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [tint.opacity(0.10), C.char800], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(C.line, lineWidth: 1))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }

    private var fullName: String {
        let a = store.answers
        let l = a.last.trimmingCharacters(in: .whitespaces)
        return l.isEmpty ? a.firstName : "\(a.firstName) \(l)"
    }

    private var identity: some View {
        VStack(spacing: 10) {
            PhotosPicker(selection: $photo, matching: .images) {
                Avatar(size: 92)
                    .overlay(alignment: .bottomLeading) {
                        if let t = ShownTeam.row(shownTeam) {
                            TeamCrest(name: t.name, logo: t.logo, color: t.color, size: 46).offset(x: -4, y: 2)
                        }
                    }
            }
                .buttonStyle(.press(.stud))
                .contextMenu {
                    if store.avatar != nil { Button("Remove photo", role: .destructive) { store.setAvatar(nil) } }
                }
                .accessibilityLabel(store.avatar == nil ? "Add a profile photo" : "Change your profile photo")
            Button {
                first = store.answers.first
                last = store.answers.last
                editName = true
            } label: {
                HStack(spacing: 8) {
                    Text(fullName).font(.system(size: 24, weight: .bold)).foregroundStyle(C.creme)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Image(systemName: "pencil").font(.system(size: 15, weight: .heavy)).foregroundStyle(C.muted)
                }
            }
            .buttonStyle(.press(.stud))
            .accessibilityLabel("\(fullName). Edit name")
            Text("\(store.answers.positionName) · \(store.answers.foot ?? "Right") foot")
                .font(F.round(15, .semibold)).foregroundStyle(C.muted)
            TeamChip { showTeams = true }
                .padding(.top, 4)
            // TEAM used to be a tab; it opens from here now (chat, leaderboard, invites, the code box)
            Button { Nav.shared.team = true } label: { Label("My team", systemImage: "person.3.fill") }
                .buttonStyle(.game(.charcoal, height: 46, font: 19))
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }

    /// The spider graph (2026-10-27, replaced the FC card + its six stat tiles): onboarding stats grown by training.
    private var cardSection: some View {
        VStack(spacing: 22) {
            SpiderCard()   // GiftCard (GIVE A FRIEND 7 DAYS FREE) removed from Profile 2026-11-08
        }
    }
}

/// GIVE A FRIEND 7 DAYS FREE (2026-10-29, replaced SHARE MY STATS). The user: "add on the profile a share for a free
/// 7 day trial no card so that they can share it with any friends and their soccer buddies can try it out." Shares
/// soccermax.app/join/<your gift code> as a picture card; a friend's account gets ONE free week ever (server
/// `redeem_gift`, notes/19). Needs the Apple sign-in (the code belongs to the account) ? asked for right here.
struct GiftCard: View {
    @Environment(AppStore.self) private var store
    @State private var team = Team.shared
    @State private var signing = false

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "gift.fill").font(.system(size: 26, weight: .bold)).foregroundStyle(C.brandInk)
                    .frame(width: 58, height: 58)
                    .background(Circle().fill(C.brand).overlay(Circle().stroke(C.line, lineWidth: 1)))
                VStack(alignment: .leading, spacing: 3) {
                    Disp("GIVE A FRIEND 7 DAYS FREE", size: 21).lineLimit(2).minimumScaleFactor(0.8)
                    Text("No card. For your soccer buddies.").font(F.round(14, .semibold)).foregroundStyle(C.muted)
                }
                Spacer(minLength: 0)
            }
            if team.signedIn {
                LinkShareButton { await ShareCards.gift(store) } label: { Label("SEND A FREE WEEK", systemImage: "paperplane.fill") }
                    .buttonStyle(.game(.brand))
            } else {
                Button { signing = true } label: { Label("SEND A FREE WEEK", systemImage: "paperplane.fill") }
                    .buttonStyle(.game(.brand))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous).fill(LinearGradient(colors: [C.char800, C.char850], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(C.line, lineWidth: 1))
        )
        .stitched(24)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(C.charInk).offset(y: 5))
        .sheet(isPresented: $signing) {
            VStack(spacing: 14) {
                Disp("ONE TAP FIRST", size: 30).padding(.top, 28)
                Text("Your free-week code belongs to your account.").font(F.round(15, .semibold)).foregroundStyle(C.muted)
                    .multilineTextAlignment(.center)
                Spacer()
                AppleSignIn()
                if let e = team.error { Text(e).font(F.round(14, .semibold)).foregroundStyle(C.gold) }
            }
            .padding(.horizontal, 20).padding(.bottom, 12)
            .presentationDetents([.height(300)])
            .presentationBackground(C.char900)
        }
        .onChange(of: team.signedIn) { _, on in
            guard on, signing else { return }
            signing = false
            Task { try? await Task.sleep(for: .milliseconds(500)); ShareLinks.present(await ShareCards.gift(store)) }
        }
    }
}

/// The profile photo, or the player's initials on grass. A camera badge says "tap to change".
struct Avatar: View {
    @Environment(AppStore.self) private var store
    var size: CGFloat = 118

    var body: some View {
        let a = store.answers
        let initials = [a.first, a.last].compactMap { $0.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } }.joined()
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                if let img = store.avatar {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    C.char800
                    Text(initials.isEmpty ? "P" : initials).font(.system(size: size * 0.36, weight: .semibold)).foregroundStyle(C.creme)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(C.brand.opacity(0.7), lineWidth: 1.5))
            .shadow(color: C.brand.opacity(0.35), radius: 12)

            Image(systemName: "camera.fill")
                .font(.system(size: size * 0.11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size * 0.28, height: size * 0.28)
                .background(Circle().fill(C.brand))
                .overlay(Circle().stroke(Color.black, lineWidth: 2))
                .offset(x: 2, y: 2)
        }
    }
}

/// 2026-10-28: "remove the 'pick your club' and instead add a 'display your team' button on profile where users can
/// choose to display a team with the profile pic". The chosen team's crest sits on the photo; its name is under yours.
/// Stored on this phone only (`sm.profile.team`). A team you leave stops showing by itself.
enum ShownTeam {
    static let key = "sm.profile.team"
    @MainActor static func row(_ id: String) -> TeamRow? { id.isEmpty ? nil : Team.shared.team(id) }
}

/// The shown team under your name ? or a dashed "display your team" chip.
struct TeamChip: View {
    @AppStorage(ShownTeam.key) private var shown = ""
    let action: () -> Void

    var body: some View {
        let t = ShownTeam.row(shown)
        Button(action: action) {
            HStack(spacing: 10) {
                if let t {
                    TeamCrest(name: t.name, logo: t.logo, color: t.color, size: 30)
                    Text(t.name).font(F.round(16, .bold)).foregroundStyle(C.creme)
                } else {
                    Image(systemName: "shield.lefthalf.filled").font(.system(size: 14, weight: .semibold)).foregroundStyle(C.brandHi)
                    Text("Show a team on your profile").font(F.round(14, .semibold)).foregroundStyle(C.brandHi)
                }
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .heavy)).foregroundStyle(C.muted)
            }
            .lineLimit(1)
            .padding(.leading, 14).padding(.trailing, 16)
            .frame(height: 40)
            .background(Capsule().fill(C.char800))
            .overlay(Capsule().strokeBorder(C.line, lineWidth: 1))
        }
        .buttonStyle(.press(.stud))
        .accessibilityLabel(t.map { "Showing \($0.name) on your profile. Change" } ?? "Display your team")
    }
}

/// Pick which of your teams shows with your photo (or none).
struct TeamDisplayPicker: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ShownTeam.key) private var shown = ""
    private var team: Team { Team.shared }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if team.teams.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "person.3.fill").font(.system(size: 34, weight: .bold)).foregroundStyle(C.brand)
                            Text("You\u{2019}re not on a team yet.").font(F.round(18, .semibold)).foregroundStyle(C.creme)
                            Button("MAKE OR JOIN A TEAM") {
                                dismiss()
                                Nav.shared.team = true
                            }
                            .buttonStyle(.game(.brand))
                        }
                        .frame(maxWidth: .infinity)
                        .gameCard(padding: 22)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(team.ordered.enumerated()), id: \.element.id) { i, t in
                                if i > 0 { Divider().overlay(C.charInk) }
                                row(selected: shown == t.id, action: { pick(t.id) }) {
                                    TeamCrest(name: t.name, logo: t.logo, color: t.color, size: 44)
                                    Text(t.name).font(F.round(17, .semibold)).foregroundStyle(C.creme).lineLimit(1)
                                }
                            }
                            Divider().overlay(C.charInk)
                            row(selected: ShownTeam.row(shown) == nil, action: { pick("") }) {
                                Image(systemName: "nosign").font(.system(size: 20, weight: .bold)).foregroundStyle(C.muted)
                                    .frame(width: 44, height: 44)
                                Text("Don\u{2019}t show a team").font(F.round(17, .semibold)).foregroundStyle(C.muted)
                            }
                        }
                        .gameCard(padding: 6, radius: 20)
                    }
                }
                .padding(16)
            }
            .page()
            .screenTitle("DISPLAY YOUR TEAM")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func pick(_ id: String) {
        shown = id
        Haptics.play(.latch)
        dismiss()
    }

    private func row<L: View>(selected: Bool, action: @escaping () -> Void, @ViewBuilder label: () -> L) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                label()
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 22, weight: .bold)).foregroundStyle(C.brand)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.press(.stud))
    }
}
