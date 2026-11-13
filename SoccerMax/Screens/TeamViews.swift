// TEAM tab (notes/26, 2026-10-25): your friends in one place. No team yet ? MAKE A TEAM or JOIN WITH A CODE.
// On a team: the crest + name + INVITE, two small boards (STREAK · THIS WEEK), then the FEED ? activity (sessions
// finished, film watched) and chat in one stream, newest at the bottom, with shared sessions + film as cards you can
// open. Text only (rule: nothing heavy on the server).
import AuthenticationServices
import PhotosUI
import SwiftUI

struct TeamTab: View {
    @Environment(AppStore.self) private var store
    @State private var team = Team.shared
    /// The open chat (Messages-style push). Kept apart from `team.selectedId` so going back never empties the chat
    /// mid-slide: the selection is cleared only once the pop animation is over (the 2026-10-28 back-button crash).
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if !team.teams.isEmpty {
                    TeamList()
                } else if team.loaded {
                    TeamStart()
                } else {
                    ProgressView().tint(C.brand).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .tabRoot("Teams")
            .pageGlow()
            .page()
            // tap a team ? its chat, with a back arrow to the list (like Messages)
            .navigationDestination(for: String.self) { id in TeamHome(id: id).page() }
        }
        // the list (or making / joining a team) picks a team ? push it; leaving or losing it ? back to the list
        .onChange(of: team.selectedId) { _, id in sync(id) }
        .onAppear { sync(team.selectedId) }
        .onChange(of: path) { _, p in
            guard p.isEmpty, team.selectedId != nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { if path.isEmpty { team.selectedId = nil } }
        }
        .task { await team.refresh(store) }
        .onAppear { team.startPolling(store) }
        .onDisappear { team.stopPolling() }
    }

    private func sync(_ id: String?) {
        if let id { if path != [id] { path = [id] } } else if !path.isEmpty { path = [] }
    }
}

// MARK: - the team list (MANY TEAMS, 2026-10-27)

/// Every team you're on, like Messages: one clean card per team ? crest, name + time, the last message, then who's
/// on it (faces + count) and the team streak. Newest on top; unread teams get a green edge + count. + adds a team.
/// (v2 2026-10-28: "more professional and seamless" ? no flame badge on the crest, no boxed list.)
struct TeamList: View {
    @Environment(AppStore.self) private var store
    @State private var team = Team.shared
    @State private var adding = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                TabHeader(title: "TEAMS") {
                    Button { adding = true } label: { Image(systemName: "plus").font(.system(size: 18, weight: .heavy)) }
                        .buttonStyle(.gameRound(.brand, size: 44))
                        .accessibilityLabel("Add a team")
                }
                .padding(.bottom, 14)
                LazyVStack(spacing: 12) {
                    ForEach(team.ordered) { t in
                        Button { Haptics.play(.press); team.selectedId = t.id } label: { TeamListRow(row: t) }
                            .buttonStyle(.press)
                            // share OUTSIDE the app from the card itself (2026-10-29): the invite link + picture card
                            .overlay(alignment: .bottomTrailing) {
                                LinkShareButton { await ShareCards.invite(t) } label: {
                                    Image(systemName: "square.and.arrow.up").font(.system(size: 15, weight: .heavy)).foregroundStyle(C.creme)
                                        .frame(width: 36, height: 36)
                                        .background(Circle().fill(C.char700))
                                }
                                .frame(width: 48, height: 48).contentShape(Rectangle())
                                .padding(.trailing, 6).padding(.bottom, 4)
                                .accessibilityLabel("Share \(t.name) invite link")
                            }
                            .contextMenu {
                                Button("Share invite link", systemImage: "paperplane") { Task { ShareLinks.present(await ShareCards.invite(t)) } }
                                Button("Copy invite code", systemImage: "doc.on.doc") { UIPasteboard.general.string = t.code }
                            }
                    }
                }
                Button { adding = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 17, weight: .bold))
                        Text("Join or make another team").font(F.round(15, .bold))
                    }
                    .foregroundStyle(C.muted)
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(C.char700, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.press)
                .padding(.top, 12)
                // contacts + local teams (2026-11-08, Screens/LocalTeamViews.swift)
                VStack(spacing: 12) {
                    FriendsRow()
                    NearbyTeamsSection()
                }
                .padding(.top, 22)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .refreshable { await team.refresh(store); await LocalTeams.shared.refreshMine(); await LocalTeams.shared.findNearby() }
        .task { await LocalTeams.shared.refreshMine() }
        .sheet(isPresented: $adding) { AddTeamSheet() }
    }
}

/// One team card: crest · name + time · last message + unread count · faces, player count, team streak.
private struct TeamListRow: View {
    let row: TeamRow
    @Environment(AppStore.self) private var store
    @State private var team = Team.shared

    var body: some View {
        let last = team.lastPost(row.id)
        let unread = team.unread(row.id)
        let s = team.streak(store, team: row.id)
        let members = team.members(of: row.id)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                TeamCrest(name: row.name, logo: row.logo, color: row.color, size: 54)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(row.name).font(F.round(18, .bold)).foregroundStyle(C.creme).lineLimit(1)
                        Spacer(minLength: 4)
                        if let last {
                            Text(Self.when(last.date)).font(F.round(13, unread > 0 ? .bold : .medium))
                                .foregroundStyle(unread > 0 ? C.brand : C.muted)
                        }
                    }
                    HStack(alignment: .center, spacing: 8) {
                        Text(last.map(preview) ?? "No messages yet — say hi")
                            .font(F.round(15, unread > 0 ? .semibold : .regular))
                            .foregroundStyle(unread > 0 ? C.creme2 : C.muted)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if unread > 0 {
                            Text("\(min(unread, 99))").font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(C.brandInk)
                                .padding(.horizontal, 7).frame(minWidth: 22, minHeight: 22)
                                .background(Capsule().fill(C.brand))
                                .accessibilityLabel("\(unread) new")
                        }
                    }
                }
            }
            Rectangle().fill(C.char700.opacity(0.7)).frame(height: 1)
            HStack(spacing: 10) {
                Faces(members: Array(members.prefix(4)))
                Text("\(members.count) player\(members.count == 1 ? "" : "s")")
                    .font(F.round(13, .semibold)).foregroundStyle(C.muted)
                Spacer(minLength: 4)
                if s.alive {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill").font(.system(size: 12, weight: .heavy))
                        Text("\(s.days) day\(s.days == 1 ? "" : "s")").font(F.round(13, .bold))
                    }
                    .foregroundStyle(Color(hex: 0xFF8A1E))
                    .accessibilityLabel("Team streak \(s.days) days")
                }
                Color.clear.frame(width: 36, height: 30)     // the share button sits here (TeamList overlay)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [C.char800, C.char850], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(unread > 0 ? C.brand.opacity(0.75) : C.char700, lineWidth: unread > 0 ? 1.5 : 1))
        )
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// Up to four teammates' faces, overlapping.
    private struct Faces: View {
        let members: [MemberRow]
        var body: some View {
            HStack(spacing: -8) {
                ForEach(members) { m in
                    PlayerPic(id: m.id, name: m.name, size: 24)
                        .overlay(Circle().stroke(C.char800, lineWidth: 2))
                }
            }
            .accessibilityHidden(true)
        }
    }

    /// The last thing said or done, in a few words ? like a message preview.
    private func preview(_ p: Post) -> String {
        let mine = p.user_id == team.me
        let who = mine ? "You" : (team.member(p.user_id)?.name.split(separator: " ").first.map(String.init) ?? "A teammate")
        switch p.kind {
        case "chat": return "\(who): \(p.body ?? "")"
        case "session": return "\(who) finished \(p.meta?.title ?? "a session")"
        case "film": return "\(who) watched \(p.meta?.title ?? "a film")"
        case "share_session", "share_film": return "\(who) shared \(p.meta?.title ?? "something")" + (p.body.map { ": \($0)" } ?? "")
        case "join": return "\(who) joined the team"
        case "create": return "\(who) made the team"
        default: return ""
        }
    }

    /// 4:12 PM today, Yesterday, a weekday this week, else 10/21.
    static func when(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return d.formatted(date: .omitted, time: .shortened) }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        if let w = cal.dateComponents([.day], from: d, to: Date()).day, w < 7 { return d.formatted(.dateTime.weekday(.wide)) }
        return d.formatted(.dateTime.month(.defaultDigits).day())
    }
}

/// + on the team list: join another team with a code, or make a new one (the same card as the first-team page).
struct AddTeamSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var team = Team.shared
    var body: some View {
        TeamStart(adding: true)
            .presentationDetents([.large])
            .presentationBackground(C.char900)
            .onChange(of: team.teams.count) { a, b in if b > a { dismiss() } }
    }
}

// MARK: - no team yet

/// The page before a team (2026-10-25 v2): ONE drawn hero ? a pitch with your friends on it, a chat bubble and the
/// leader's crown ? then three short perks (signed out) or the code boxes + MAKE A TEAM (signed in).
struct TeamStart: View {
    @Environment(AppStore.self) private var store
    @State private var team = Team.shared
    @State private var making = false
    @State private var code = ""
    @State private var preview: Team.Preview?
    @State private var checking = false
    @State private var busy = false
    @State private var trialToast = false
    /// Opened from + on the team list: just the code card + MAKE A TEAM (no mascot, no sign-in).
    var adding = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if adding {
                    Disp("ADD A TEAM", size: 30).padding(.top, 26)
                    Text("Join with a friend's code, or make a new one.").font(F.round(15, .semibold)).foregroundStyle(C.muted)
                        .multilineTextAlignment(.center).padding(.top, 4)
                } else {
                TabHeader("Team").frame(maxWidth: .infinity, alignment: .leading)
                // a plain header (2026-11-13): the talking mascot is gone from this page
                Image(systemName: "person.3.fill").font(.system(size: 32, weight: .bold)).foregroundStyle(C.brandHi)
                    .frame(width: 88, height: 88)
                    .background(Circle().fill(C.brand.opacity(0.18)))
                    .overlay(Circle().stroke(C.brand.opacity(0.5), lineWidth: 1))
                    .shadow(color: C.brand.opacity(0.35), radius: 14)
                    .padding(.top, 18)
                    .accessibilityHidden(true)
                Text("Train with your friends").font(.system(size: 26, weight: .bold)).foregroundStyle(C.creme)
                    .multilineTextAlignment(.center).padding(.top, 16)
                Text(team.signedIn ? "No team yet. Make one, or type a friend's code."
                     : "Make a team, chat, and see who trains the most each week. Sign in to start.")
                    .font(F.round(15, .medium)).foregroundStyle(C.muted)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6).padding(.horizontal, 12)
                }

                if !team.signedIn {
                    VStack(spacing: 10) {
                        PerkRow(icon: "bubble.left.and.bubble.right.fill", title: "Team chat", text: "", tint: C.brand)
                        PerkRow(icon: "trophy.fill", title: "Weekly leaderboard", text: "", tint: C.gold)
                        PerkRow(icon: "location.fill", title: "Teams near you", text: "", tint: C.brandHi)
                    }
                    .padding(.top, 20)
                    if let e = team.error { Text(e).font(F.round(14, .semibold)).foregroundStyle(C.gold).padding(.top, 14) }
                } else {
                    joinCard.padding(.top, 22)
                    OrRule().padding(.vertical, 16)
                    Button { making = true } label: { Label("MAKE A TEAM", systemImage: "plus") }
                        .buttonStyle(.gameLarge)
                    if let e = team.error { Text(e).font(F.round(14, .semibold)).foregroundStyle(C.gold).padding(.top, 12) }
                    // teams near you + friends from contacts (2026-11-08, Screens/LocalTeamViews.swift)
                    VStack(spacing: 12) {
                        NearbyTeamsSection()
                        if !adding { FriendsRow() }
                    }
                    .padding(.top, 24)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .dock {
            if !team.signedIn {
                VStack(spacing: 8) {
                    AppleSignIn()
                }
            }
        }
        .onAppear {
            if let c = team.pendingCode { code = c; look(c) }
            if DebugRoute.parts.contains("code") { code = "482" }   // DEBUG `-route team:in:code`
        }
        .sheet(isPresented: $making) { MakeTeamSheet() }
        .alert("7 DAYS FREE", isPresented: $trialToast) { Button("LET'S GO") {} } message: {
            Text(preview?.isGift == true || code.isEmpty ? "Your free week has started. No card needed." : "You're on the team — and your free week has started. No card needed.")
        }
    }

    /// GOT A CODE? ? six boxes, then the team it opens and one JOIN button.
    private var joinCard: some View {
        VStack(spacing: 14) {
            CodeEntry(code: $code, keypad: preview == nil)
                .onChange(of: code) { _, v in
                    let c = Team.clean(v)
                    if c != v { code = c; return }
                    look(c)
                }
            if let p = preview, p.isCreator {
                CreatorRow(name: p.name)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(C.char950))
                Button(busy ? "ONE SEC…" : "USE CODE") { useCreator() }
                    .buttonStyle(.gameLarge(.brand, feel: .kick))
                    .disabled(busy)
            } else if let p = preview, p.isGift {
                GiftRow(from: p.name)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(C.char950))
                Button(busy ? "…" : "GET 7 DAYS FREE") { join() }
                    .buttonStyle(.gameLarge(.brand, feel: .kick))
                    .disabled(busy)
            } else if let p = preview {
                HStack(spacing: 12) {
                    TeamCrest(name: p.name, logo: p.logo, color: p.color, size: 46)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).font(F.round(18, .bold)).foregroundStyle(C.creme).lineLimit(1)
                        HStack(spacing: 8) {
                            HStack(spacing: -6) {
                                ForEach(0..<min(p.members, 5), id: \.self) { i in MemberDot(name: " ", seed: i * 3 + 1, size: 18) }
                            }
                            Text("\(p.members) player\(p.members == 1 ? "" : "s")").font(F.round(13, .semibold)).foregroundStyle(C.muted)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(C.char950))
                .transition(.scale(scale: 0.9).combined(with: .opacity))
                Button(busy ? "JOINING…" : "JOIN \(p.name.uppercased())") { join() }
                    .buttonStyle(.gameLarge(.brand, feel: .kick))
                    .disabled(busy)
                    .transition(.opacity)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous).fill(LinearGradient(colors: [C.char800, C.char850], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(preview != nil ? C.brand : C.charInk, lineWidth: 2.5))
        )
        .stitched(24)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(C.charInk).offset(y: 5))
        .animation(.snappy, value: preview?.name)
    }

    private func look(_ c: String) {
        preview = nil
        guard c.count == 6 else { checking = false; return }
        checking = true
        Task {
            let p = await team.preview(code: c)
            if c == code { preview = p; checking = false; if p != nil { Haptics.play(.latch) } }
        }
    }

    /// A creator's code: nothing to join, the account is tied to them and the box clears.
    private func useCreator() {
        busy = true
        Task {
            let ok = await team.claimCreator(code: code)
            busy = false
            if ok { Haptics.play(.goal); code = ""; preview = nil }
        }
    }

    private func join() {
        busy = true
        Task {
            let gift = preview?.isGift == true
            let granted = gift ? await team.redeemGift(code: code, store: store) : await team.join(code: code, store: store)
            busy = false
            if granted != nil { Haptics.play(.goal) }
            if granted == true { trialToast = true }
            if gift, granted == false { team.error = "This account already had its free week." }
            if gift, granted != nil { code = ""; preview = nil }
        }
    }
}

/// A thin "OR" between the two ways in.
private struct OrRule: View {
    var body: some View {
        HStack(spacing: 12) {
            Capsule().fill(C.char700).frame(height: 2)
            Text("OR").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundStyle(C.muted)
            Capsule().fill(C.char700).frame(height: 2)
        }
    }
}

/// One perk on the sign-in page: an icon on a ball panel, a word, a line.
private struct PerkRow: View {
    let icon: String
    let title: String
    let text: String
    let tint: Color
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 19, weight: .heavy)).foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(PanelShape(sides: 6).fill(C.char950).overlay(PanelShape(sides: 6).stroke(tint.opacity(0.5), lineWidth: 2)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(F.display(18)).foregroundStyle(C.creme)
            }
            Spacer(minLength: 0)
        }
        .gameCard(padding: 10, radius: 20)
    }
}

/// The hero: a mowed pitch with five friends on it, the ball on the spot, a chat bubble and the leader's crown.
private struct TeamPitchHero: View {
    @State private var bob = false
    private let spots: [(x: CGFloat, y: CGFloat, n: String, seed: Int)] = [
        (0.20, 0.34, "M", 0), (0.80, 0.30, "J", 1), (0.50, 0.80, "S", 4), (0.16, 0.76, "A", 2), (0.84, 0.74, "L", 3)]

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                shape.fill(LinearGradient(colors: [Color(hex: 0x4D9BFF), C.brand, C.brandMid], startPoint: .top, endPoint: .bottom))
                MowedStripes(band: 30).clipShape(shape)
                PitchChalk().clipShape(shape)
                RadialGradient(colors: [.white.opacity(0.18), .clear], center: .center, startRadius: 4, endRadius: w * 0.4)
                BallGlyph(size: 40).shadow(color: C.brandInk.opacity(0.6), radius: 0, y: 3).position(x: w / 2, y: h * 0.53)

                ForEach(spots.indices, id: \.self) { i in
                    let s = spots[i]
                    MemberDot(name: s.n, seed: s.seed, size: 50)
                        .background(Ellipse().fill(C.brandInk.opacity(0.35)).frame(width: 44, height: 12).offset(y: 30))
                        .overlay(alignment: .top) {
                            if i == 1 {
                                Image(systemName: "crown.fill").font(.system(size: 20, weight: .heavy)).foregroundStyle(C.gold)
                                    .shadow(color: C.charInk, radius: 0, y: 2).offset(y: -22)
                            }
                        }
                        .offset(y: bob ? -3 : 3)
                        .animation(.easeInOut(duration: 1.5).repeatForever().delay(Double(i) * 0.25), value: bob)
                        .position(x: w * s.x, y: h * s.y)
                }

                // the chat bubble from M
                HStack(spacing: 6) {
                    Text("who's training today?").font(F.round(14, .bold)).foregroundStyle(C.creme)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(BubbleTail().fill(C.char800).overlay(BubbleTail().stroke(C.charInk, lineWidth: 2)))
                .position(x: w * 0.20 + 62, y: h * 0.34 - 46)

                // the leader's line, under J
                HStack(spacing: 5) {
                    Image(systemName: "flame.fill").font(.system(size: 11, weight: .heavy))
                    Text("#1  14 DAYS").font(.system(size: 11, weight: .heavy, design: .monospaced))
                }
                .foregroundStyle(C.goldInk)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(Capsule().fill(C.gold).overlay(Capsule().stroke(C.charInk, lineWidth: 2)))
                .position(x: w * 0.80, y: h * 0.30 + 42)

                shape.inset(by: 3).stroke(.white.opacity(0.3), lineWidth: 2)
                    .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center))
                shape.stroke(C.brandInk, lineWidth: 2.5)
            }
        }
        .frame(height: 230)
        .background(shape.fill(C.brandLip).overlay(shape.stroke(C.line, lineWidth: 1)).offset(y: 6))
        .padding(.bottom, 6)
        .onAppear { bob = true }
        .accessibilityHidden(true)
    }
}

/// Halfway line, centre circle and the two box edges ? enough for the card to read as a pitch.
private struct PitchChalk: View {
    var body: some View {
        Canvas { ctx, s in
            let c = GraphicsContext.Shading.color(.white.opacity(0.32))
            var p = Path()
            p.move(to: CGPoint(x: -4, y: s.height * 0.53)); p.addLine(to: CGPoint(x: s.width + 4, y: s.height * 0.53))
            let r = s.height * 0.2
            p.addEllipse(in: CGRect(x: s.width / 2 - r, y: s.height * 0.53 - r, width: r * 2, height: r * 2))
            p.addRect(CGRect(x: s.width * 0.28, y: -4, width: s.width * 0.44, height: s.height * 0.13))
            p.addRect(CGRect(x: s.width * 0.28, y: s.height * 0.92, width: s.width * 0.44, height: s.height * 0.12))
            ctx.stroke(p, with: c, lineWidth: 2)
        }
        .allowsHitTesting(false)
    }
}

/// A speech bubble with a little tail at the lower left.
private struct BubbleTail: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(roundedRect: r, cornerRadius: min(16, r.height / 2), style: .continuous)
        p.move(to: CGPoint(x: r.minX + 14, y: r.maxY - 1))
        p.addLine(to: CGPoint(x: r.minX + 6, y: r.maxY + 9))
        p.addLine(to: CGPoint(x: r.minX + 26, y: r.maxY - 1))
        return p
    }
}

struct MakeTeamSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var team = Team.shared
    @State private var name = ""
    @State private var color = 0
    @State private var pick: PhotosPickerItem?
    @State private var logo: UIImage?
    @State private var busy = false
    /// Show the team to players nearby (2026-11-08) ? creator only, set here or later in Edit team.
    @State private var local = false
    @State private var place = ""
    var editing = false

    var body: some View {
        VStack(spacing: 18) {
            Disp(editing ? "EDIT TEAM" : "MAKE A TEAM", size: 30).padding(.top, 24)
            PhotosPicker(selection: $pick, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    TeamCrest(name: name.isEmpty ? "?" : name, image: logo, color: color, size: 110)
                    Image(systemName: "camera.fill").font(.system(size: 15, weight: .heavy)).foregroundStyle(C.brandInk)
                        .frame(width: 36, height: 36).background(Circle().fill(C.brand).overlay(Circle().stroke(C.charInk, lineWidth: 2)))
                }
            }
            .accessibilityLabel("Pick a team logo")
            Text(logo == nil ? "Tap to add a logo — or keep the crest" : "Tap to change").font(F.round(13)).foregroundStyle(C.muted)
            if logo == nil {
                HStack(spacing: 10) {
                    ForEach(Team.colors.indices, id: \.self) { i in
                        Button { color = i; Haptics.play(.press) } label: {
                            Circle().fill(Color(hex: Team.colors[i])).frame(width: 30, height: 30)
                                .overlay(Circle().stroke(color == i ? C.creme : C.charInk, lineWidth: color == i ? 3 : 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            TextField("", text: $name, prompt: Text("Team name").foregroundStyle(C.muted))
                .font(F.round(20, .semibold)).foregroundStyle(C.creme)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16).frame(height: 56)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(C.char950)
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(C.charInk, lineWidth: 2)))
                .onChange(of: name) { _, v in if v.count > 30 { name = String(v.prefix(30)) } }
            if LocalTeams.shared.ready { TeamPlaceField(on: $local, place: $place) }   // once the server has local teams
            if let e = team.error, busy == false, !e.isEmpty {
                Text(e).font(F.round(14, .semibold)).foregroundStyle(C.gold)
            }
            Spacer()
            Button(editing ? "SAVE" : "CREATE TEAM") { go() }
                .buttonStyle(.gameLarge)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || busy)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .presentationDetents([.large])
        .presentationBackground(C.char900)
        .onAppear {
            if editing, let t = team.team {
                name = t.name; color = t.color; logo = Team.logoImage(t.logo)
                if let p = LocalTeams.shared.places[t.id] { local = true; place = p.place ?? "" }
            }
        }
        .onChange(of: pick) { _, p in
            Task { if let d = try? await p?.loadTransferable(type: Data.self), let img = UIImage(data: d) { logo = img } }
        }
    }

    /// On ? the town + current spot (rounded to ~1 km on the server); off ? hidden from nearby players.
    private func savePlace(_ id: String) async {
        let wasOn = LocalTeams.shared.places[id] != nil
        if local, let here = Locator.shared.coordinate {
            await LocalTeams.shared.setLocation(team: id, place: place.trimmingCharacters(in: .whitespaces), at: here)
        } else if !local, wasOn {
            await LocalTeams.shared.setLocation(team: id, place: nil, at: nil)
        }
    }

    private func go() {
        busy = true
        let n = name.trimmingCharacters(in: .whitespaces)
        Task {
            if editing {
                let oldLogo = Team.logoImage(team.team?.logo)
                await team.edit(name: n, logo: logo === oldLogo ? nil : .some(logo), color: color)
                if let id = team.team?.id { await savePlace(id) }
                busy = false
                dismiss()
            } else if await team.create(name: n, logo: logo, color: color, store: store) {
                if let id = team.selectedId, local { await savePlace(id) }
                Haptics.play(.goal)
                busy = false
                dismiss()
            } else { busy = false }
        }
    }
}

// MARK: - on a team

struct TeamHome: View {
    /// The team this chat is for. Its row is read live, with the last copy kept so the page never has nothing to show
    /// (it used to force-unwrap the open team and crashed when the back button cleared it mid-slide).
    let id: String
    @State private var shown: TeamRow?
    @Environment(AppStore.self) private var store
    @State private var team = Team.shared
    @State private var draft = ""
    @State private var inviting = false
    @State private var editing = false
    @State private var leaving = false
    @State private var requesting = false
    @State private var page = DebugRoute.parts.contains("board") ? "Leaderboard" : DebugRoute.parts.contains("streak") ? "Streak" : "Chat"
    @State private var opening: Post?
    @State private var film: Film?
    @State private var missingFilm = false
    @State private var viewing: MemberRow?
    @State private var reporting: Post?
    @State private var blocking: MemberRow?
    @State private var reported: Bool?
    @FocusState private var typing: Bool

    var body: some View {
        if let t = team.team(id) ?? shown {
            home(t).onAppear { shown = t }.onChange(of: team.team(id)) { _, r in if let r { shown = r } }
        } else {
            Color.clear
        }
    }

    @ViewBuilder private func home(_ t: TeamRow) -> some View {
        VStack(spacing: 0) {
            Segments(options: ["Chat", "Streak", "Leaderboard"], pick: $page.animation(.snappy))
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .onChange(of: page) { _, _ in typing = false }

            if page == "Streak" {
                TeamStreakPage(open: { viewing = $0 })
            } else if page == "Leaderboard" {
                LeaderboardPage(open: { viewing = $0 }, invite: { inviting = true })
            } else {
            // the feed
            ScrollViewReader { sc in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        RequestsBanner(team: t)   // the creator only: players asking to join (LocalTeamViews.swift)
                        if team.feed.isEmpty {
                            Text("Nothing yet. Finish a session or say hi — it all shows up here.")
                                .font(F.round(15)).foregroundStyle(C.muted).multilineTextAlignment(.center).padding(.top, 40)
                        }
                        ForEach(Array(team.feed.enumerated()), id: \.element.id) { i, p in
                            if i == 0 || !Calendar.current.isDate(p.date, inSameDayAs: team.feed[i - 1].date) {
                                DayStamp(date: p.date)
                            }
                            FeedRow(post: p, mine: p.user_id == team.me, who: team.member(p.user_id), open: { open(p) },
                                    profile: { id in viewing = team.member(id) })
                                .id(p.id)
                                .contextMenu {
                                    if p.user_id == team.me, ["chat", "share_session", "share_film"].contains(p.kind) {
                                        Button("Delete", systemImage: "trash", role: .destructive) { Task { await team.delete(p) } }
                                    }
                                    if let b = p.body { Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = b } }
                                    if p.user_id != team.me {
                                        Button("Report", systemImage: "exclamationmark.bubble") { reporting = p }
                                        if let m = team.member(p.user_id) {
                                            Button("Block \(m.name)", systemImage: "hand.raised", role: .destructive) { blocking = m }
                                        }
                                    }
                                }
                        }
                        Color.clear.frame(height: 4).id("end")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .clipped()
                .onChange(of: team.feed.last?.id) { _, _ in withAnimation { sc.scrollTo("end", anchor: .bottom) } }
                .onChange(of: typing) { _, on in if on { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { withAnimation { sc.scrollTo("end", anchor: .bottom) } } } }
            }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if page == "Chat" {
            VStack(spacing: 6) {
                if let e = team.error { Text(e).font(F.round(13, .semibold)).foregroundStyle(C.gold) }
                HStack(spacing: 10) {
                    TextField("", text: $draft, prompt: Text("Message your team").foregroundStyle(C.muted), axis: .vertical)
                        .lineLimit(1...4)
                        .font(FeedRow.chat).foregroundStyle(C.creme)
                        .focused($typing)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(C.char950)
                            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(C.charInk, lineWidth: 2)))
                        .onChange(of: draft) { _, v in if v.count > 500 { draft = String(v.prefix(500)) } }
                    Button { send() } label: { Image(systemName: "arrow.up").font(.system(size: 18, weight: .heavy)) }
                        .buttonStyle(.gameRound(.brand, size: 46))
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Send")
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)
            .background(C.char900.opacity(0.96).ignoresSafeArea())
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button { page = "Leaderboard" } label: {
                    HStack(spacing: 8) {
                        TeamCrest(name: t.name, logo: t.logo, color: t.color, size: 32)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(t.name).font(F.round(16, .bold)).foregroundStyle(C.creme).lineLimit(1)
                            Text("\(team.members.count) player\(team.members.count == 1 ? "" : "s")").font(F.round(11, .semibold)).foregroundStyle(C.muted)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(t.name), \(team.members.count) players")
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { inviting = true } label: { Image(systemName: "person.badge.plus") }
                    .accessibilityLabel("Invite")
                Menu {
                    Button("Invite friends", systemImage: "person.badge.plus") { inviting = true }
                    Button("Edit team", systemImage: "pencil") { editing = true }.disabled(t.owner != team.me)
                    if t.owner == team.me, LocalTeams.shared.ready {
                        Button("Join requests", systemImage: "person.crop.circle.badge.plus") { requesting = true }
                    }
                    Button("Leave team", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { leaving = true }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("Team options")
            }
        }
        .tint(C.creme)
        .sheet(isPresented: $inviting) { InviteSheet() }
        .sheet(isPresented: $editing) { MakeTeamSheet(editing: true) }
        .sheet(isPresented: $requesting) { RequestsSheet(team: t) }
        .sheet(item: $viewing) { PlayerSheet(member: $0) }
        .sheet(item: $opening) { SharedSessionSheet(meta: $0.meta) }
        .fullScreenCover(item: $film) { TapePlayer(tape: $0.tape, start: $0.start) }
        .alert("Film not on your phone yet", isPresented: $missingFilm) { Button("OK") {} } message: {
            Text("Open Matchday and pull down to get today's games, then try again.")
        }
        .safetyDialogs(reporting: $reporting, blocking: $blocking, reported: $reported)
        .confirmationDialog("Leave \(t.name)?", isPresented: $leaving, titleVisibility: .visible) {
            Button("Leave team", role: .destructive) { Task { await team.leave() } }
        } message: { Text(team.members.count <= 1 ? "You're the last player — the team and its feed will be deleted." : "You can join again with the code.") }
    }

    private func send() {
        let t = draft
        draft = ""
        Haptics.play(.kick)
        Task { await team.send(chat: t) }
    }

    private func open(_ p: Post) {
        switch p.kind {
        case "share_session", "session":
            if p.meta?.items?.isEmpty == false { opening = p }
        case "share_film", "film":
            if let id = p.ref.flatMap(Int.init), let tape = Matchday.shared.tape(id) { film = Film(tape: tape) } else { missingFilm = true }
        default: break
        }
    }
}

private struct DayStamp: View {
    let date: Date
    var body: some View {
        Text(Calendar.current.isDateInToday(date) ? "TODAY" : Calendar.current.isDateInYesterday(date) ? "YESTERDAY" : date.formatted(.dateTime.weekday(.wide).month().day()).uppercased())
            .font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundStyle(C.muted)
            .padding(.top, 8)
    }
}

/// One line of the feed: a chat bubble, an activity line, or a shared card.
struct FeedRow: View {
    let post: Post
    let mine: Bool
    let who: MemberRow?
    let open: () -> Void
    var profile: (String) -> Void = { _ in }

    private func pic(_ name: String) -> some View {
        Button { profile(post.user_id) } label: { PlayerPic(id: post.user_id, name: name, size: 30) }
            .buttonStyle(.press)
            .accessibilityLabel("\(name)'s profile")
    }

    var body: some View {
        let name = mine ? "You" : (who?.name ?? "A teammate")
        switch post.kind {
        case "chat":
            HStack(alignment: .bottom, spacing: 8) {
                if mine { Spacer(minLength: 50) } else { pic(name) }
                VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
                    if !mine { Button(name) { profile(post.user_id) }.font(F.round(12, .bold)).foregroundStyle(C.muted).buttonStyle(.plain) }
                    Text(post.body ?? "")
                        .font(Self.chat)
                        .foregroundStyle(mine ? C.brandInk : C.creme)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(mine ? C.brand : C.char800)
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(C.charInk, lineWidth: 2)))
                }
                if !mine { Spacer(minLength: 50) }
            }
        case "share_session", "share_film":
            HStack(alignment: .bottom, spacing: 8) {
                if mine { Spacer(minLength: 40) } else { pic(name) }
                VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                    Text(mine ? "You shared" : "\(name) shared").font(F.round(12, .bold)).foregroundStyle(C.muted)
                    Button(action: open) { SharedCard(post: post) }.buttonStyle(.press)
                    if let b = post.body, !b.isEmpty {
                        Text(b).font(Self.chat).foregroundStyle(mine ? C.brandInk : C.creme)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(mine ? C.brand : C.char800)
                                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(C.charInk, lineWidth: 2)))
                    }
                }
                if !mine { Spacer(minLength: 40) }
            }
        case "session" where post.meta?.area != nil || post.meta?.parts != nil:
            // a live session (2026-11-08 v2): who + total time, every category done, the photos/videos they added
            TeamSessionCard(post: post, name: name, profile: { profile(post.user_id) })
        default:
            // activity: one centred line, tappable when there's something to open
            Button(action: open) {
                HStack(spacing: 10) {
                    Button { profile(post.user_id) } label: {
                        PlayerPic(id: post.user_id, name: name, size: 30)
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: icon).font(.system(size: 8, weight: .heavy)).foregroundStyle(C.charInk)
                                    .frame(width: 15, height: 15).background(Circle().fill(tone).overlay(Circle().stroke(C.charInk, lineWidth: 1.5)))
                                    .offset(x: 4, y: 4)
                            }
                    }
                    .buttonStyle(.press)
                    (Text(name).font(F.round(15, .bold)).foregroundColor(C.creme) + Text(" " + line).font(F.round(15)).foregroundColor(C.creme2))
                        .lineLimit(2).multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    if let m = post.meta?.minutes, ["session", "film"].contains(post.kind) {
                        Text("\(m) MIN").font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundStyle(tone)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(C.char700, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            }
            .buttonStyle(.plain)
        }
    }

    /// Chat text: the rounded system face ? it has emoji, the brand font doesn't.
    static let chat = Font.system(size: 17, weight: .medium, design: .rounded)

    private var icon: String {
        switch post.kind { case "session": "figure.soccer"; case "film": "play.rectangle.fill"; case "join": "person.badge.plus"; default: "flag.fill" }
    }
    private var tone: Color { post.kind == "film" ? C.gold : C.brand }
    private var line: String {
        switch post.kind {
        case "session": return "finished \(post.meta?.title ?? "a session")"
        case "film": return "watched \(post.meta?.title ?? "a film")"
        case "join": return "joined the team"
        case "create": return "made the team"
        default: return ""
        }
    }
}

/// A shared session or film inside the feed.
private struct SharedCard: View {
    let post: Post
    var body: some View {
        let film = post.kind == "share_film"
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(film ? Color(hex: 0x0B0D0F) : C.brandLip)
                if film, let h = post.meta?.home, let a = post.meta?.away {
                    HStack(spacing: -6) { CrestImage(url: h, size: 26); CrestImage(url: a, size: 26) }
                } else {
                    Image(systemName: "figure.soccer").font(.system(size: 22, weight: .heavy)).foregroundStyle(C.brandHi)
                }
            }
            .frame(width: 58, height: 50)
            VStack(alignment: .leading, spacing: 2) {
                Text(post.meta?.title ?? (film ? "Film" : "Session")).font(F.round(16, .bold)).foregroundStyle(C.creme).lineLimit(2)
                Text(film ? [post.meta?.score, post.meta?.league].compactMap { $0 }.joined(separator: " · ")
                     : "\(post.meta?.drills ?? 0) drills · \(post.meta?.minutes ?? 0) min")
                    .font(F.round(13)).foregroundStyle(C.muted).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(film ? "WATCH" : "OPEN").font(F.display(14)).foregroundStyle(film ? C.gold : C.brand)
        }
        .padding(10)
        .frame(maxWidth: 290)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(C.char800)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(film ? C.gold.opacity(0.6) : C.brand.opacity(0.6), lineWidth: 2)))
    }
}

// MARK: - the team streak page

/// STREAK (its own page, 2026-10-27; user: "create a new section in the teams that's streak"). The team's fire only
/// stays lit while EVERY player trains 10 min every 3 days. Hero = the big 3D fire + the day count + who it's waiting
/// on; then THE RULE in one line; then everyone with a ring of their time left and a plain status.
struct TeamStreakPage: View {
    let open: (MemberRow) -> Void
    @Environment(AppStore.self) private var store
    @State private var team = Team.shared
    @State private var info = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { tl in
            let s = team.streak(store, now: tl.date)
            let waiting = s.waitingOn(tl.date)
            ScrollView {
                VStack(spacing: 0) {
                    // hero: the fire ? no card, no border (2026-11-08: same clean look as the Sessions tab)
                    VStack(spacing: 0) {
                        StreakFire(heat: s.alive ? max(0.75, s.air(tl.date)) : 0.3, size: 210)
                            .padding(.top, -10).padding(.bottom, -26)
                        Disp("\(s.days)", size: 76).shadow(color: C.charInk, radius: 0, y: 3)
                        HStack(spacing: 8) {
                            Disp("DAY TEAM STREAK", size: 20, color: C.creme2)
                            // how it works sits behind an info button, like the personal streak
                            Button { info = true } label: {
                                Image(systemName: "info.circle.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(C.muted)
                            }
                            .buttonStyle(.press(.stud))
                            .accessibilityLabel("How the team streak works")
                            .popover(isPresented: $info, arrowEdge: .bottom) {
                                TeamStreakInfo().presentationCompactAdaptation(.popover).presentationBackground(C.char850)
                            }
                        }
                        Text(line(s, waiting, tl.date)).font(F.round(15, .semibold))
                            .foregroundStyle(!waiting.isEmpty && s.alive ? C.gold : s.alive ? C.creme2 : C.muted)
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8).padding(.horizontal, 12)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)

                    // everyone: who's in, who it's waiting on
                    Text("EVERYONE").font(F.round(13, .heavy)).kerning(1.6).foregroundStyle(C.creme2)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 26)
                    VStack(spacing: 8) {
                        ForEach(team.members.sorted { (s.due[$0.id] ?? .distantFuture) < (s.due[$1.id] ?? .distantFuture) }) { m in
                            row(m, s, waiting.contains(m.id), tl.date)
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func row(_ m: MemberRow, _ s: TeamStreak, _ wait: Bool, _ now: Date) -> some View {
        let due = s.due[m.id]
        let left = due.map { max(0, min(1, $0.timeIntervalSince(now) / Double((AirStreak.window + 1) * 86_400))) } ?? 0
        let today = (m.id == team.me ? store.keptDays.contains { Calendar.current.isDateInToday($0) }
                     : KeptBits.decode(m.kept, end: m.kept_end).contains(dateKey(now)))
        let status: String = {
            guard s.alive, let due else { return today ? "Trained today" : "Hasn't trained yet" }
            if today { return "Trained today" }
            let h = Int(due.timeIntervalSince(now) / 3600)
            return h < 24 ? "Goes out in \(max(1, h)) h" : "\(h / 24) day\(h / 24 == 1 ? "" : "s") left"
        }()
        return Button { open(m) } label: {
            HStack(spacing: 12) {
                PlayerPic(id: m.id, name: m.name, size: 42)
                    .padding(4)
                    .overlay(Circle().stroke(C.char700, lineWidth: 3))
                    .overlay(Circle().trim(from: 0, to: s.alive ? left : 0).rotation(.degrees(-90))
                        .stroke(wait ? C.gold : C.brand, style: StrokeStyle(lineWidth: 3, lineCap: .round)))
                Text(m.id == team.me ? "You" : m.name).font(F.round(16, .bold)).foregroundStyle(m.id == team.me ? C.brand : C.creme).lineLimit(1)
                Spacer(minLength: 4)
                HStack(spacing: 5) {
                    if today { Image(systemName: "checkmark.circle.fill").font(.system(size: 13, weight: .heavy)) }
                    Text(status).font(F.round(13, .bold))
                }
                .foregroundStyle(today ? C.brand : wait ? C.gold : C.muted)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(wait ? C.gold.opacity(0.10) : C.char850))
        }
        .buttonStyle(.press)
        .accessibilityLabel("\(m.id == team.me ? "You" : m.name), \(status)")
    }

    private func line(_ s: TeamStreak, _ waiting: [String], _ now: Date) -> String {
        guard s.alive else { return "Train 10 min today to light it." }
        if waiting.isEmpty { return "Everyone's in. Keep it going." }
        let names = waiting.map { $0 == team.me ? "you" : (team.member($0)?.name.split(separator: " ").first.map(String.init) ?? "a teammate") }
        let h = max(1, Int((s.deadline?.timeIntervalSince(now) ?? 0) / 3600))
        let who = names.count == 1 ? names[0] : names.count == 2 ? "\(names[0]) and \(names[1])" : "\(names[0]) + \(names.count - 1) more"
        return "Goes out in \(h) h — waiting on \(who)."
    }
}

/// What the info button on the team streak opens (the old "rule" card, 2026-11-08).
struct TeamStreakInfo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Disp("TEAM STREAK", size: 22)
            row("person.3.fill", "Everyone on the team trains 10 minutes at least once every 3 days.")
            row("flame.fill", "Each day the whole team keeps it, the fire grows by one.")
            row("exclamationmark.triangle.fill", "One player misses 3 days and the fire goes out for everyone.")
            row("hourglass", "The ring around each player is the time they have left.")
        }
        .padding(20)
        .frame(width: 300, alignment: .leading)
    }
    private func row(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.system(size: 15, weight: .bold)).foregroundStyle(C.gold).frame(width: 20)
            Text(text).font(F.round(15, .semibold)).foregroundStyle(C.creme).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - the leaderboard page

/// LEADERBOARD (its own page, 2026-10-25 v2; 2026-11-08 = THIS WEEK'S MINUTES ONLY ? user: "so anyone can take the win"):
/// a podium for the top 3, where you stand, then everyone else. Starts again every Monday.
struct LeaderboardPage: View {
    let open: (MemberRow) -> Void
    let invite: () -> Void
    @State private var team = Team.shared

    var body: some View {
        let rows = team.byMinutes
        let value: (MemberRow) -> Int = { $0.minutesThisWeek }
        let unit: (Int) -> String = { _ in "MIN" }
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 4) {
                    Disp("THIS WEEK", size: 26)
                    Text(resetLine).font(F.round(14, .semibold)).foregroundStyle(C.muted)
                }
                .padding(.top, 16)

                Podium(rows: Array(rows.prefix(3)), me: team.me, value: value, unit: unit, open: open, invite: invite)
                    .padding(.top, 10)

                if let i = rows.firstIndex(where: { $0.id == team.me }) {
                    YourPlace(rank: i + 1, line: placeLine(i, rows, value))
                        .padding(.top, 16)
                }

                if rows.count > 3 {
                    VStack(spacing: 8) {
                        ForEach(Array(rows.enumerated()).dropFirst(3), id: \.element.id) { i, m in
                            Button { open(m) } label: {
                                HStack(spacing: 12) {
                                    Text("\(i + 1)").font(F.display(20)).foregroundStyle(C.muted).frame(width: 28)
                                    PlayerPic(id: m.id, name: m.name, size: 38)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(m.id == team.me ? "You" : m.name).font(F.round(16, .bold)).foregroundStyle(m.id == team.me ? C.brand : C.creme)
                                        if let p = m.position { Text(Library.shared.positions[p] ?? p).font(F.round(12)).foregroundStyle(C.muted) }
                                    }
                                    Spacer()
                                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                                        Text("\(value(m))").font(F.display(20)).foregroundStyle(C.creme)
                                        Text(unit(value(m))).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundStyle(C.muted)
                                    }
                                }
                                .gameCard(padding: 10, radius: 18, stroke: m.id == team.me ? C.brand : C.charInk)
                            }
                            .buttonStyle(.press)
                        }
                    }
                    .padding(.top, 14)
                }

                if rows.count < 3 {
                    Button(action: invite) {
                        HStack(spacing: 12) {
                            Image(systemName: "person.badge.plus").font(.system(size: 20, weight: .heavy)).foregroundStyle(C.brand)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("FILL THE PODIUM").font(F.display(17)).foregroundStyle(C.creme)
                                Text("Invite friends — they get 7 days free.").font(F.round(13)).foregroundStyle(C.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 14, weight: .heavy)).foregroundStyle(C.muted)
                        }
                        .gameCard(padding: 14, radius: 20)
                    }
                    .buttonStyle(.press)
                    .padding(.top, 14)
                }

                Text("Most minutes trained since Monday wins. Everyone starts at 0 every Monday.")
                    .font(F.round(13)).foregroundStyle(C.muted).multilineTextAlignment(.center)
                    .padding(.top, 18)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
    }

    /// One plain line on where you stand: how far to the next player up, or that you're on top.
    /// "New week in 3 days" ? the race is open to anyone, every week.
    private var resetLine: String {
        let next = addDays(Calendar.current.startOfDay(for: dateOf("Mon")), 7)
        let d = max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: next).day ?? 0)
        return d <= 1 ? "New week starts tomorrow" : "New week in \(d) days"
    }

    private func placeLine(_ i: Int, _ rows: [MemberRow], _ value: (MemberRow) -> Int) -> String {
        guard rows.count > 1 else { return "Invite a friend to race." }
        if i == 0 {
            let lead = value(rows[0]) - value(rows[1])
            return lead > 0 ? "Top of the team, \(lead) min clear." : "Top of the team — tied. Train to pull away."
        }
        let up = rows[i - 1]
        let gap = value(up) - value(rows[i]) + 1
        let who = up.name.hasSuffix(".") ? up.name : up.name + "."
        return "\(gap) more min to pass \(who)"
    }
}

/// The top three on pedestals: 2nd · 1st · 3rd. An empty spot asks for an invite.
private struct Podium: View {
    let rows: [MemberRow]
    let me: String?
    let value: (MemberRow) -> Int
    let unit: (Int) -> String
    let open: (MemberRow) -> Void
    let invite: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            spot(1); spot(0); spot(2)
        }
        .padding(.top, 26)
        .background(alignment: .top) {
            RadialGradient(colors: [C.gold.opacity(0.22), .clear], center: .center, startRadius: 4, endRadius: 150)
                .frame(height: 260).offset(y: -20)
                .allowsHitTesting(false)
        }
    }

    private static let medals: [(face: [Color], lip: Color, ink: Color)] = [
        ([C.goldHi, C.gold, C.goldMid], C.goldLip, C.goldInk),
        ([Color(hex: 0xF1F3F5), Color(hex: 0xC9CFD5), Color(hex: 0xA9B1B9)], Color(hex: 0x6F7882), Color(hex: 0x3A4148)),
        ([Color(hex: 0xF2B482), Color(hex: 0xD98B4E), Color(hex: 0xB86E35)], Color(hex: 0x7E4620), Color(hex: 0x4E2A10))]

    @ViewBuilder private func spot(_ i: Int) -> some View {
        let m = rows[safe: i]
        let medal = Self.medals[i]
        let pic: CGFloat = i == 0 ? 86 : 66
        let block: CGFloat = [128, 96, 74][i]
        VStack(spacing: 8) {
            if let m {
                Button { open(m) } label: {
                    VStack(spacing: 6) {
                        PlayerPic(id: m.id, name: m.name, size: pic)
                            .padding(4)
                            .background(Circle().fill(LinearGradient(colors: medal.face, startPoint: .top, endPoint: .bottom)))
                            .overlay(Circle().stroke(C.line, lineWidth: 1))
                            .overlay(alignment: .top) {
                                if i == 0 {
                                    Image(systemName: "crown.fill").font(.system(size: 26, weight: .heavy)).foregroundStyle(C.gold)
                                        .shadow(color: C.charInk, radius: 0, y: 2.5).offset(y: -26)
                                }
                            }
                        Text(m.id == me ? "You" : m.name).font(F.round(15, .bold)).foregroundStyle(m.id == me ? C.brand : C.creme).lineLimit(1)
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text("\(value(m))").font(F.display(i == 0 ? 26 : 21)).foregroundStyle(C.creme)
                            Text(unit(value(m))).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundStyle(C.muted)
                        }
                    }
                }
                .buttonStyle(.press)
            } else {
                Button(action: invite) {
                    VStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 22, weight: .heavy)).foregroundStyle(C.muted)
                            .frame(width: pic + 8, height: pic + 8)
                            .background(Circle().strokeBorder(C.char600, style: StrokeStyle(lineWidth: 2.5, dash: [6, 5])))
                        Text("Invite").font(F.round(15, .bold)).foregroundStyle(C.muted)
                        Text(" ").font(F.display(21))
                    }
                }
                .buttonStyle(.press)
            }
            Pedestal(rank: i + 1, height: block, face: m == nil ? [C.char700, C.char800] : medal.face, lip: m == nil ? C.charInk : medal.lip, ink: m == nil ? C.char600 : medal.ink)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct Pedestal: View {
    let rank: Int
    let height: CGFloat
    let face: [Color]
    let lip: Color
    let ink: Color
    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 6, bottomTrailingRadius: 6, topTrailingRadius: 16, style: .continuous)
        ZStack(alignment: .top) {
            shape.fill(LinearGradient(colors: face, startPoint: .top, endPoint: .bottom))
            MowedStripes(band: 14).clipShape(shape).opacity(0.7)
            shape.inset(by: 3).stroke(.white.opacity(0.35), lineWidth: 2)
                .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center))
            Text("\(rank)").font(F.display(rank == 1 ? 44 : 34)).foregroundStyle(.white)
                .shadow(color: ink, radius: 0, y: 3)
                .padding(.top, 10)
            shape.stroke(C.line, lineWidth: 1)
        }
        .frame(height: height)
        .background(shape.fill(lip).overlay(shape.stroke(C.line, lineWidth: 1)).offset(y: 5))
        .padding(.bottom, 5)
    }
}

/// Where you stand, in one line.
private struct YourPlace: View {
    let rank: Int
    let line: String
    var body: some View {
        HStack(spacing: 12) {
            Text("#\(rank)").font(F.display(28)).foregroundStyle(rank == 1 ? C.gold : C.brand)
                .shadow(color: C.charInk, radius: 0, y: 2)
                .frame(minWidth: 54)
            VStack(alignment: .leading, spacing: 2) {
                Text("YOU").font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundStyle(C.muted)
                Text(line).font(F.round(15, .semibold)).foregroundStyle(C.creme).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .gameCard(padding: 12, radius: 20, stroke: C.brand)
        .stitched(20, color: C.brand, opacity: 0.25)
    }
}

struct InviteSheet: View {
    @State private var team = Team.shared
    @State private var copied = false
    var body: some View {
        VStack(spacing: 16) {
            Disp("INVITE FRIENDS", size: 30).padding(.top, 24)
            Text("They get 7 days free — no card. The link opens the app, or gets it and gives them the code.")
                .font(F.round(15, .semibold)).foregroundStyle(C.creme2).multilineTextAlignment(.center)
            Text(team.team?.code ?? "")
                .font(.system(size: 44, weight: .heavy, design: .monospaced)).kerning(6)
                .foregroundStyle(C.creme)
                .padding(.vertical, 14).frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(C.char950)
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(C.brand, style: StrokeStyle(lineWidth: 2.5, dash: [8, 6]))))
            if let t = team.team {
                LinkShareButton { await ShareCards.invite(t) } label: { Label("SEND INVITE", systemImage: "paperplane.fill") }
                    .buttonStyle(.gameLarge)
            }
            Button(copied ? "COPIED ✓" : "COPY CODE") {
                UIPasteboard.general.string = team.team?.code
                copied = true
                Haptics.play(.latch)
            }
            .buttonStyle(.game(.charcoal))
            Spacer()
        }
        .padding(.horizontal, 20)
        .presentationDetents([.medium])
        .presentationBackground(C.char900)
    }
}

/// A teammate's session, opened from the feed: what's in it, and SAVE TO MY SESSIONS.
struct SharedSessionSheet: View {
    let meta: PostMeta?
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var saved = false

    var body: some View {
        let items = (meta?.items ?? []).compactMap { pair -> PlanItem? in
            guard let id = pair.first, Library.shared.has(id) else { return nil }
            return PlanItem(id, sets: pair[safe: 1].flatMap { Int($0) })
        }
        VStack(alignment: .leading, spacing: 12) {
            Disp((meta?.title ?? "Session").uppercased(), size: 28).padding(.top, 22).lineLimit(2).minimumScaleFactor(0.7)
            Text("\(items.count) drills · \(items.reduce(0) { $0 + $1.min }) min").font(F.round(15, .semibold)).foregroundStyle(C.muted)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(items, id: \.drill) { it in
                        HStack {
                            Text(Library.shared.drill(it.drill).name).font(F.round(16, .semibold)).foregroundStyle(C.creme)
                            Spacer()
                            Text(it.dose).font(F.round(13)).foregroundStyle(C.muted)
                        }
                        .gameCard(padding: 12, radius: 16)
                    }
                }
            }
            Button(saved ? "SAVED ✓" : "SAVE TO MY SESSIONS") {
                if let id = meta?.pro, let p = Library.shared.pro(id) { store.save(p) }
                else { store.sessions.insert(Session(name: meta?.title ?? "Team Session", items: items), at: 0) }
                saved = true
                Haptics.play(.goal)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { dismiss() }
            }
            .buttonStyle(.gameLarge)
            .disabled(saved || items.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .presentationDetents([.medium, .large])
        .presentationBackground(C.char900)
    }
}

// MARK: - share: the team first, then everywhere else

/// The share button on every session and film. Opens a small sheet: SEND TO <TEAM> on top, other apps under it.
struct ShareButton: View {
    let item: Shareable
    var size: CGFloat = 46
    @State private var open = false
    var body: some View {
        Button { open = true } label: { Image(systemName: "square.and.arrow.up").font(.system(size: size * 0.38, weight: .heavy)) }
            .buttonStyle(.gameRound(.charcoal, size: size))
            .accessibilityLabel("Share")
            .sheet(isPresented: $open) { ShareSheet(item: item) }
    }
}

struct ShareSheet: View {
    let item: Shareable
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var team = Team.shared
    @State private var note = ""
    @State private var sent: Set<String> = []
    @State private var busy: Set<String> = []

    private func send(_ id: String, close: Bool) {
        busy.insert(id)
        Task {
            if await team.share(item, note: note, to: id) {
                sent.insert(id)
                Haptics.play(.goal)
                if close { DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { dismiss() } }
            }
            busy.remove(id)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: item.icon).font(.system(size: 20, weight: .heavy)).foregroundStyle(C.brandHi)
                    .frame(width: 50, height: 50).background(RoundedRectangle(cornerRadius: 14).fill(C.brandLip))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(F.round(17, .bold)).foregroundStyle(C.creme).lineLimit(2)
                    Text(item.subtitle).font(F.round(13)).foregroundStyle(C.muted)
                }
            }
            .padding(.top, 24)

            if !team.teams.isEmpty {
                // 1 ? your teams (one big button each; several teams = a short list)
                TextField("", text: $note, prompt: Text("Add a message (optional)").foregroundStyle(C.muted))
                    .font(F.round(16, .medium)).foregroundStyle(C.creme)
                    .padding(.horizontal, 14).frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(C.char950)
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(C.charInk, lineWidth: 2)))
                if team.teams.count == 1, let t = team.teams.first {
                    Button { send(t.id, close: true) } label: {
                        HStack(spacing: 10) {
                            TeamCrest(name: t.name, logo: t.logo, color: t.color, size: 30)
                            Text(sent.contains(t.id) ? "SENT ✓" : "SEND TO \(t.name.uppercased())")
                        }
                    }
                    .buttonStyle(.gameLarge)
                    .disabled(!busy.isEmpty || sent.contains(t.id))
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(team.ordered) { t in
                                let done = sent.contains(t.id)
                                HStack(spacing: 12) {
                                    TeamCrest(name: t.name, logo: t.logo, color: t.color, size: 36)
                                    Text(t.name).font(F.round(16, .bold)).foregroundStyle(C.creme).lineLimit(1)
                                    Spacer(minLength: 4)
                                    Button(done ? "SENT ✓" : busy.contains(t.id) ? "…" : "SEND") { send(t.id, close: false) }
                                        .buttonStyle(.game(done ? .charcoal : .brand, height: 38, font: 15, block: false))
                                        .fixedSize()
                                        .disabled(done || busy.contains(t.id))
                                }
                                .gameCard(padding: 10, radius: 18)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .frame(maxHeight: 230)
                }
                if let e = team.error { Text(e).font(F.round(13, .semibold)).foregroundStyle(C.gold) }
            } else {
                Text("Make or join a team in the Teams tab to send this to your friends in the app.")
                    .font(F.round(14, .semibold)).foregroundStyle(C.muted)
            }

            // 2 ? everywhere else
            LinkShareButton { await ShareCards.item(item) } label: {
                Label("OTHER APPS", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.game(.charcoal))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .presentationDetents([.height(team.teams.isEmpty ? 280 : team.teams.count == 1 ? 360 : min(560, 330 + CGFloat(team.teams.count) * 64))])
        .presentationBackground(C.char900)
    }
}

// MARK: - pictures without photos

/// The team's picture: its logo (128 px), or a shield in its colour with its initials.
struct TeamCrest: View {
    let name: String
    var logo: String? = nil
    var image: UIImage? = nil
    let color: Int
    let size: CGFloat

    var body: some View {
        let img = image ?? Team.logoImage(logo)
        let tint = Color(hex: Team.colors[safe: color] ?? Team.colors[0])
        ZStack {
            if let img {
                Image(uiImage: img).resizable().scaledToFill()
                    .frame(width: size, height: size).clipShape(Circle())
                    .overlay(Circle().stroke(C.charInk, lineWidth: max(2, size * 0.04)))
            } else {
                TeamShield().fill(LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                    .overlay(TeamShield().stroke(C.charInk, lineWidth: max(2, size * 0.04)))
                    .overlay(TeamShield(pad: size * 0.09).stroke(.white.opacity(0.35), lineWidth: max(1, size * 0.02)))
                Text(Self.initials(name)).font(F.display(size * 0.36)).foregroundStyle(C.charInk.opacity(0.85)).offset(y: -size * 0.02)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    static func initials(_ n: String) -> String {
        let w = n.split(separator: " ").filter { !$0.isEmpty }
        return (w.count >= 2 ? "\(w[0].prefix(1))\(w[1].prefix(1))" : String(n.prefix(2))).uppercased()
    }
}

private struct TeamShield: Shape {
    var pad: CGFloat = 0
    func path(in r0: CGRect) -> Path {
        let r = r0.insetBy(dx: pad, dy: pad)
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.14), control: CGPoint(x: r.maxX - r.width * 0.2, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - r.width * 0.04, y: r.minY + r.height * 0.55))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.maxY), control: CGPoint(x: r.maxX - r.width * 0.12, y: r.maxY - r.height * 0.12))
        p.addQuadCurve(to: CGPoint(x: r.minX + r.width * 0.04, y: r.minY + r.height * 0.55), control: CGPoint(x: r.minX + r.width * 0.12, y: r.maxY - r.height * 0.12))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.14))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.minY), control: CGPoint(x: r.minX + r.width * 0.2, y: r.minY))
        return p
    }
}

/// A teammate: their initial on a colour of their own (no profile photos on the server).
struct MemberDot: View {
    let name: String
    let seed: Int
    let size: CGFloat
    private static let tones: [UInt32] = [0x3EC25A, 0xFFC531, 0x5B9BF0, 0xE87D5B, 0xB18CF0, 0x4FD1C5, 0xF2A1C0]
    var body: some View {
        let tone = Color(hex: Self.tones[abs(seed) % Self.tones.count])
        Text(String(name.prefix(1)).uppercased())
            .font(F.display(size * 0.46)).foregroundStyle(C.charInk)
            .frame(width: size, height: size)
            .background(Circle().fill(tone).overlay(Circle().stroke(C.charInk, lineWidth: 2)))
            .accessibilityHidden(true)
    }
}

extension String {
    /// The same number on every launch (hashValue changes per run), so a teammate keeps their colour.
    var stableSeed: Int { unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff } }
}

/// HAVE A CODE? from the paywall (2026-10-30): one box for every code ? a friend's team (7 days free), a friend's
/// gift (7 days free) or a FREE LIFETIME code (notes/40) ? into the app.
struct JoinCodeSheet: View {
    let done: () -> Void
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var team = Team.shared
    @State private var code = ""
    @State private var preview: Team.Preview?
    @State private var busy = false
    @State private var note: String?

    var body: some View {
        VStack(spacing: 16) {
            Disp("HAVE A CODE?", size: 30).padding(.top, 24)
            Text("Creator, team, gift, free-pass or 40% off code").font(F.round(14, .semibold)).foregroundStyle(C.muted).padding(.top, -8)
            CodeEntry(code: $code, keypad: preview == nil)
                .onChange(of: code) { _, v in
                    let c = Team.clean(v)
                    if c != v { code = c }
                    preview = nil
                    if c.count == 6 { Task { preview = await team.preview(code: c) } }
                }
            if !team.signedIn {
                AppleSignIn()
            }
            if let p = preview {
                if p.isCreator { CreatorRow(name: p.name).gameCard(padding: 10, radius: 16) }
                else if p.isLifetime { LifetimeRow().gameCard(padding: 10, radius: 16) }
                else if p.isOff40 { Off40Row().gameCard(padding: 10, radius: 16) }
                else if p.isGift { GiftRow(from: p.name).gameCard(padding: 10, radius: 16) } else {
                HStack(spacing: 12) {
                    TeamCrest(name: p.name, logo: p.logo, color: p.color, size: 40)
                    Text(p.name).font(F.round(17, .bold)).foregroundStyle(C.creme)
                    Spacer()
                    Text("\(p.members) player\(p.members == 1 ? "" : "s")").font(F.round(13)).foregroundStyle(C.muted)
                }
                .gameCard(padding: 10, radius: 16)
                }
            }
            if let n = note ?? team.error { Text(n).font(F.round(14, .semibold)).foregroundStyle(C.gold).multilineTextAlignment(.center) }
            Spacer()
            Button(busy ? "ONE SEC…" : preview?.isLifetime == true ? "UNLOCK FOR LIFE" : preview?.isOff40 == true ? "GET 40% OFF" : preview?.isGift == true ? "GET 7 DAYS FREE" : preview == nil || preview?.isCreator == true ? "USE CODE" : "JOIN · 7 DAYS FREE") {
                busy = true
                note = nil
                Task {
                    if preview?.isCreator == true {
                        // a creator's code: the account is tied to them, then back to the plans (it unlocks nothing)
                        let ok = await team.claimCreator(code: code)
                        busy = false
                        if ok { Haptics.play(.goal); dismiss() }
                        return
                    }
                    if preview?.isOff40 == true {
                        // launch-list code ? the 40% OFF plans (StayOfferView, launch mode: no clock)
                        let ok = await team.redeemOff40(code: code, store: store)
                        busy = false
                        if ok == true { Haptics.play(.goal); dismiss(); QuickActions.shared.openLaunch() }
                        return
                    }
                    let granted = preview?.isLifetime == true ? await team.redeemLifetime(code: code, store: store)
                                : preview?.isGift == true ? await team.redeemGift(code: code, store: store)
                                                          : await team.join(code: code, store: store)
                    busy = false
                    guard let granted else { return }
                    if granted || team.onTrial {
                        Haptics.play(.goal)
                        dismiss()
                        done()
                    } else {
                        note = preview?.isGift == true ? "This account already had its free week, so pick a plan to keep going."
                                                       : "You're on the team! Your free week was already used, so pick a plan to keep going."
                    }
                }
            }
            .buttonStyle(.gameLarge(.brand, feel: .kick))
            .disabled(code.count != 6 || busy || !team.signedIn)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
        .presentationDetents([.large])
        .presentationBackground(C.char900)
        .onAppear { if let c = team.pendingCode { code = c } }
        .onChange(of: team.signedIn) { _, on in if on, code.count == 6 { Task { preview = await team.preview(code: code) } } }
    }
}

/// A content creator's code (2026-11-12): whose code it is, so the viewer knows it worked.
struct CreatorRow: View {
    let name: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "star.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(C.brandInk)
                .frame(width: 40, height: 40).background(Circle().fill(C.brand))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(name.uppercased())'S CODE").font(F.round(16, .bold)).foregroundStyle(C.creme).lineLimit(1)
                Text("You're supporting this creator").font(F.round(13, .semibold)).foregroundStyle(C.muted)
            }
            Spacer(minLength: 0)
        }
    }
}

/// A free LIFETIME code (notes/40): gold, the whole app free forever.
struct LifetimeRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "crown.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(C.goldInk)
                .frame(width: 40, height: 40).background(Circle().fill(LinearGradient(colors: [C.goldHi, C.gold], startPoint: .top, endPoint: .bottom)))
            VStack(alignment: .leading, spacing: 2) {
                Text("FREE LIFETIME PASS").font(F.round(16, .bold)).foregroundStyle(C.gold).lineLimit(1)
                Text("Everything, free forever · no card").font(F.round(13, .semibold)).foregroundStyle(C.muted)
            }
            Spacer(minLength: 0)
        }
    }
}

/// A launch-list code from the waitlist email: 40% OFF every plan (2026-11-01).
struct Off40Row: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("%").font(F.display(22)).foregroundStyle(C.goldInk)
                .frame(width: 40, height: 40).background(Circle().fill(LinearGradient(colors: [C.goldHi, C.gold], startPoint: .top, endPoint: .bottom)))
            VStack(alignment: .leading, spacing: 2) {
                Text("40% OFF EVERY PLAN").font(F.round(16, .bold)).foregroundStyle(C.gold).lineLimit(1)
                Text("Your launch-list code").font(F.round(13, .semibold)).foregroundStyle(C.muted)
            }
            Spacer(minLength: 0)
        }
    }
}

/// A friend's gift code: their name + 7 DAYS FREE (in the code boxes, 2026-10-29).
struct GiftRow: View {
    let from: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "gift.fill").font(.system(size: 20, weight: .bold)).foregroundStyle(C.brandInk)
                .frame(width: 40, height: 40).background(Circle().fill(C.brand))
            VStack(alignment: .leading, spacing: 2) {
                Text("A GIFT FROM \(from.uppercased())").font(F.round(16, .bold)).foregroundStyle(C.creme).lineLimit(1)
                Text("7 days free · no card").font(F.round(13, .semibold)).foregroundStyle(C.muted)
            }
            Spacer(minLength: 0)
        }
    }
}

/// One tap makes the account: Sign in with Apple (the only sign-in, 2026-10-25).
struct AppleSignIn: View {
    /// Onboarding: called once Apple sign-in is over (worked OR failed ? only cancelling the Apple sheet stays put),
    /// so the account page ALWAYS goes into the app (user, 2026-10-30: "no matter what it should take you INTO the app").
    var onDone: (() -> Void)? = nil
    /// The Apple sheet is opening / was closed without signing in (the account page's ball animates in between).
    var onStart: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil
    @Environment(AppStore.self) private var store
    @State private var team = Team.shared
    @State private var nonce = Nonce.make()
    var body: some View {
        SignInWithAppleButton(.continue) { req in
            onStart?()
            nonce = Nonce.make()
            req.requestedScopes = [.fullName]
            req.nonce = Nonce.sha256(nonce)
        } onCompletion: { result in
            let n = nonce
            let canceled = { if case .failure(let e) = result { return (e as? ASAuthorizationError)?.code == .canceled }; return false }()
            Task {
                await team.signIn(result, nonce: n, store: store)
                if !canceled { onDone?() } else { onCancel?() }
            }
        }
        .signInWithAppleButtonStyle(.white)
        .frame(height: 58)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(C.line, lineWidth: 1))
    }
}

/// A player's picture inside the team: their photo (96 px, from the server) or their initial on a colour.
struct PlayerPic: View {
    let id: String
    let name: String
    let size: CGFloat
    @Environment(AppStore.self) private var store
    @State private var team = Team.shared
    var body: some View {
        if let img = id == team.me ? store.avatar : team.avatars[id] {
            Image(uiImage: img).resizable().scaledToFill()
                .frame(width: size, height: size).clipShape(Circle())
                .overlay(Circle().stroke(C.charInk, lineWidth: 2))
                .accessibilityHidden(true)
        } else {
            MemberDot(name: name, seed: id.stableSeed, size: size)
        }
    }
}

/// A teammate's profile: picture, name, position + club, their numbers, and what they've done lately.
struct PlayerSheet: View {
    let member: MemberRow
    @State private var team = Team.shared
    var body: some View {
        let me = member.id == team.me
        let recent = team.feed.filter { $0.user_id == member.id && ["session", "film", "share_session", "share_film"].contains($0.kind) }.suffix(8).reversed()
        ScrollView {
            VStack(spacing: 14) {
                PlayerPic(id: member.id, name: member.name, size: 112)
                    .background(Circle().fill(C.charInk).offset(y: 5))
                    .padding(.top, 28)
                Disp((me ? "You" : member.name).uppercased(), size: 30)
                Text([member.position.map { Library.shared.positions[$0] ?? $0 }, member.club].compactMap { $0 }.joined(separator: " · "))
                    .font(F.round(15, .semibold)).foregroundStyle(C.muted).multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    Tile(value: "\(member.streak)", label: "DAY STREAK", icon: "flame.fill")
                    Tile(value: "\(member.minutesThisWeek)", label: "MIN THIS WEEK", icon: "clock.fill")
                    Tile(value: "\(member.level ?? 1)", label: "LEVEL", icon: "star.fill")
                }
                .padding(.top, 4)
                if !me { SafetyButtons(member: member) }
                if !recent.isEmpty {
                    H("LATELY")
                    VStack(spacing: 8) {
                        ForEach(Array(recent)) { p in
                            HStack(spacing: 10) {
                                Image(systemName: p.kind.contains("film") ? "play.rectangle.fill" : "figure.soccer")
                                    .font(.system(size: 14, weight: .heavy)).foregroundStyle(p.kind.contains("film") ? C.gold : C.brand)
                                    .frame(width: 22)
                                Text("\(p.kind.hasPrefix("share") ? "Shared" : p.kind == "film" ? "Watched" : "Finished") \(p.meta?.title ?? "")")
                                    .font(F.round(15, .semibold)).foregroundStyle(C.creme).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(p.date.formatted(.relative(presentation: .named))).font(F.round(12)).foregroundStyle(C.muted)
                            }
                            .gameCard(padding: 10, radius: 14)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(C.char900)
    }

    private struct Tile: View {
        let value: String
        let label: String
        let icon: String
        var body: some View {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 13, weight: .heavy)).foregroundStyle(C.brand)
                Text(value).font(F.display(26)).foregroundStyle(C.creme)
                Text(label).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(C.muted)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .gameCard(padding: 10, radius: 16)
        }
    }
}

// MARK: - report + block (App Store 1.2, 2026-10-30)

extension View {
    /// The report-a-message reasons, the block confirm, and the thank-you ? shared by the chat.
    func safetyDialogs(reporting: Binding<Post?>, blocking: Binding<MemberRow?>, reported: Binding<Bool?>) -> some View {
        self
            .confirmationDialog("Report this message", isPresented: Binding(get: { reporting.wrappedValue != nil }, set: { if !$0 { reporting.wrappedValue = nil } }),
                                titleVisibility: .visible, presenting: reporting.wrappedValue) { p in
                ForEach(Team.reportReasons, id: \.self) { r in
                    Button(r) { Task { reported.wrappedValue = await Team.shared.report(p, reason: r) } }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in Text("Why are you reporting it? You won't see it again.") }
            .confirmationDialog(blocking.wrappedValue.map { "Block \($0.name.hasSuffix(".") ? $0.name : $0.name + "?")" } ?? "", isPresented: Binding(get: { blocking.wrappedValue != nil }, set: { if !$0 { blocking.wrappedValue = nil } }),
                                titleVisibility: .visible, presenting: blocking.wrappedValue) { m in
                Button("Block", role: .destructive) { Task { await Team.shared.block(m.id) } }
                Button("Cancel", role: .cancel) {}
            } message: { _ in Text("You won't see their messages or activity in any team. They won't be told. Unblock any time from their profile.") }
            .alert(reported.wrappedValue == false ? "Couldn't send the report" : "Thanks for telling us",
                   isPresented: Binding(get: { reported.wrappedValue != nil }, set: { if !$0 { reported.wrappedValue = nil } })) {
                Button("OK") {}
            } message: {
                Text(reported.wrappedValue == false ? "Check your signal and try again, or email support@soccermax.app."
                     : "We look at every report within 24 hours and remove anything that breaks the rules.")
            }
    }
}

/// On another player's profile: report them, block / unblock them.
private struct SafetyButtons: View {
    let member: MemberRow
    @State private var team = Team.shared
    @State private var reasons = false
    @State private var confirmBlock = false
    @State private var reported: Bool?
    var body: some View {
        let isBlocked = team.blocked.contains(member.id)
        HStack(spacing: 10) {
            Button { reasons = true } label: { Label("Report", systemImage: "exclamationmark.bubble") }
            Button {
                if isBlocked { Task { await team.unblock(member.id) } } else { confirmBlock = true }
            } label: { Label(isBlocked ? "Unblock" : "Block", systemImage: "hand.raised") }
        }
        .font(F.round(14, .bold)).foregroundStyle(C.muted)
        .buttonStyle(.plain)
        .confirmationDialog("Report \(member.name)", isPresented: $reasons, titleVisibility: .visible) {
            ForEach(Team.reportReasons, id: \.self) { r in
                Button(r) { Task { reported = await team.report(player: member.id, reason: r) } }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Block \(member.name.hasSuffix(".") ? member.name : member.name + "?")", isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("Block", role: .destructive) { Task { await team.block(member.id) } }
        } message: { Text("You won't see their messages or activity in any team. They won't be told.") }
        .alert(reported == false ? "Couldn't send the report" : "Thanks for telling us",
               isPresented: Binding(get: { reported != nil }, set: { if !$0 { reported = nil } })) { Button("OK") {} } message: {
            Text(reported == false ? "Check your signal and try again, or email support@soccermax.app."
                 : "We look at every report within 24 hours and remove anything that breaks the rules.")
        }
    }
}


/// A teammate's (or my) live session in the feed: name + total, each category as a small glossy icon + minutes
/// (tap one = train it too), then their photos/videos (private bucket, loaded on demand). No border.
struct TeamSessionCard: View {
    let post: Post
    let name: String
    let profile: () -> Void

    private var parts: [SessionPart] {
        if let p = post.meta?.parts, !p.isEmpty { return p }
        let a = TrainingArea.of(post.meta?.area)
        return [SessionPart(area: post.meta?.area ?? "", name: a?.name ?? post.meta?.title ?? "Session",
                            icon: a?.icon ?? "soccerball", seconds: (post.meta?.minutes ?? 0) * 60)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Button(action: profile) { PlayerPic(id: post.user_id, name: name, size: 38) }
                    .buttonStyle(.press)
                (Text(name).font(F.round(16, .bold)).foregroundColor(C.creme)
                 + Text(" trained").font(F.round(16)).foregroundColor(C.creme2))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(minText(Double(post.meta?.minutes ?? 0)).uppercased()).font(F.display(18)).foregroundStyle(C.brand)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(parts, id: \.self) { p in
                        let a = TrainingArea(id: p.area, name: p.name, icon: p.icon)
                        Button { FreeStart.shared.open(TrainingArea.of(p.area) ?? a) } label: {
                            HStack(spacing: 8) {
                                AreaIcon(area: a, size: 34)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(p.name).font(F.round(14, .bold)).foregroundStyle(C.creme).lineLimit(1)
                                    Text("\(p.minutes) min").font(F.round(12, .semibold)).foregroundStyle(C.muted)
                                }
                            }
                        }
                        .buttonStyle(.press(.kick))
                        .accessibilityLabel("Train \(p.name) too")
                    }
                }
            }
            .scrollIndicators(.hidden)
            if let media = post.meta?.media, !media.isEmpty {
                HStack(spacing: 8) {
                    ForEach(media.prefix(4), id: \.self) { m in RemoteMediaTile(path: m) }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(C.char850))
    }
}

/// A photo/video from the team bucket: downloads once (cached), tap = full screen.
struct RemoteMediaTile: View {
    let path: String
    @State private var file: URL?
    @State private var img: UIImage?
    @State private var open = false
    var body: some View {
        Button { if file != nil { open = true } } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let img { Image(uiImage: img).resizable().scaledToFill() }
                    else { C.char800.overlay { ProgressView().tint(C.muted) } }
                }
                .overlay {
                    if SessionMedia.isVideo(path) {
                        Image(systemName: "play.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(C.creme)
                            .frame(width: 36, height: 36).background(Circle().fill(C.char950.opacity(0.6)))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.press(.stud))
        .frame(maxWidth: 90)
        .task(id: path) {
            guard let f = try? await Team.shared.api.mediaFile(path) else { return }
            file = f
            img = await SessionMedia.thumb(file: f)
        }
        .fullScreenCover(isPresented: $open) { if let file { MediaViewer(name: "", file: file) } }
    }
}
