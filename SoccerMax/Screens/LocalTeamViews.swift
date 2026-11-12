// Team-finding pieces (2026-11-08, notes/26 top): our contacts explainer before Apple's ONE prompt, the contacts invite
// list, the quiet "turn contacts on" card (only after a NO, closable forever), TEAMS NEAR YOU with ASK TO JOIN, the
// owner's JOIN REQUESTS, and the team-location row used when making / editing a team. Borderless Sessions-tab look.
import CoreLocation
import MessageUI
import SwiftUI

// MARK: - contacts: our explainer first

/// Shown BEFORE Apple's contacts prompt (we only get one): why, then ALLOW (? Apple's prompt) or NOT NOW (? nothing,
/// ask again some other time from the Team tab).
struct ContactsExplainer: View {
    var done: (Bool) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var book = FriendsBook.shared
    @State private var asking = false

    var body: some View {
        VStack(spacing: 0) {
            GlowIcon(symbol: "person.2.fill", size: 84).padding(.top, 34)
            Disp("FIND YOUR FRIENDS", size: 32).padding(.top, 18)
            Text("Soccer Lab is better with your teammates.").font(F.round(16, .semibold)).foregroundStyle(C.muted)
                .multilineTextAlignment(.center).padding(.top, 6)
            VStack(alignment: .leading, spacing: 16) {
                row("person.badge.plus", "Invite friends in one tap", "Text them your team's link")
                row("person.3.fill", "Get your team together", "Everyone in one chat and leaderboard")
                row("lock.fill", "Your contacts stay on your phone", "We never upload them or text anyone for you")
            }
            .padding(.horizontal, 28).padding(.top, 28)
            Spacer(minLength: 20)
            Button(asking ? "…" : "ALLOW CONTACTS") {
                asking = true
                Task {
                    await book.ask()
                    asking = false
                    done(book.allowed)
                    dismiss()
                }
            }
            .buttonStyle(.gameLarge)
            .disabled(asking)
            Button("Not now") { book.skipped = true; done(false); dismiss() }
                .font(F.round(17, .semibold)).foregroundStyle(C.muted).frame(height: 44)
        }
        .padding(.horizontal, 20).padding(.bottom, 8)
        .presentationDetents([.large])
        .presentationBackground(C.char900)
    }

    private func row(_ icon: String, _ title: String, _ sub: String) -> some View {
        HStack(spacing: 14) {
            GlowIcon(symbol: icon, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(F.round(17, .bold)).foregroundStyle(C.creme)
                Text(sub).font(F.round(14, .semibold)).foregroundStyle(C.muted)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - contacts: on the Team tab

/// One row on the Team tab, chosen by what the player said:
/// allowed ? INVITE FRIENDS (opens the list) · never asked / said "not now" ? FIND FRIENDS (our explainer) ·
/// said NO to Apple ? a closable card with the steps to turn it on in Settings. Closed once = gone for good.
struct FriendsRow: View {
    @State private var book = FriendsBook.shared
    @State private var explaining = false
    @State private var listing = false
    @Environment(\.scenePhase) private var phase

    var body: some View {
        Group {
            if book.allowed {
                Button { listing = true } label: { line("person.2.fill", "Invite friends from contacts", "Text them your team's link") }
                    .buttonStyle(.press)
            } else if book.undecided {
                Button { explaining = true } label: { line("person.2.fill", "Find friends in your contacts", "Invite them to train with you") }
                    .buttonStyle(.press)
            } else if book.denied && !book.cardClosed {
                offCard
            }
        }
        .sheet(isPresented: $explaining) { ContactsExplainer { ok in if ok { listing = true } } }
        .sheet(isPresented: $listing) { ContactsInviteSheet() }
        .onChange(of: phase) { _, p in if p == .active { book.recheck() } }   // came back from Settings
    }

    private func line(_ icon: String, _ title: String, _ sub: String) -> some View {
        HStack(spacing: 14) {
            GlowIcon(symbol: icon, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(F.round(16, .bold)).foregroundStyle(C.creme)
                Text(sub).font(F.round(13, .semibold)).foregroundStyle(C.muted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .heavy)).foregroundStyle(C.muted)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(LinearGradient(colors: [C.char800, C.char850], startPoint: .top, endPoint: .bottom)))
        .contentShape(Rectangle())
    }

    /// Said NO to Apple's prompt: how to turn it on. Shown until closed ? then never again.
    private var offCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                GlowIcon(symbol: "person.2.fill", size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Allow contacts").font(F.round(16, .bold)).foregroundStyle(C.creme)
                    Text("To invite friends from your phone, turn it on in Settings:").font(F.round(13, .semibold)).foregroundStyle(C.muted)
                }
                Spacer(minLength: 0)
                Button { withAnimation { book.cardClosed = true } } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(C.muted)
                        .frame(width: 30, height: 30).background(Circle().fill(C.char700))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            Text("Settings → Apps → Soccer Lab → Contacts → Full Access")
                .font(F.round(13, .bold)).foregroundStyle(C.creme2)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Capsule().fill(C.char700))
            Button("Open Settings") {
                if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
            }
            .font(F.round(15, .bold)).foregroundStyle(C.brand)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(LinearGradient(colors: [C.char800, C.char850], startPoint: .top, endPoint: .bottom)))
    }
}

/// Everyone in your contacts with a phone number, searchable, each with INVITE (a text with your team's link).
struct ContactsInviteSheet: View {
    @State private var book = FriendsBook.shared
    @State private var team = Team.shared
    @State private var search = ""
    @State private var texting: FriendsBook.Friend?
    @State private var sent: Set<String> = []

    private var shown: [FriendsBook.Friend] {
        let q = search.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? book.friends : book.friends.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }
    private var forTeam: TeamRow? { team.team ?? team.ordered.first }

    var body: some View {
        VStack(spacing: 0) {
            Disp("INVITE FRIENDS", size: 28).padding(.top, 24)
            Text(forTeam.map { "They get a link to join \($0.name)." } ?? "They get a link to Soccer Lab.")
                .font(F.round(14, .semibold)).foregroundStyle(C.muted).padding(.top, 4)
            TextField("", text: $search, prompt: Text("Search").foregroundStyle(C.muted))
                .font(F.round(17, .semibold)).foregroundStyle(C.creme)
                .padding(.horizontal, 16).frame(height: 48)
                .background(Capsule().fill(C.char800))
                .padding(.horizontal, 16).padding(.top, 16)
            List(shown) { f in
                HStack(spacing: 12) {
                    MemberDot(name: f.name, seed: abs(f.id.hashValue) % 9, size: 38)
                    Text(f.name).font(F.round(16, .semibold)).foregroundStyle(C.creme).lineLimit(1)
                    Spacer()
                    Button(sent.contains(f.id) ? "SENT" : "INVITE") { texting = f }
                        .font(F.round(13, .heavy))
                        .foregroundStyle(sent.contains(f.id) ? C.muted : C.brandInk)
                        .padding(.horizontal, 14).frame(height: 32)
                        .background(Capsule().fill(sent.contains(f.id) ? C.char700 : C.brand))
                        .buttonStyle(.plain)
                }
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(C.creme.opacity(0.06))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .overlay {
                if book.friends.isEmpty { Text("No contacts with a phone number.").font(F.round(15)).foregroundStyle(C.muted) }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(C.char900)
        .task { if book.friends.isEmpty { await book.load() } }
        .sheet(item: $texting) { f in
            TextComposer(to: f.phone, body: book.inviteText(team: forTeam)) { ok in if ok { sent.insert(f.id) } }
                .ignoresSafeArea()
        }
    }
}

/// Messages' own compose screen (nothing is sent without the player tapping Send). No Messages (iPad, simulator) ?
/// the share sheet with the same text.
private struct TextComposer: UIViewControllerRepresentable {
    let to: String
    let body: String
    let done: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }
    func makeUIViewController(context: Context) -> UIViewController {
        if MFMessageComposeViewController.canSendText() {
            let vc = MFMessageComposeViewController()
            vc.recipients = [to]
            vc.body = body
            vc.messageComposeDelegate = context.coordinator
            return vc
        }
        return UIActivityViewController(activityItems: [body], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let done: (Bool) -> Void
        init(done: @escaping (Bool) -> Void) { self.done = done }
        func messageComposeViewController(_ c: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            done(result == .sent)
            c.dismiss(animated: true)
        }
    }
}

// MARK: - teams near you

/// TEAMS NEAR YOU on the Team tab: teams whose creator set a place, closest first, each with ASK TO JOIN.
/// Location off ? one quiet row to turn it on. Nothing at all until the server has the local-teams SQL.
struct NearbyTeamsSection: View {
    @State private var local = LocalTeams.shared
    @State private var where_ = Locator.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if where_.allowed {
                if !local.nearby.isEmpty {
                    Text("TEAMS NEAR YOU").font(F.round(13, .heavy)).kerning(1.6).foregroundStyle(C.creme2).padding(.horizontal, 4)
                    ForEach(local.nearby) { t in NearbyTeamRow(t: t) }
                }
            } else if !where_.denied {
                Button { where_.ask() } label: {
                    HStack(spacing: 14) {
                        GlowIcon(symbol: "location.fill", size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Find teams near you").font(F.round(16, .bold)).foregroundStyle(C.creme)
                            Text("See local teams and ask to join").font(F.round(13, .semibold)).foregroundStyle(C.muted)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .heavy)).foregroundStyle(C.muted)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(LinearGradient(colors: [C.char800, C.char850], startPoint: .top, endPoint: .bottom)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.press)
            }
        }
        .task(id: where_.coordinate?.latitude) { await local.findNearby() }
        .onAppear { if where_.allowed { where_.ask() } }   // fresh fix
    }
}

private struct NearbyTeamRow: View {
    let t: NearbyTeam
    @State private var local = LocalTeams.shared
    @State private var busy = false

    var body: some View {
        HStack(spacing: 12) {
            TeamCrest(name: t.name, logo: t.logo, color: t.color, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.name).font(F.round(17, .bold)).foregroundStyle(C.creme).lineLimit(1)
                Text([t.place, t.km < 1 ? "under 1 km" : "\(Int(t.km.rounded())) km", "\(t.members) player\(t.members == 1 ? "" : "s")"]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(F.round(13, .semibold)).foregroundStyle(C.muted).lineLimit(1)
            }
            Spacer(minLength: 6)
            Button(t.requested ? "ASKED" : "ASK TO JOIN") {
                busy = true
                Task { await local.ask(t); busy = false }
            }
            .font(F.round(13, .heavy))
            .foregroundStyle(t.requested ? C.muted : C.brandInk)
            .padding(.horizontal, 14).frame(height: 34)
            .background(Capsule().fill(t.requested ? C.char700 : C.brand))
            .buttonStyle(.plain)
            .disabled(busy)
            .accessibilityHint(t.requested ? "Tap to cancel your request" : "Sends a request to the team's creator")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(LinearGradient(colors: [C.char800, C.char850], startPoint: .top, endPoint: .bottom)))
    }
}

// MARK: - join requests (team creator only)

/// "3 players want to join · REVIEW" at the top of the creator's team chat.
struct RequestsBanner: View {
    let team: TeamRow
    @State private var local = LocalTeams.shared
    @State private var open = false

    var body: some View {
        let n = local.requests[team.id]?.count ?? 0
        Group {
            if team.owner == Team.shared.me, n > 0 {
                Button { open = true } label: {
                    HStack(spacing: 10) {
                        GlowIcon(symbol: "person.crop.circle.badge.plus", size: 34)
                        Text("\(n) player\(n == 1 ? " wants" : "s want") to join").font(F.round(15, .bold)).foregroundStyle(C.creme)
                        Spacer()
                        Text("REVIEW").font(F.round(13, .heavy)).foregroundStyle(C.brand)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(C.char800))
                }
                .buttonStyle(.press)
            }
        }
        .task(id: team.id) { if team.owner == Team.shared.me { await local.loadRequests(team.id) } }
        .sheet(isPresented: $open) { RequestsSheet(team: team) }
    }
}

struct RequestsSheet: View {
    let team: TeamRow
    @Environment(AppStore.self) private var store
    @State private var local = LocalTeams.shared

    var body: some View {
        let list = local.requests[team.id] ?? []
        VStack(spacing: 0) {
            Disp("JOIN REQUESTS", size: 28).padding(.top, 24)
            Text("Only you, the creator, can let players in.").font(F.round(14, .semibold)).foregroundStyle(C.muted).padding(.top, 4)
            ScrollView {
                VStack(spacing: 10) {
                    if list.isEmpty {
                        Text("No requests right now.").font(F.round(15)).foregroundStyle(C.muted).padding(.top, 40)
                    }
                    ForEach(list) { r in
                        HStack(spacing: 12) {
                            MemberDot(name: r.name, seed: abs(r.user_id.hashValue) % 9, size: 42)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.name).font(F.round(17, .bold)).foregroundStyle(C.creme).lineLimit(1)
                                Text([r.position, r.level.map { "Level \($0)" }].compactMap { $0 }.joined(separator: " · "))
                                    .font(F.round(13, .semibold)).foregroundStyle(C.muted)
                            }
                            Spacer()
                            Button { Task { await local.answer(r, team: team.id, accept: false, store: store) } } label: {
                                Image(systemName: "xmark").font(.system(size: 14, weight: .heavy)).foregroundStyle(C.creme)
                                    .frame(width: 40, height: 40).background(Circle().fill(C.char700))
                            }
                            .buttonStyle(.plain).accessibilityLabel("Decline \(r.name)")
                            Button { Task { await local.answer(r, team: team.id, accept: true, store: store) } } label: {
                                Image(systemName: "checkmark").font(.system(size: 15, weight: .heavy)).foregroundStyle(C.brandInk)
                                    .frame(width: 40, height: 40).background(Circle().fill(C.brand))
                            }
                            .buttonStyle(.plain).accessibilityLabel("Let \(r.name) in")
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(C.char800))
                    }
                    if let e = local.error { Text(e).font(F.round(13, .semibold)).foregroundStyle(C.gold) }
                }
                .padding(16)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(C.char900)
        .task { await local.loadRequests(team.id) }
    }
}

// MARK: - team location (make / edit, creator only)

/// "Show to players nearby" on the make / edit team sheet: off = private (code only). On = your current town,
/// rounded to ~1 km on the server; the name is editable ("Victoria Park").
struct TeamPlaceField: View {
    @Binding var on: Bool
    @Binding var place: String
    @State private var where_ = Locator.shared
    @State private var finding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $on.animation(.snappy)) {
                HStack(spacing: 12) {
                    GlowIcon(symbol: "location.fill", size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Show to players nearby").font(F.round(16, .bold)).foregroundStyle(C.creme)
                        Text("Local players can find you and ask to join").font(F.round(12, .semibold)).foregroundStyle(C.muted)
                    }
                }
            }
            .tint(C.brand)
            if on {
                if where_.denied {
                    Text("Location is off for Soccer Lab. Turn it on in Settings → Apps → Soccer Lab → Location.")
                        .font(F.round(13, .semibold)).foregroundStyle(C.gold)
                } else {
                    TextField("", text: $place, prompt: Text(finding ? "Finding your town?" : "Where you play (e.g. Victoria Park)").foregroundStyle(C.muted))
                        .font(F.round(16, .semibold)).foregroundStyle(C.creme)
                        .padding(.horizontal, 14).frame(height: 46)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(C.char950))
                        .onChange(of: place) { _, v in if v.count > 60 { place = String(v.prefix(60)) } }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(C.char800))
        .onChange(of: on) { _, v in if v { fill() } }
        .onChange(of: where_.coordinate?.latitude) { _, _ in if on && place.isEmpty { fill() } }
    }

    private func fill() {
        where_.ask()
        guard place.isEmpty else { return }
        finding = true
        Task {
            if let t = await where_.townName(), place.isEmpty { place = t }
            finding = false
        }
    }
}
