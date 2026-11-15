// RANKS + GLOBAL LEADERBOARD (2026-11-15). Your rank is the level badge you already earn (Bronze I ... Diamond V,
// Data/Stats.swift), now fed by everything you do in the app (Lab.bonusXP). Signed-in players also appear on one
// global leaderboard: the phone sends its XP total to public.xp_sync (supabase/2026-11-15-ai-and-ranks.sql), which
// caps how fast it can rise, and reads the table back with public.leaderboard. Shown name = first name + initial;
// a player can hide from the table and still see their own place.
import SwiftUI

@MainActor @Observable
final class Ranks {
    static let shared = Ranks()

    struct Row: Decodable, Identifiable, Hashable {
        let place: Int
        let name: String
        let pos: String?
        let xp: Int
        let me: Bool
        var id: String { "\(place)-\(name)-\(xp)-\(me)" }
    }

    /// My place among everyone, and how many players there are (once synced).
    private(set) var rank: Int?
    private(set) var total: Int?
    private(set) var hidden = false
    private(set) var board: [Row] = []
    private(set) var loading = false
    private var lastSync = Date.distantPast

    /// "Top 5%" from rank and total.
    var topPercent: Int? {
        guard let rank, let total, total > 0 else { return nil }
        return max(1, Int((Double(rank) / Double(total) * 100).rounded(.up)))
    }

    /// Send my XP and get my place. At most once a minute unless `force`.
    func sync(_ store: AppStore, force: Bool = false, hide: Bool? = nil) async {
        guard Team.shared.signedIn, force || hide != nil || Date().timeIntervalSince(lastSync) > 60 else { return }
        lastSync = Date()
        let a = store.answers
        var args: [String: Any] = ["p_xp": store.xp, "p_name": "\(a.first) \(a.last)", "p_position": a.position]
        if let hide { args["p_hidden"] = hide }
        struct Reply: Decodable { let rank: Int; let total: Int; let xp: Int; let hidden: Bool }
        if let r: Reply = try? await Team.shared.api.rpc("xp_sync", args) {
            rank = r.rank
            total = r.total
            hidden = r.hidden
        }
    }

    func loadBoard(_ store: AppStore) async {
        guard Team.shared.signedIn else { return }
        loading = true
        defer { loading = false }
        await sync(store, force: true)
        if let rows: [Row] = try? await Team.shared.api.rpc("leaderboard", ["p_limit": 50]) { board = rows }
    }

    func setHidden(_ yes: Bool, store: AppStore) async {
        await sync(store, hide: yes)
        await loadBoard(store)
    }
}

// MARK: - Home: your rank

struct HomeRankCard: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        let l = store.level
        let next = LevelBadge.of(l.lv + 1)
        HStack(spacing: 14) {
            BadgePatch(badge: l.badge, earned: true, size: 58, fresh: false)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("RANK").font(F.round(11, .heavy)).kerning(1.2).foregroundStyle(C.muted)
                    Spacer()
                    Text("Level \(l.lv)").font(F.round(12, .bold)).foregroundStyle(C.muted)
                }
                Text(l.badge.name).font(F.round(19, .heavy))
                    .foregroundStyle(l.badge.rarity == .common ? C.creme : l.badge.rarity.tint)
                XPBar(progress: l.progress, height: 7)
                Text(next.lv == l.badge.lv ? "\(l.need - l.into) XP to level \(l.lv + 1)" : "\(l.need - l.into) XP to \(next.name)")
                    .font(F.round(12, .semibold)).foregroundStyle(C.muted).monospacedDigit()
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(C.char800)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(C.line, lineWidth: 1)))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Home: the global leaderboard card

struct GlobalBoardCard: View {
    @Environment(AppStore.self) private var store
    @State private var ranks = Ranks.shared
    @State private var team = Team.shared
    // test builds: `-route tab:home:board` opens the full table
    @State private var open = DebugRoute.parts.contains("board")

    var body: some View {
        Button { open = true } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "trophy.fill").font(.system(size: 20, weight: .bold)).foregroundStyle(C.gold)
                        .frame(width: 44, height: 44).background(Circle().fill(C.gold.opacity(0.16)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("GLOBAL LEADERBOARD").font(F.round(11, .heavy)).kerning(1.2).foregroundStyle(C.muted)
                        if !team.signedIn {
                            Text("Sign in to get ranked").font(F.round(17, .bold)).foregroundStyle(C.creme)
                        } else if let r = ranks.rank {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("#\(r)").font(F.round(26, .heavy)).foregroundStyle(C.creme).monospacedDigit()
                                if let p = ranks.topPercent {
                                    Text("Top \(p)%").font(F.round(12, .heavy)).foregroundStyle(C.brandInk)
                                        .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(C.brandHi))
                                }
                            }
                        } else {
                            Text("See where you stand").font(F.round(17, .bold)).foregroundStyle(C.creme)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .heavy)).foregroundStyle(C.muted)
                }
                if !ranks.board.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(ranks.board.prefix(3)) { r in
                            HStack(spacing: 6) {
                                Text("\(r.place)").font(F.round(12, .heavy)).foregroundStyle(r.place == 1 ? C.gold : C.muted)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(r.name).font(F.round(13, .bold)).foregroundStyle(C.creme).lineLimit(1)
                                    Text("\(r.xp.formatted()) XP").font(F.round(11, .semibold)).foregroundStyle(C.muted).lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(C.char850))
                        }
                    }
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(C.char800)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(C.line, lineWidth: 1)))
        }
        .buttonStyle(.plain)
        .task(id: team.signedIn) { await ranks.loadBoard(store) }
        .sheet(isPresented: $open) { LeaderboardView() }
    }
}

// MARK: - the full table

struct LeaderboardView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var ranks = Ranks.shared
    @State private var team = Team.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Disp("LEADERBOARD", size: 30)
                    Spacer()
                    Button("Done") { dismiss() }.font(F.round(16, .bold)).foregroundStyle(C.brandHi)
                }
                .padding(.top, 24)
                Text("Everyone in Soccer Lab, ranked by XP. Earn XP by ticking off drills, finishing sessions, reviewing film, running and logging food.")
                    .font(F.round(14, .semibold)).foregroundStyle(C.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if !team.signedIn {
                    VStack(spacing: 12) {
                        Text("Sign in to join the leaderboard.").font(F.round(15, .semibold)).foregroundStyle(C.creme2)
                        AppleSignIn()
                        if let e = team.error { Text(e).font(F.round(13, .semibold)).foregroundStyle(C.gold) }
                    }
                } else {
                    if let r = ranks.rank, let t = ranks.total {
                        HStack {
                            Text("You're #\(r) of \(t)").font(F.round(17, .bold)).foregroundStyle(C.creme)
                            Spacer()
                            Text("\(store.xp.formatted()) XP").font(F.round(15, .bold)).foregroundStyle(C.gold).monospacedDigit()
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(C.brand.opacity(0.16)))
                    }
                    if ranks.loading && ranks.board.isEmpty { ProgressView().tint(C.brandHi).frame(maxWidth: .infinity) }
                    VStack(spacing: 6) {
                        ForEach(ranks.board) { r in row(r) }
                    }
                    Toggle(isOn: Binding(get: { !ranks.hidden }, set: { on in Task { await ranks.setHidden(!on, store: store) } })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show me on the leaderboard").font(F.round(15, .bold)).foregroundStyle(C.creme)
                            Text("Others see your first name, initial, position and XP.").font(F.round(12, .semibold)).foregroundStyle(C.muted)
                        }
                    }
                    .tint(C.brand)
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .presentationDetents([.large])
        .presentationBackground(C.char900)
        .task { await ranks.loadBoard(store) }
    }

    private func row(_ r: Ranks.Row) -> some View {
        HStack(spacing: 12) {
            Text("\(r.place)").font(F.round(15, .heavy)).monospacedDigit()
                .foregroundStyle(r.place == 1 ? C.gold : r.place <= 3 ? C.creme : C.muted)
                .frame(width: 34, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(r.me ? "\(r.name) (you)" : r.name).font(F.round(15, .bold)).foregroundStyle(C.creme).lineLimit(1)
                if let p = r.pos, !p.isEmpty { Text(p).font(F.round(12, .semibold)).foregroundStyle(C.muted) }
            }
            Spacer(minLength: 0)
            Text("\(r.xp.formatted()) XP").font(F.round(14, .bold)).foregroundStyle(C.creme2).monospacedDigit()
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(r.me ? C.brand.opacity(0.18) : C.char800))
    }
}
