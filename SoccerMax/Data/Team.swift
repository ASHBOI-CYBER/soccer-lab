// TEAM (notes/26, 2026-10-25): the ONLY thing the app keeps on a server (Supabase, project pojdwcgicconsiiinyyi since 2026-11-12).
// A player invites friends with a 6-letter code (a friend's first join = 7 days free, no card), they share one team
// (name + a tiny logo), one FEED that is both the activity log (sessions finished, film watched) and the chat, and two
// small leaderboards (streak, minutes this week). Text only on the server ? no photos or video (the logo is a 128 px
// JPEG kept on the team row, ~6 KB). Everything else in the app stays on the phone.
//
// Accounts = Sign in with Apple (user, 2026-10-25: "make the user sign in with apple, create accounts").
// No SDK: a tiny REST client (Apple ID token ? Supabase session, then PostgREST). The feed is polled while the Team tab is open.
import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import PostHog
import Security
import SwiftUI
import UIKit

enum SupabaseConfig {
    static let url = URL(string: "https://pojdwcgicconsiiinyyi.supabase.co")!
    /// The publishable key is meant to ship in the app; Row Level Security decides what each player can see.
    static let key = "sb_publishable_HPvVa5jQ9raq6fAHbNAGgA_yUOJRv4A"
}

// MARK: - rows

struct TeamRow: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var logo: String?
    var color: Int
    let code: String
    var owner: String?
}

struct MemberRow: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var position: String?
    var streak: Int
    var week_minutes: Int
    var week_start: String?
    var last_active: String?
    var club: String?
    var level: Int?
    /// Bumped when the player changes their picture (pictures download only on a new version).
    var avatar_v: Int?
    /// Kept days (10+ min) for the last 400 days as a hex bitmap ending on `kept_end` ? the team streak reads these.
    var kept: String?
    var kept_end: String?
    /// Minutes count only for the current week (an old week reads 0).
    var minutesThisWeek: Int { week_start == dateKey(dateOf("Mon")) ? week_minutes : 0 }
}

/// What a shared session or film carries, so a teammate can open it without the server storing anything else.
struct PostMeta: Codable, Equatable {
    var title: String?
    var minutes: Int?
    var drills: Int?
    /// [drill id, sets] ? enough to rebuild a session.
    var items: [[String]]?
    var pro: String?
    var home: String?
    var away: String?
    var score: String?
    var league: String?
    /// Free sessions (2026-11-08): the TrainingArea id ? the feed shows its icon, tap = train it too.
    var area: String?
    /// MAP tab (2026-11-08): where the session was played, rounded to ~100 m. Only sent when the player shares spots.
    var lat: Double?
    var lng: Double?
    /// Live sessions (2026-11-08 v2): each category done, in order ? name + icon travel with it so a teammate sees
    /// custom categories too.
    var parts: [SessionPart]?
    /// Photos/videos in the `session-media` bucket (`<uid>/<file>`), shown in the feed.
    var media: [String]?
}

struct Post: Codable, Identifiable, Equatable {
    let id: Int
    let team_id: String
    let user_id: String
    let kind: String
    let body: String?
    let ref: String?
    let meta: PostMeta?
    let created_at: String

    var date: Date { Self.iso.date(from: created_at) ?? Self.isoPlain.date(from: created_at) ?? Date() }
    static let iso: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
    static let isoPlain = ISO8601DateFormatter()
}

/// Something a player can send to the team (or outside the app).
enum Shareable {
    case session(Session)
    case pro(ProSession, level: Int)
    case film(MatchTape)

    var title: String {
        switch self {
        case .session(let s): return s.name
        case .pro(let p, _): return p.title
        case .film(let t): return "\(t.home.name) \(t.score.0)–\(t.score.1) \(t.away.name)"
        }
    }
    var subtitle: String {
        switch self {
        case .session(let s): return s.summary
        case .pro(let p, let lv): return "\(p.items(lv).count) drills · \(p.minutes(lv)) min"
        case .film(let t): return "\(t.fx.league.name) · Matchday film"
        }
    }
    var icon: String { if case .film = self { return "play.rectangle.fill" }; return "figure.soccer" }
    func post() -> (kind: String, ref: String, meta: PostMeta) {
        switch self {
        case .session(let s):
            return ("share_session", s.pro ?? s.id, PostMeta(title: s.name, minutes: s.minutes, drills: s.items.count,
                                                             items: s.items.map { [$0.drill, "\($0.sets)"] }, pro: s.pro))
        case .pro(let p, let lv):
            let items = p.items(lv)
            return ("share_session", p.id, PostMeta(title: p.title, minutes: p.minutes(lv), drills: items.count,
                                                   items: items.map { [$0.drill, "\($0.sets)"] }, pro: p.id))
        case .film(let t):
            return ("share_film", "\(t.id)", Team.filmMeta(t))
        }
    }
}

// MARK: - the store

@Observable
@MainActor
final class Team {
    static let shared = Team()

    private(set) var me: String?
    /// Every team I'm on (MANY TEAMS, 2026-10-27: "allow multiple teams at once"), newest message first in the list.
    private(set) var teams: [TeamRow] = []
    /// The team whose chat is open (nil = the team list).
    var selectedId: String? { didSet { if let selectedId { markSeen(selectedId) } } }
    /// Everyone on any of my teams (one row each, even when they share two teams with me).
    private(set) var people: [MemberRow] = []
    /// team id ? (member id ? the day they joined, "2026-10-25"), for each team's streak grace.
    private(set) var roster: [String: [String: String]] = [:]
    /// team id ? its feed (oldest first).
    private(set) var feeds: [String: [Post]] = [:]
    /// team id ? the last post I've seen there (the list's unread dot).
    private var seen: [String: Int] = (UserDefaults.standard.dictionary(forKey: "sm.team.seen") as? [String: Int]) ?? [:]
    /// True after the first look at the server (so the tab doesn't flash "make a team" before it knows).
    private(set) var loaded = false
    var error: String?
    /// A code from an invite link (soccermax.app/join/123456) or typed on the welcome screen, waiting to be used.
    var pendingCode: String? {
        didSet {
            UserDefaults.standard.set(pendingCode, forKey: "sm.team.pending")
            // it may be a creator's code: tag the RevenueCat customer now, so a purchase made before signing in
            // still counts for the creator (supabase/2026-11-12-creators.sql). A team or gift code matches nobody.
            if let c = pendingCode { Purchases.shared.tagCreator(c) }
        }
    }
    /// The creator (affiliate) whose code this account used: their name, for analytics. One per account.
    private(set) var creatorName: String? = UserDefaults.standard.string(forKey: "sm.creator.name") {
        didSet { UserDefaults.standard.set(creatorName, forKey: "sm.creator.name") }
    }
    /// Free trial from a team invite (server time), mirrored here so the paywall can skip.
    private(set) var trialUntil: Date? { didSet { UserDefaults.standard.set(trialUntil, forKey: "sm.team.trial") } }
    /// The server says this account already had its ONE free week (team, gift or Apple's) ? Purchases.freeWeekUsed.
    private(set) var trialUsed = false { didSet { UserDefaults.standard.set(trialUsed, forKey: "sm.team.trialused") } }
    /// A free LIFETIME code was redeemed on this account (notes/40) ? the server also pushed trialUntil to 2999.
    private(set) var freeForLife = false { didSet { UserDefaults.standard.set(freeForLife, forKey: "sm.team.freelife") } }

    /// Teammates' pictures (96 px), kept on the phone by version: id ? (version, image).
    private(set) var avatars: [String: UIImage] = [:]
    private var avatarV: [String: Int] = [:]

    let api = SupabaseREST()
    private var polling: Task<Void, Never>?

    // the open team (what the chat / streak / leaderboard pages read)
    var team: TeamRow? { teams.first { $0.id == selectedId } }
    var members: [MemberRow] { members(of: selectedId) }
    var feed: [Post] { shown(selectedId.flatMap { feeds[$0] } ?? []) }
    var joined: [String: String] { selectedId.flatMap { roster[$0] } ?? [:] }
    func members(of id: String?) -> [MemberRow] {
        guard let id, let r = roster[id] else { return [] }
        return people.filter { r[$0.id] != nil }
    }
    func team(_ id: String) -> TeamRow? { teams.first { $0.id == id } }
    func lastPost(_ id: String) -> Post? { shown(feeds[id] ?? []).last }
    /// New posts from teammates since I last opened that team.
    func unread(_ id: String) -> Int {
        let s = seen[id] ?? 0
        return shown(feeds[id] ?? []).filter { $0.id > s && $0.user_id != me }.count
    }
    private func markSeen(_ id: String) {
        guard let last = feeds[id]?.last?.id, (seen[id] ?? 0) < last else { return }
        seen[id] = last
        UserDefaults.standard.set(seen, forKey: "sm.team.seen")
    }
    /// The list order: the team with the newest post on top (like Messages).
    var ordered: [TeamRow] {
        teams.sorted { (lastPost($0.id)?.date ?? .distantPast) > (lastPost($1.id)?.date ?? .distantPast) }
    }

    private init() {
        pendingCode = UserDefaults.standard.string(forKey: "sm.team.pending")
        trialUntil = UserDefaults.standard.object(forKey: "sm.team.trial") as? Date
        trialUsed = UserDefaults.standard.bool(forKey: "sm.team.trialused")
        freeForLife = UserDefaults.standard.bool(forKey: "sm.team.freelife")
        if let data = UserDefaults.standard.data(forKey: "sm.team.cache2"), let c = try? JSONDecoder().decode(Cache.self, from: data) {
            teams = c.teams; people = c.people; roster = c.roster; feeds = c.feeds; me = c.me; loaded = !c.teams.isEmpty
        } else if let data = UserDefaults.standard.data(forKey: "sm.team.cache"), let c = try? JSONDecoder().decode(OldCache.self, from: data), let t = c.team {
            // the one-team cache from before 2026-10-27
            teams = [t]; people = c.members; feeds = [t.id: c.feed]; me = c.me
            roster = [t.id: Dictionary(uniqueKeysWithValues: c.members.map { ($0.id, c.joined?[$0.id] ?? "") })]
            loaded = true
        }
        loadAvatars()
        if ["team", "profile", "tab"].contains(DebugRoute.parts.first), DebugRoute.parts.contains("demo") { seedDemo() }
    }

    // MARK: player pictures

    private struct SavedPic: Codable { var v: Int; var b64: String }
    private func loadAvatars() {
        guard let d = UserDefaults.standard.data(forKey: "sm.team.avatars"),
              let all = try? JSONDecoder().decode([String: SavedPic].self, from: d) else { return }
        for (id, p) in all { avatarV[id] = p.v; avatars[id] = Team.logoImage(p.b64) }
    }
    private func saveAvatars(_ new: [String: SavedPic]) {
        var all = (UserDefaults.standard.data(forKey: "sm.team.avatars").flatMap { try? JSONDecoder().decode([String: SavedPic].self, from: $0) }) ?? [:]
        for (k, v) in new { all[k] = v }
        all = all.filter { k, _ in people.contains { $0.id == k } }   // only my teammates'
        UserDefaults.standard.set(try? JSONEncoder().encode(all), forKey: "sm.team.avatars")
    }
    /// Download only the pictures whose version changed (usually none).
    private func pullAvatars() async {
        let stale = people.filter { ($0.avatar_v ?? 0) != (avatarV[$0.id] ?? 0) }
        guard !stale.isEmpty else { return }
        struct Pic: Decodable { let id: String; let avatar: String?; let avatar_v: Int }
        let ids = stale.map(\.id).joined(separator: ",")
        guard let rows: [Pic] = try? await api.get("profiles?select=id,avatar,avatar_v&id=in.(\(ids))") else { return }
        var saved: [String: SavedPic] = [:]
        for r in rows {
            avatarV[r.id] = r.avatar_v
            avatars[r.id] = Team.logoImage(r.avatar)
            saved[r.id] = SavedPic(v: r.avatar_v, b64: r.avatar ?? "")
        }
        saveAvatars(saved)
    }

    /// 96 px square JPEG, base64 (~4 KB) ? a player's whole server picture.
    static func picData(_ img: UIImage?) -> String? {
        guard let img else { return nil }
        let side = min(img.size.width, img.size.height), out: CGFloat = 96
        let f = UIGraphicsImageRendererFormat(); f.scale = 1
        let square = UIGraphicsImageRenderer(size: CGSize(width: out, height: out), format: f).image { _ in
            let k = out / side
            img.draw(in: CGRect(x: -(img.size.width - side) / 2 * k, y: -(img.size.height - side) / 2 * k, width: img.size.width * k, height: img.size.height * k))
        }
        return square.jpegData(compressionQuality: 0.7)?.base64EncodedString()
    }

    /// DEBUG `-route team:demo`: three made-up teams on the phone only (nothing is sent), for screenshots.
    /// `team:demo:chat` / `:streak` / `:board` opens the first team on that page.
    private func seedDemo() {
        me = "me"
        teams = [TeamRow(id: "demo", name: "Hackney Hawks", logo: nil, color: 0, code: "482913", owner: "me"),
                 TeamRow(id: "demo2", name: "Sunday Squad", logo: nil, color: 2, code: "771204", owner: "u7"),
                 TeamRow(id: "demo3", name: "U14 Blues", logo: nil, color: 4, code: "305518", owner: "u9")]
        let mon = dateKey(dateOf("Mon"))
        people = [MemberRow(id: "me", name: "Jack S.", position: "CM", streak: 9, week_minutes: 74, week_start: mon, club: "Hackney Wick FC", level: 7),
                  MemberRow(id: "u2", name: "Maya R.", position: "ST", streak: 14, week_minutes: 52, week_start: mon, club: "Clapton CFC", level: 11),
                  MemberRow(id: "u3", name: "Sam K.", position: "CB", streak: 4, week_minutes: 118, week_start: mon),
                  MemberRow(id: "u4", name: "Leo P.", position: "LW", streak: 2, week_minutes: 20, week_start: mon),
                  MemberRow(id: "u5", name: "Ava T.", position: "GK", streak: 6, week_minutes: 41, week_start: mon),
                  MemberRow(id: "u6", name: "Noah B.", position: "RB", streak: 1, week_minutes: 12, week_start: mon),
                  MemberRow(id: "u7", name: "Dad", position: "CB", streak: 3, week_minutes: 30, week_start: mon),
                  MemberRow(id: "u8", name: "Ollie S.", position: "ST", streak: 5, week_minutes: 44, week_start: mon),
                  MemberRow(id: "u9", name: "Coach Dan", position: "CM", streak: 12, week_minutes: 90, week_start: mon),
                  MemberRow(id: "u10", name: "Zara M.", position: "LB", streak: 8, week_minutes: 61, week_start: mon)]
        // team streak demo: everyone joined 3 weeks ago and has kept it since; Leo last trained 3 days ago (waiting on him)
        let today = Calendar.current.startOfDay(for: Date())
        let runs: [String: [Int]] = ["me": [0, 2, 4, 7, 9, 11, 14, 17, 19], "u2": [1, 3, 5, 8, 10, 12, 15, 18],
                                     "u3": [0, 1, 4, 6, 9, 12, 13, 16, 19], "u4": [3, 5, 8, 11, 14, 17, 20],
                                     "u5": [0, 2, 5, 7, 10, 13, 16, 18], "u6": [1, 4, 6, 9, 12, 15, 17, 20],
                                     "u7": [0, 3, 6], "u8": [1, 2, 5, 8], "u9": [0, 1, 2, 3, 4, 5, 6, 7], "u10": [5, 9]]
        for i in people.indices {
            let days = Set((runs[people[i].id] ?? []).map { dateKey(addDays(today, -$0)) })
            people[i].kept = KeptBits.encode(days, end: today)
            people[i].kept_end = dateKey(today)
        }
        func on(_ ids: [String], _ ago: Int) -> [String: String] { Dictionary(uniqueKeysWithValues: ids.map { ($0, dateKey(addDays(today, -ago))) }) }
        roster = ["demo": on(["me", "u2", "u3", "u4", "u5", "u6"], 21), "demo2": on(["me", "u7", "u8"], 9), "demo3": on(["me", "u9", "u10", "u3"], 30)]
        let now = Date()
        func at(_ minsAgo: Double) -> String { Post.isoPlain.string(from: now.addingTimeInterval(-minsAgo * 60)) }
        let quick = PostMeta(title: "Quick Feet", minutes: 24, drills: 2, items: [["toe-taps", "3"], ["cone-slalom", "4"]])
        let tape = Matchday.shared.tapes.first
        feeds["demo"] = [Post(id: 1, team_id: "demo", user_id: "u3", kind: "join", body: nil, ref: nil, meta: nil, created_at: at(1500)),
                Post(id: 2, team_id: "demo", user_id: "u2", kind: "session", body: nil, ref: nil, meta: quick, created_at: at(190)),
                Post(id: 3, team_id: "demo", user_id: "u2", kind: "chat", body: "who's doing weak foot today?", ref: nil, meta: nil, created_at: at(120)),
                Post(id: 4, team_id: "demo", user_id: "me", kind: "chat", body: "me after school", ref: nil, meta: nil, created_at: at(110)),
                Post(id: 5, team_id: "demo", user_id: "u3", kind: "share_session", body: "this one is brutal", ref: "s-weak-foot",
                     meta: PostMeta(title: "Weak Foot Day", minutes: 31, drills: 3, items: [["foundations", "2"], ["figure-8", "3"], ["weak-foot-laces", "3"]]), created_at: at(60)),
                Post(id: 12, team_id: "demo", user_id: "u5", kind: "session", body: nil, ref: nil,
                     meta: { var m = PostMeta(title: "Shooting + Defending", minutes: 47); m.area = "shooting"
                         m.parts = [SessionPart(area: "shooting", name: "Shooting", icon: "target", seconds: 1800),
                                    SessionPart(area: "defending", name: "Defending", icon: "shield.fill", seconds: 1020)]
                         return m }(), created_at: at(45)),
                Post(id: 6, team_id: "demo", user_id: "u4", kind: "film", body: nil, ref: tape.map { "\($0.id)" },
                     meta: tape.map { var m = Self.filmMeta($0); m.minutes = 6; return m }, created_at: at(30)),
                Post(id: 7, team_id: "demo", user_id: "me", kind: "share_film", body: "watch the 2nd goal", ref: tape.map { "\($0.id)" },
                     meta: tape.map(Self.filmMeta), created_at: at(12))]
        feeds["demo2"] = [Post(id: 8, team_id: "demo2", user_id: "u7", kind: "create", body: nil, ref: nil, meta: nil, created_at: at(13000)),
                          Post(id: 9, team_id: "demo2", user_id: "u8", kind: "chat", body: "park at 10 on sunday?", ref: nil, meta: nil, created_at: at(4)),
                          Post(id: 10, team_id: "demo2", user_id: "u7", kind: "chat", body: "bring the cones", ref: nil, meta: nil, created_at: at(2))]
        feeds["demo3"] = [Post(id: 11, team_id: "demo3", user_id: "u9", kind: "session", body: nil, ref: nil,
                               meta: PostMeta(title: "Match Fit", minutes: 35, drills: 5), created_at: at(2900))]
        seen = ["demo": 7, "demo2": 8, "demo3": 11]
        // map demo: sessions around Hackney (rounded spots, like the real ones)
        let spots: [(String, Double, Double, Int, String?, String, Double)] = [
            ("u2", 51.545, -0.055, 52, nil, "Quick Feet", 190), ("u5", 51.545, -0.055, 35, "shooting", "Shooting", 45),
            ("u3", 51.548, -0.041, 118, "fitness", "Fitness", 600), ("u4", 51.541, -0.062, 12, "juggling", "Juggling", 1400),
            ("u6", 51.552, -0.066, 20, "speed", "Speed", 2600), ("u9", 51.538, -0.047, 90, "game", "Scrimmage", 3000),
            ("u10", 51.551, -0.049, 61, "dribbling", "Dribbling", 4000), ("u8", 51.545, -0.055, 8, "weak-foot", "Weak foot", 5200),
            ("me", 51.543, -0.058, 45, "passing", "Passing", 300), ("me", 51.548, -0.041, 74, "first-touch", "First touch", 2900)]
        spotPosts = spots.enumerated().map { i, s in
            var m = PostMeta(title: s.5, minutes: s.3, drills: s.4 == nil ? 2 : 0, items: s.4 == nil ? [["toe-taps", "3"], ["cone-slalom", "4"]] : nil)
            m.area = s.4; m.lat = s.1; m.lng = s.2
            return Post(id: 100 + i, team_id: "demo", user_id: s.0, kind: "session", body: nil, ref: nil, meta: m, created_at: at(s.6))
        }
        // demo pictures for two teammates (bundled photos, never uploaded)
        for (id, f) in [("u2", "fit-mbappe"), ("u3", "fit-kante")] {
            if let u = Bundle.main.url(forResource: f, withExtension: "jpg", subdirectory: "Players"), let img = UIImage(contentsOfFile: u.path) {
                avatars[id] = Team.logoImage(Self.picData(img))
            }
        }
        if DebugRoute.parts.contains(where: { ["chat", "streak", "board"].contains($0) }) { selectedId = "demo" }
        loaded = true
    }

    private struct Cache: Codable {
        var teams: [TeamRow]; var people: [MemberRow]; var roster: [String: [String: String]]; var feeds: [String: [Post]]; var me: String?
    }
    private struct OldCache: Codable { var team: TeamRow?; var members: [MemberRow]; var feed: [Post]; var me: String?; var joined: [String: String]? }
    private func cache() {
        guard teams.first?.id.hasPrefix("demo") != true else { return }
        let c = Cache(teams: teams, people: people, roster: roster, feeds: feeds.mapValues { Array($0.suffix(80)) }, me: me)
        UserDefaults.standard.set(try? JSONEncoder().encode(c), forKey: "sm.team.cache2")
    }

    /// Signed in with Apple (an account on the server). Nothing team-related works before this.
    var signedIn: Bool { api.hasAccount || debugSignedIn }
    /// DEBUG `-route team:in`: look signed in with no team (the join / make page), nothing sent.
    private let debugSignedIn = DebugRoute.parts.first == "team" && (DebugRoute.parts.contains("in") || DebugRoute.parts.contains("demo"))

    /// Sign in with Apple ? a Supabase account. `nonce` = the raw nonce whose SHA-256 went to Apple.
    func signIn(_ result: Result<ASAuthorization, Error>, nonce: String, store: AppStore) async {
        switch result {
        case .failure(let e):
            if (e as? ASAuthorizationError)?.code != .canceled { error = "Couldn't sign in with Apple. Try again." }
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential, let t = cred.identityToken,
                  let token = String(data: t, encoding: .utf8) else { error = "Couldn't sign in with Apple. Try again."; return }
            do {
                // The raw nonce that matches THIS token (its `nonce` claim = the SHA-256 we sent), not whatever the
                // button's state holds now ? a second tap or a redraw swapped it ? "Nonces mismatch" (2026-10-30).
                try await api.signInWithApple(idToken: token, nonce: Nonce.raw(for: token) ?? nonce)
                identifyUser(try await api.userId())
                UserDefaults.standard.removeObject(forKey: "sm.team.picsent")   // a new account has no picture yet
                if store.answers.first.isEmpty, let given = cred.fullName?.givenName { store.answers.first = given }
                if store.answers.last.isEmpty, let family = cred.fullName?.familyName { store.answers.last = family }
                error = nil
                // a returning player (deleted the app, new phone): their sessions, log and stats come back first
                await Backup.shared.pull(store)
                await refresh(store)
                await Backup.shared.push(store)
                Haptics.play(.goal)
            } catch { self.error = Self.say(error) }
        }
    }

    // MARK: safety ? block, report, delete account (App Store 1.2 + 5.1.1(v), 2026-10-30)

    /// People I blocked: their posts and activity never show on this phone (also saved to the server's `blocks`).
    private(set) var blocked: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "sm.team.blocked") ?? []) {
        didSet { UserDefaults.standard.set(Array(blocked), forKey: "sm.team.blocked") }
    }
    /// Posts I reported: hidden for me straight away.
    private var hidden: Set<Int> = Set(UserDefaults.standard.array(forKey: "sm.team.hidden") as? [Int] ?? []) {
        didSet { UserDefaults.standard.set(Array(hidden), forKey: "sm.team.hidden") }
    }
    // MARK: map (2026-11-08)

    /// Session posts with a spot, from every team I'm on (pulled on their own: the chat feeds only keep the last 60).
    private var spotPosts: [Post] = []
    func pullSpots() async {
        guard !teams.isEmpty, teams.first?.id.hasPrefix("demo") != true else { return }
        if let r: [Post] = try? await api.get("feed?select=*&kind=eq.session&meta-%3E%3Elat=not.is.null&order=id.desc&limit=500") {
            spotPosts = r
        }
    }
    /// Every teammate session with a spot, once each (the same session is posted to each of my teams).
    var mapPosts: [Post] {
        var seen = Set<String>(), out: [Post] = []
        for p in shown(spotPosts + feeds.values.flatMap { $0 }) where p.kind == "session" && p.meta?.lat != nil {
            let k = "\(p.user_id)|\(p.meta?.title ?? "")|\(p.meta?.minutes ?? 0)|\(p.meta?.lat ?? 0),\(p.meta?.lng ?? 0)|\(dateKey(p.date))"
            if seen.insert(k).inserted { out.append(p) }
        }
        return out
    }

    private func shown(_ posts: [Post]) -> [Post] {
        blocked.isEmpty && hidden.isEmpty ? posts : posts.filter { !blocked.contains($0.user_id) && !hidden.contains($0.id) }
    }
    static let reportReasons = ["Bullying or harassment", "Hate speech", "Sexual content", "Violence or threats", "Spam", "Something else"]

    func block(_ id: String) async {
        guard id != me else { return }
        blocked.insert(id)
        PostHogSDK.shared.capture("player_blocked")
        Haptics.play(.latch)
        if api.hasAccount { try? await api.send("POST", "blocks", ["blocked": id], prefer: "resolution=ignore-duplicates,return=minimal") }
    }
    func unblock(_ id: String) async {
        blocked.remove(id)
        if api.hasAccount { try? await api.send("DELETE", "blocks?blocked=eq.\(id)", nil, prefer: "return=minimal") }
    }
    private func pullBlocks() async {
        struct B: Decodable { let blocked: String }
        if let rows: [B] = try? await api.get("blocks?select=blocked") { blocked.formUnion(rows.map(\.blocked)) }
    }
    /// Report a message: it's hidden for me at once, and a copy goes to the developer (`reports`, reviewed within 24 h).
    func report(_ post: Post, reason: String) async -> Bool {
        hidden.insert(post.id)
        PostHogSDK.shared.capture("content_reported", properties: ["what": "message", "reason": reason])
        guard api.hasAccount else { return true }   // the demo team
        do { let _: EmptyReply = try await api.rpc("report_post", ["p_post": post.id, "p_reason": reason]); return true }
        catch { return false }
    }
    func report(player id: String, reason: String) async -> Bool {
        PostHogSDK.shared.capture("content_reported", properties: ["what": "player", "reason": reason])
        guard api.hasAccount else { return true }
        do { let _: EmptyReply = try await api.rpc("report_player", ["p_user": id, "p_reason": reason]); return true }
        catch { return false }
    }
    /// Delete my account for good: the server removes my profile, team spots, posts and backup; then sign out.
    /// Training on this phone stays (it was never part of the account).
    func deleteAccount() async -> Bool {
        do { let _: EmptyReply = try await api.rpc("delete_my_account", [:]) } catch { return false }
        PostHogSDK.shared.capture("account_deleted")
        for k in ["sm.team.cache2", "sm.team.cache", "sm.team.seen", "sm.team.blocked", "sm.team.hidden", "sm.team.picsent"] {
            UserDefaults.standard.removeObject(forKey: k)
        }
        blocked = []; hidden = []
        signOut()
        Haptics.play(.latch)
        return true
    }

    /// A small filter for the worst words (App Store 1.2: a way to stop objectionable posts). Not a full moderator.
    static func allowed(_ text: String) -> Bool {
        let words = text.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
        let bad: Set<String> = ["fuck", "fucking", "fucker", "motherfucker", "cunt", "nigger", "nigga", "faggot", "fag", "retard",
                                "retarded", "slut", "whore", "rape", "kys", "chink", "spic", "kike", "tranny", "dyke"]
        return !words.contains { bad.contains($0) }
    }

    func signOut() {
        PostHogSDK.shared.reset()
        Purchases.shared.signOut()
        api.signOut()
        Backup.shared.reset()
        teams = []; people = []; feeds = [:]; roster = [:]; me = nil; selectedId = nil
        cache()
    }

    var onTrial: Bool { (trialUntil ?? .distantPast) > Date() }
    func member(_ id: String) -> MemberRow? { people.first { $0.id == id } }
    var byStreak: [MemberRow] { members.sorted { ($0.streak, $0.minutesThisWeek, $0.name) > ($1.streak, $1.minutesThisWeek, $1.name) } }
    var byMinutes: [MemberRow] { members.sorted { ($0.minutesThisWeek, $0.streak, $0.name) > ($1.minutesThisWeek, $1.streak, $1.name) } }

    // MARK: loading

    /// Restores PostHog's persisted identity after an existing Keychain session is loaded.
    private func identifyUser(_ userId: String) {
        Purchases.shared.identify(userId)   // RevenueCat: the plan follows the account (notes/39)
        guard PostHogSDK.shared.getDistinctId() != userId else { return }
        PostHogSDK.shared.identify(userId)
    }

    /// Push my stats, then pull my teams (signed in only).
    func refresh(_ store: AppStore) async {
        guard api.hasAccount, teams.first?.id.hasPrefix("demo") != true else { loaded = true; return }
        do {
            let userId = try await api.userId()
            me = userId
            identifyUser(userId)
            try await pushProfile(store)
            // a creator's link was opened before signing in: tie the account to them now, without asking
            if let c = pendingCode, c.count == 6, creatorName == nil { await claimCreator(code: c, quiet: true) }
            await pullBlocks()
            try await pullTeams()
            error = nil
        } catch {
            self.error = Self.say(error)
        }
        loaded = true
    }

    private func pullTeams() async throws {
        teams = try await api.get("teams?select=id,name,logo,color,code,owner")
        if let s = selectedId, team(s) == nil { selectedId = nil }
        guard !teams.isEmpty else { people = []; feeds = [:]; roster = [:]; cache(); return }
        try await pullMembers()
        await pullAvatars()
        var out: [String: [Post]] = [:]
        for t in teams {
            let posts: [Post] = try await api.get("feed?select=*&team_id=eq.\(t.id)&order=id.desc&limit=60")
            out[t.id] = posts.reversed()
        }
        feeds = out
        // a team I've never opened starts read (no wall of dots on first launch)
        for t in teams where seen[t.id] == nil { seen[t.id] = out[t.id]?.last?.id ?? 0 }
        UserDefaults.standard.set(seen, forKey: "sm.team.seen")
        if let s = selectedId { markSeen(s) }
        cache()
    }

    /// Everyone on my teams + when each joined which team. Falls back to the old columns if the server has no `kept`
    /// yet (native/supabase/2026-10-27-team-streak.sql not run).
    private func pullMembers() async throws {
        let cols = "id,name,position,streak,week_minutes,week_start,last_active,club,level,avatar_v"
        if let r: [MemberRow] = try? await api.get("profiles?select=\(cols),kept,kept_end") { people = r }
        else { people = try await api.get("profiles?select=\(cols)") }
        struct J: Decodable { let team_id: String; let user_id: String; let joined_at: String }
        let js: [J] = try await api.get("team_members?select=team_id,user_id,joined_at")
        var out: [String: [String: String]] = [:]
        for j in js {
            out[j.team_id, default: [:]][j.user_id] = (Post.iso.date(from: j.joined_at) ?? Post.isoPlain.date(from: j.joined_at)).map(dateKey) ?? String(j.joined_at.prefix(10))
        }
        roster = out
    }

    /// New posts on any of my teams (cheap: one small request every few seconds while the tab is open).
    func pollNow() async {
        guard !teams.isEmpty, teams.first?.id.hasPrefix("demo") != true else { return }
        let after = feeds.values.compactMap { $0.last?.id }.max() ?? 0
        guard let new: [Post] = try? await api.get("feed?select=*&id=gt.\(after)&order=id.asc&limit=100"), !new.isEmpty else { return }
        for p in new where !(feeds[p.team_id]?.contains { $0.id == p.id } ?? false) { feeds[p.team_id, default: []].append(p) }
        if new.contains(where: { $0.kind == "join" || member($0.user_id) == nil }) || new.contains(where: { team($0.team_id) == nil }) {
            try? await pullTeams()
        }
        if let s = selectedId { markSeen(s) }
        cache()
    }

    func startPolling(_ store: AppStore) {
        polling?.cancel()
        polling = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { return }
                await self.pollNow()
                tick += 1
                if tick % 12 == 0 { await self.refresh(store) }   // the boards, every minute
            }
        }
    }
    func stopPolling() { polling?.cancel(); polling = nil }

    // MARK: me

    func pushProfile(_ store: AppStore) async throws {
        let a = store.answers
        let body: [String: Any] = [
            "id": try await api.userId(),
            "name": String((a.last.isEmpty ? a.firstName : "\(a.firstName) \(a.last.prefix(1)).").prefix(40)),
            "position": a.position,
            "streak": store.air.days,
            "week_minutes": store.minutesThisWeek,
            "week_start": dateKey(dateOf("Mon")),
            "last_active": Post.isoPlain.string(from: Date()),
            "club": store.club.map { String($0.name.prefix(60)) } ?? NSNull(),
            "level": min(999, store.level.lv),
        ]
        // the picture goes up only when it changed (keyed by its bytes), with a new version so teammates re-download once
        let pic = Self.picData(store.avatar)
        let sig = pic.map { "\($0.count)-\($0.stableSeed)" } ?? "none"
        let sentKey = "sm.team.picsent"
        var withPic = body
        let changed = UserDefaults.standard.string(forKey: sentKey) != sig
        if changed {
            withPic["avatar"] = pic ?? NSNull()
            withPic["avatar_v"] = Int(Date().timeIntervalSince1970) - 1_790_000_000
        }
        try await api.send("POST", "profiles?on_conflict=id", withPic, prefer: "resolution=merge-duplicates,return=minimal")
        if changed { UserDefaults.standard.set(sig, forKey: sentKey) }
        // the team streak's days, on their own so an older server (no `kept` column yet) can't block the rest
        let k = store.keptBitmap
        try? await api.send("PATCH", "profiles?id=eq.\(try await api.userId())", ["kept": k.hex, "kept_end": k.end], prefer: "return=minimal")
        await refreshTrial()
    }

    /// trial_until + trial_used from the server (signed in only). Apple's free week used on this phone ? tell the server first.
    func refreshTrial() async {
        guard api.hasAccount, let uid = try? await api.userId() else { return }
        if UserDefaults.standard.bool(forKey: "sm.trial.used"), !trialUsed { await markTrialUsed() }
        struct R: Decodable { let trial_until: String?; let trial_used: Bool?; let free_for_life: Bool? }
        guard let rows: [R] = try? await api.get("profiles?select=trial_until,trial_used,free_for_life&id=eq.\(uid)"), let r = rows.first else { return }
        if let t = r.trial_until { trialUntil = Post.iso.date(from: t) ?? Post.isoPlain.date(from: t) }
        trialUsed = r.trial_used ?? trialUsed
        freeForLife = r.free_for_life ?? freeForLife
    }

    func markTrialUsed() async {
        guard api.hasAccount else { return }
        let _: String? = try? await api.rpc("mark_trial_used", [:])
        trialUsed = true
    }

    /// Your own gift code: friends who type it (or open soccermax.app/join/<it>) get 7 days free, no card ? once per account.
    func myGiftCode() async -> String? {
        guard api.hasAccount else { return nil }
        if let c = UserDefaults.standard.string(forKey: "sm.gift.code") { return c }
        guard let c: String = try? await api.rpc("my_gift_code", [:]) else { return nil }
        UserDefaults.standard.set(c, forKey: "sm.gift.code")
        return c
    }

    /// Use a friend's gift code. true = the free week started, false = this account already had its free week.
    func redeemGift(code: String, store: AppStore) async -> Bool? {
        do {
            _ = try await api.userId()
            try await pushProfile(store)
            struct R: Decodable { let trial_granted: Bool }
            let r: R = try await api.rpc("redeem_gift", ["p_code": code])
            pendingCode = nil
            await refreshTrial()
            error = nil
            return r.trial_granted
        } catch { self.error = Self.say(error); return nil }
    }

    /// Use a free LIFETIME code (notes/40). true = the app is free for life on this account; nil = error (in `error`).
    func redeemLifetime(code: String, store: AppStore) async -> Bool? {
        do {
            _ = try await api.userId()
            try await pushProfile(store)
            struct R: Decodable { let lifetime: Bool; let error: String? }
            let r: R = try await api.rpc("redeem_lifetime", ["p_code": code])
            guard r.lifetime else { error = r.error ?? "That code doesn't work."; return nil }
            pendingCode = nil
            freeForLife = true
            trialUntil = Date(timeIntervalSince1970: 32_503_680_000)   // 2999 until the server answers
            await refreshTrial()
            PostHogSDK.shared.capture("lifetime_code_redeemed", properties: ["code": code])
            error = nil
            return true
        } catch { self.error = Self.say(error); return nil }
    }

    /// Use a creator's code: this account's purchases now count for that creator. true = tied (now or already).
    /// `quiet` = the code came from a link and may be a team code, so a "no" says nothing and keeps the code waiting.
    @discardableResult
    func claimCreator(code: String, quiet: Bool = false) async -> Bool {
        do {
            _ = try await api.userId()
            struct R: Decodable { let ok: Bool; let name: String?; let error: String? }
            let r: R = try await api.rpc("claim_creator", ["p_code": code])
            guard r.ok else {
                if !quiet { error = r.error ?? "That code doesn't work." }
                return false
            }
            if pendingCode == code { pendingCode = nil }
            creatorName = r.name ?? creatorName
            Purchases.shared.tagCreator(code)
            PostHogSDK.shared.capture("creator_code_used", properties: ["code": code, "from_link": quiet])
            if !quiet { error = nil }
            return true
        } catch {
            if !quiet { self.error = Self.say(error) }
            return false
        }
    }

    /// Use a launch-list 40% OFF code (the waitlist email, 2026-11-01). true = the 40% plans can open; nil = error.
    func redeemOff40(code: String, store: AppStore) async -> Bool? {
        do {
            _ = try await api.userId()
            try await pushProfile(store)
            struct R: Decodable { let ok: Bool; let error: String? }
            let r: R = try await api.rpc("redeem_off40", ["p_code": code])
            guard r.ok else { error = r.error ?? "That code doesn't work."; return nil }
            pendingCode = nil
            PostHogSDK.shared.capture("off40_code_redeemed")
            error = nil
            return true
        } catch { self.error = Self.say(error); return nil }
    }

    // MARK: team

    /// Make a team; it opens straight away.
    func create(name: String, logo: UIImage?, color: Int, store: AppStore) async -> Bool {
        do {
            _ = try await api.userId()
            try await pushProfile(store)
            let made: TeamRow = try await api.rpc("create_team", ["p_name": name, "p_logo": Self.logoData(logo) as Any, "p_color": color])
            try await pullTeams()
            selectedId = made.id
            PostHogSDK.shared.capture("team_created")
            error = nil
            return true
        } catch { self.error = Self.say(error); return false }
    }

    /// Join by code; the team opens. Returns true if this started the 7-day trial.
    @discardableResult
    func join(code: String, store: AppStore) async -> Bool? {
        do {
            _ = try await api.userId()
            try await pushProfile(store)
            struct R: Decodable { let team_id: String?; let trial_granted: Bool }
            let r: R = try await api.rpc("join_team", ["p_code": code])
            pendingCode = nil
            try await pushProfile(store)          // picks up trial_until
            try await pullTeams()
            if let id = r.team_id, team(id) != nil { selectedId = id }
            PostHogSDK.shared.capture("team_joined", properties: ["trial_granted": r.trial_granted])
            error = nil
            return r.trial_granted
        } catch { self.error = Self.say(error); return nil }
    }

    /// What a code opens: a team, or (gift = true) a friend's free week ? `name` is then the friend's first name.
    struct Preview: Decodable {
        let name: String; let logo: String?; let color: Int; let members: Int
        var gift: Bool? = nil
        var lifetime: Bool? = nil
        /// A launch-list 40% OFF code (2026-11-01, supabase/2026-11-01-waitlist-codes.sql).
        var off40: Bool? = nil
        var isGift: Bool { gift == true }
        var isLifetime: Bool { lifetime == true }
        var isOff40: Bool { off40 == true }
        /// A content creator's code (2026-11-12, supabase/2026-11-12-creators.sql): `name` is the creator's name.
        var creator: Bool? = nil
        var isCreator: Bool { creator == true }
    }
    func preview(code: String) async -> Preview? {
        if debugSignedIn, !api.hasAccount { return Preview(name: "Hackney Hawks", logo: nil, color: 0, members: 6) }
        guard signedIn, (try? await api.userId()) != nil else { return nil }
        let rows: [Preview]? = try? await api.rpc("team_preview", ["p_code": code])
        if let t = rows?.first { return t }
        struct G: Decodable { let name: String }
        let g: [G]? = try? await api.rpc("gift_preview", ["p_code": code])
        if let g = g?.first { return Preview(name: g.name, logo: nil, color: 0, members: 0, gift: true) }
        // null (not a creator's code) fails to decode as a String, so `try?` gives nil
        if let name: String = try? await api.rpc("creator_preview", ["p_code": code]), !name.isEmpty {
            return Preview(name: name, logo: nil, color: 0, members: 0, creator: true)
        }
        let life: Bool? = try? await api.rpc("lifetime_preview", ["p_code": code])
        if life == true { return Preview(name: "", logo: nil, color: 0, members: 0, lifetime: true) }
        let off: Bool? = try? await api.rpc("off40_preview", ["p_code": code])
        return off == true ? Preview(name: "", logo: nil, color: 0, members: 0, off40: true) : nil
    }

    /// Leave the open team (the others stay).
    func leave() async {
        guard let t = team else { return }
        do {
            do { let _: EmptyReply = try await api.rpc("leave_team", ["p_team": t.id]) }
            catch { let _: EmptyReply = try await api.rpc("leave_team", [:]) }   // a server from before many teams
            selectedId = nil
            teams.removeAll { $0.id == t.id }
            feeds[t.id] = nil; roster[t.id] = nil
            cache()
            try? await pullTeams()
        } catch { self.error = Self.say(error) }
    }

    func edit(name: String? = nil, logo: UIImage?? = nil, color: Int? = nil) async {
        guard let team else { return }
        var body: [String: Any] = [:]
        if let name { body["name"] = name }
        if let logo { body["logo"] = Self.logoData(logo) ?? NSNull() }
        if let color { body["color"] = color }
        do {
            try await api.send("PATCH", "teams?id=eq.\(team.id)", body, prefer: "return=minimal")
            try await pullTeams()
        } catch { self.error = Self.say(error) }
    }

    // MARK: posting

    /// A chat message to the open team.
    func send(chat text: String) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let id = selectedId else { return }
        guard Self.allowed(t) else { error = "That message has words we don't allow in team chat."; return }
        await post(to: id, kind: "chat", body: String(t.prefix(500)))
    }

    func share(_ item: Shareable, note: String?, to id: String) async -> Bool {
        let p = item.post()
        let n = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let n, !Self.allowed(n) { error = "That message has words we don't allow in team chat."; return false }
        return await post(to: id, kind: p.kind, body: n?.isEmpty == false ? String(n!.prefix(500)) : nil, ref: p.ref, meta: p.meta)
    }

    /// Activity, logged on its own to EVERY team I'm on: a finished session, film watched. Silent with no team / no signal.
    func log(session name: String, minutes: Int, items: [PlanItem], pro: String?, area: String? = nil,
             parts: [SessionPart]? = nil, media: [String] = []) {
        guard !teams.isEmpty, minutes >= 1 else { return }
        var meta = PostMeta(title: name, minutes: minutes, drills: items.count, items: items.map { [$0.drill, "\($0.sets)"] }, pro: pro)
        meta.area = area
        meta.parts = parts
        if SessionSpot.shared.onMap, let s = SessionSpot.shared.here { meta.lat = s.lat; meta.lng = s.lng }
        Task {
            // photos/videos go up first (one copy, readable by every team I'm on), then the post points at them
            var paths: [String] = []
            for m in media { if let p = await SessionMedia.upload(m, api: api) { paths.append(p) } }
            if !paths.isEmpty { meta.media = paths }
            for t in teams { await post(to: t.id, kind: "session", body: nil, ref: pro, meta: meta, quiet: true) }
        }
    }
    func log(film tape: MatchTape, minutes: Double) {
        guard !teams.isEmpty, minutes >= 1 else { return }
        var m = Self.filmMeta(tape)
        m.minutes = Int(minutes.rounded())
        Task { for t in teams { await post(to: t.id, kind: "film", body: nil, ref: "\(tape.id)", meta: m, quiet: true) } }
    }
    /// After training: the boards should show it.
    func syncStats(_ store: AppStore) {
        guard !teams.isEmpty else { return }
        Task { try? await pushProfile(store); await pollNow() }
    }

    @discardableResult
    private func post(to id: String, kind: String, body: String?, ref: String? = nil, meta: PostMeta? = nil, quiet: Bool = false) async -> Bool {
        guard let me = try? await api.userId() else { return false }
        var row: [String: Any] = ["team_id": id, "user_id": me, "kind": kind]
        if let body { row["body"] = body }
        if let ref { row["ref"] = ref }
        if let meta, let d = try? JSONEncoder().encode(meta), let j = try? JSONSerialization.jsonObject(with: d) { row["meta"] = j }
        do {
            let made: [Post] = try await api.sendReturning("POST", "feed", row)
            for p in made where !(feeds[id]?.contains { $0.id == p.id } ?? false) { feeds[id, default: []].append(p) }
            if selectedId == id { markSeen(id) }
            cache()
            if kind == "chat" {
                PostHogSDK.shared.capture("team_chat_sent")
            } else if kind == "share_session" || kind == "share_film" {
                PostHogSDK.shared.capture("team_content_shared", properties: [
                    "content_type": kind == "share_session" ? "session" : "film"
                ])
                PostHogSDK.shared.capture("share_completed", properties: [
                    "kind": kind == "share_session" ? "session" : "film", "destination": "Team chat", "destination_id": "team",
                ])
            }
            error = nil
            return true
        } catch { if !quiet { self.error = Self.say(error) }; return false }
    }

    func delete(_ post: Post) async {
        do {
            try await api.send("DELETE", "feed?id=eq.\(post.id)", nil, prefer: "return=minimal")
            feeds[post.team_id]?.removeAll { $0.id == post.id }
            cache()
        } catch { self.error = Self.say(error) }
    }

    // MARK: helpers

    nonisolated static func filmMeta(_ t: MatchTape) -> PostMeta {
        PostMeta(title: "\(t.home.name) v \(t.away.name)", home: t.home.logo, away: t.away.logo, score: "\(t.score.0)–\(t.score.1)", league: t.fx.league.name)
    }

    /// 128 px square JPEG, base64 ? about 6 KB. That's the whole cost of a team picture.
    static func logoData(_ img: UIImage?) -> String? {
        guard let img else { return nil }
        let side = min(img.size.width, img.size.height), out: CGFloat = 128
        let f = UIGraphicsImageRendererFormat(); f.scale = 1
        let square = UIGraphicsImageRenderer(size: CGSize(width: out, height: out), format: f).image { _ in
            let k = out / side
            img.draw(in: CGRect(x: -(img.size.width - side) / 2 * k, y: -(img.size.height - side) / 2 * k, width: img.size.width * k, height: img.size.height * k))
        }
        return square.jpegData(compressionQuality: 0.7)?.base64EncodedString()
    }
    static func logoImage(_ b64: String?) -> UIImage? {
        guard let b64, let d = Data(base64Encoded: b64) else { return nil }
        return UIImage(data: d)
    }

    static func say(_ e: Error) -> String {
        if let e = e as? SupabaseError { return e.message }
        if (e as NSError).domain == NSURLErrorDomain { return "No connection. Try again." }
        return "Something went wrong. Try again."
    }

    /// soccermax://join/123456 or https://soccermax.app/join/123456 (the invite page, ShareLinks)
    static func code(from url: URL) -> String? {
        let app = url.scheme == "soccermax"
        guard app || url.host?.hasSuffix("soccermax.app") == true else { return nil }
        let parts = ([app ? url.host ?? "" : ""] + url.pathComponents).filter { $0 != "/" && !$0.isEmpty }
        guard parts.first == "join", let c = parts[safe: 1] else { return nil }
        return clean(c)
    }
    static func clean(_ s: String) -> String { String(s.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6)) }

    /// The team's colours (picked when it's made): the crest behind the initials when there's no logo.
    static let colors: [UInt32] = [0x3EC25A, 0xFFC531, 0x3B82F6, 0xE5484D, 0x9B5DE5, 0xF6F1E6, 0x14B8A6, 0xF97316]
}

// MARK: - the TEAM STREAK (2026-10-27, user: "a team streak for each team where everyone has to train for at least
// 10 minutes every 3 days"). Same rule as your own streak (AirStreak.keep / .window), but EVERY player has to keep it.
// Worked out on the phone from each player's kept-days bitmap + the day they joined (a new player counts as kept on
// their join day, so joining never breaks the team). It counts from the first real 10-minute day in the run.

struct TeamStreak {
    var days = 0
    var deadline: Date?                 // the first player's fire runs out here ? the team's does too
    /// player id ? their own deadline for the team (midnight after their last kept day + the window)
    var due: [String: Date] = [:]
    var alive: Bool { days > 0 }
    /// 1 = everyone just trained, 0 = out.
    func air(_ now: Date = Date()) -> Double {
        guard let deadline, alive else { return 0 }
        return max(0, min(1, deadline.timeIntervalSince(now) / Double(AirStreak.window * 86_400)))
    }
    /// Players who haven't trained today and run out within 24 h: they're the ones the team is waiting on.
    func waitingOn(_ now: Date = Date()) -> [String] {
        due.filter { $0.value.timeIntervalSince(now) <= 86_400 }.sorted { $0.value < $1.value }.map(\.key)
    }
}

/// Kept days as a hex bitmap: bit i (left to right, 4 per char) = `end` minus i days. 400 days ? 100 chars.
enum KeptBits {
    static let span = 400
    static func encode(_ days: Set<String>, end: Date) -> String {
        var nib = [Int](repeating: 0, count: span / 4)
        for i in 0..<span where days.contains(dateKey(addDays(end, -i))) { nib[i / 4] |= 8 >> (i % 4) }
        return nib.map { String($0, radix: 16) }.joined()
    }
    static func decode(_ hex: String?, end: String?) -> Set<String> {
        guard let hex, let end = end.flatMap(keyDate) else { return [] }
        var out = Set<String>()
        for (c, ch) in hex.enumerated() {
            guard let v = Int(String(ch), radix: 16), v > 0 else { continue }
            for b in 0..<4 where v & (8 >> b) != 0 { out.insert(dateKey(addDays(end, -(c * 4 + b)))) }
        }
        return out
    }
}

extension AppStore {
    /// My kept days for the server (last 400 days, ending today).
    var keptBitmap: (hex: String, end: String) {
        let today = Calendar.current.startOfDay(for: Date())
        return (KeptBits.encode(Set(keptDays.map(dateKey)), end: today), dateKey(today))
    }
}

extension Team {
    /// A team's streak right now (the open team when `id` is nil). `store` = my own days (fresher than the server's copy).
    func streak(_ store: AppStore, team id: String? = nil, now: Date = Date()) -> TeamStreak {
        var out = TeamStreak()
        let tid = id ?? selectedId
        let members = members(of: tid), joined = tid.flatMap { roster[$0] } ?? [:]
        guard !members.isEmpty else { return out }
        let cal = Calendar.current, today = cal.startOfDay(for: now), w = AirStreak.window
        // each player as day numbers counted back from today (0 = today, 1 = yesterday?)
        struct P { let id: String; let kept: [Int]; let join: Int }
        let players: [P] = members.map { m in
            let real = m.id == me && !store.keptDays.isEmpty ? Set(store.keptDays.map(dateKey)) : KeptBits.decode(m.kept, end: m.kept_end)
            let join = joined[m.id].flatMap(keyDate).map { daysBetween($0, today) } ?? 0
            return P(id: m.id, kept: real.compactMap(keyDate).map { daysBetween($0, today) }.filter { $0 >= 0 }.sorted(), join: max(0, join))
        }
        // alive on day `back` = joined later, or a kept day (or the join day) within the window before it
        func ok(_ p: P, _ back: Int) -> Bool {
            if back > p.join { return true }
            if p.join <= back + w { return true }
            return p.kept.contains { $0 >= back && $0 <= back + w }
        }
        guard players.allSatisfy({ ok($0, 0) }) else { return out }
        let oldest = players.map(\.join).max() ?? 0          // the first join = the team's first day
        var start = 0
        while start + 1 <= min(oldest, KeptBits.span) && players.allSatisfy({ ok($0, start + 1) }) { start += 1 }
        // count from the first real 10-minute day inside the run (joining alone doesn't light it)
        guard let first = players.flatMap({ $0.kept.filter { $0 <= start } }).max() else { return out }
        out.days = first + 1
        for p in players {
            let last = min(p.kept.first ?? Int.max, p.join)          // most recent kept day (or join day)
            out.due[p.id] = addDays(today, w + 1 - last)
        }
        out.deadline = out.due.values.min()
        return out
    }
}

// MARK: - REST

struct SupabaseError: Error { let message: String }
struct EmptyReply: Decodable { init(from decoder: Decoder) throws {} }

/// Sign in with Apple + PostgREST over URLSession. The session lives in the Keychain (same account after a reinstall).
/// @Observable (2026-10-30): `Team.signedIn` reads `hasAccount` ? `session`; without this SwiftUI never saw the
/// sign-in, so CONTINUE WITH APPLE on the account page signed you in but never took you into the app.
@Observable
@MainActor
final class SupabaseREST {
    private struct Session: Codable { var access: String; var refresh: String; var expires: Date; var user: String }
    private var session: Session? = Keychain.read("sm.supabase.session").flatMap { try? JSONDecoder().decode(Session.self, from: $0) }
    @ObservationIgnored private var refreshing: Task<Session, Error>?

    var hasAccount: Bool { session != nil }

    func userId() async throws -> String { try await token().user }

    func signInWithApple(idToken: String, nonce: String) async throws {
        store(try await auth("token?grant_type=id_token", ["provider": "apple", "id_token": idToken, "nonce": nonce]))
    }
    func signOut() {
        session = nil
        Keychain.delete("sm.supabase.session")
    }
    private func store(_ s: Session) {
        session = s
        Keychain.write("sm.supabase.session", (try? JSONEncoder().encode(s)) ?? Data())
    }

    private func token() async throws -> Session {
        guard let s = session else { throw SupabaseError(message: "Sign in with Apple first.") }
        if s.expires > Date().addingTimeInterval(60) { return s }
        if let t = refreshing { return try await t.value }
        let t = Task { try await auth("token?grant_type=refresh_token", ["refresh_token": s.refresh]) }
        refreshing = t
        defer { refreshing = nil }
        do {
            let fresh = try await t.value
            store(fresh)
            return fresh
        } catch let e as SupabaseError {
            signOut()          // the refresh token is dead: sign in again
            throw e
        }
    }

    private func auth(_ path: String, _ body: [String: Any]) async throws -> Session {
        var r = URLRequest(url: URL(string: "auth/v1/\(path)", relativeTo: SupabaseConfig.url)!)
        r.httpMethod = "POST"
        r.setValue(SupabaseConfig.key, forHTTPHeaderField: "apikey")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: r)
        struct A: Decodable { let access_token: String; let refresh_token: String; let expires_in: Double; struct U: Decodable { let id: String }; let user: U }
        guard (resp as? HTTPURLResponse)?.statusCode == 200, let a = try? JSONDecoder().decode(A.self, from: data) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            if msg.contains("provider_disabled") || msg.contains("is not enabled") || msg.contains("Unsupported provider") { throw SupabaseError(message: "Teams aren't switched on yet.") }
            throw SupabaseError(message: "Couldn't sign in. Try again.")
        }
        return Session(access: a.access_token, refresh: a.refresh_token, expires: Date().addingTimeInterval(a.expires_in), user: a.user.id)
    }

    private func request(_ method: String, _ path: String, _ body: Any?, prefer: String? = nil) async throws -> Data {
        let s = try await token()
        var r = URLRequest(url: URL(string: "rest/v1/\(path)", relativeTo: SupabaseConfig.url)!)
        r.httpMethod = method
        r.timeoutInterval = 15
        r.setValue(SupabaseConfig.key, forHTTPHeaderField: "apikey")
        r.setValue("Bearer \(s.access)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { r.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let body { r.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, resp) = try await URLSession.shared.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            if code == 401 { session?.expires = .distantPast }
            struct E: Decodable { let message: String? }
            let m = (try? JSONDecoder().decode(E.self, from: data))?.message ?? ""
            throw SupabaseError(message: Self.friendly(m))
        }
        return data
    }

    private static func friendly(_ m: String) -> String {
        let known = ["no team with that code": "No team has that code.", "no gift with that code": "No team or gift has that code.",
                     "your own code": "That's your own gift code — send it to a friend.", "already on a team": "You're already on a team.",
                     "leave your team first": "Leave your team first.", "too many teams": "You're on 10 teams — leave one first.", "team is full": "That team is full (30 players).",
                     "slow down": "Slow down — a few posts a minute.", "check constraint": "That's too long."]
        return known.first { m.contains($0.key) }?.value ?? "Something went wrong. Try again."
    }

    // MARK: session media (Storage bucket `session-media`, private ? owner + teammates read; supabase/2026-11-08-session-media.sql)

    /// Upload one file to `session-media/<my uid>/<name>`. Returns the stored path.
    func uploadMedia(_ file: URL, name: String, mime: String) async throws -> String {
        let s = try await token()
        let path = "\(s.user)/\(name)"
        var r = URLRequest(url: URL(string: "storage/v1/object/session-media/\(path)", relativeTo: SupabaseConfig.url)!)
        r.httpMethod = "POST"
        r.timeoutInterval = 120
        r.setValue(SupabaseConfig.key, forHTTPHeaderField: "apikey")
        r.setValue("Bearer \(s.access)", forHTTPHeaderField: "Authorization")
        r.setValue(mime, forHTTPHeaderField: "Content-Type")
        let (_, resp) = try await URLSession.shared.upload(for: r, fromFile: file)
        guard (200..<300).contains((resp as? HTTPURLResponse)?.statusCode ?? 0) else { throw SupabaseError(message: "Upload failed.") }
        return path
    }
    /// Download a teammate's (or my) file to the cache folder; returns the local file (cached after the first time).
    func mediaFile(_ path: String) async throws -> URL {
        let dir = URL.cachesDirectory.appending(path: "TeamMedia", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let local = dir.appending(path: path.replacingOccurrences(of: "/", with: "_"))
        if FileManager.default.fileExists(atPath: local.path) { return local }
        let s = try await token()
        var r = URLRequest(url: URL(string: "storage/v1/object/authenticated/session-media/\(path)", relativeTo: SupabaseConfig.url)!)
        r.timeoutInterval = 120
        r.setValue(SupabaseConfig.key, forHTTPHeaderField: "apikey")
        r.setValue("Bearer \(s.access)", forHTTPHeaderField: "Authorization")
        let (tmp, resp) = try await URLSession.shared.download(for: r)
        guard (200..<300).contains((resp as? HTTPURLResponse)?.statusCode ?? 0) else { throw SupabaseError(message: "Couldn't load it.") }
        try? FileManager.default.removeItem(at: local)
        try FileManager.default.moveItem(at: tmp, to: local)
        return local
    }

    /// The raw JSON (Backup reads a free-form blob).
    func raw(_ path: String) async throws -> Data { try await request("GET", path, nil) }
    func get<T: Decodable>(_ path: String) async throws -> T {
        try JSONDecoder().decode(T.self, from: try await request("GET", path, nil))
    }
    func send(_ method: String, _ path: String, _ body: Any?, prefer: String) async throws {
        _ = try await request(method, path, body, prefer: prefer)
    }
    func sendReturning<T: Decodable>(_ method: String, _ path: String, _ body: Any) async throws -> T {
        try JSONDecoder().decode(T.self, from: try await request(method, path, body, prefer: "return=representation"))
    }
    func rpc<T: Decodable>(_ fn: String, _ args: [String: Any]) async throws -> T {
        let d = try await request("POST", "rpc/\(fn)", args)
        if T.self == EmptyReply.self { return try JSONDecoder().decode(T.self, from: Data("{}".utf8)) }
        return try JSONDecoder().decode(T.self, from: d)
    }
}

/// Sign in with Apple's nonce: Apple gets the SHA-256, Supabase gets the raw one.
/// Every nonce made is remembered by its hash, so the completion can find the exact one Apple signed even if the
/// button asked for another in between (double tap, several sign-in buttons alive, a redraw).
enum Nonce {
    @MainActor private static var issued: [String: String] = [:]
    @MainActor static func make() -> String {
        let abc = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        let raw = String((0..<32).map { _ in abc[Int.random(in: 0..<abc.count)] })
        issued[sha256(raw)] = raw
        return raw
    }
    /// The raw nonce whose hash is in this Apple ID token's `nonce` claim.
    @MainActor static func raw(for idToken: String) -> String? {
        let parts = idToken.split(separator: ".")
        guard parts.count > 1 else { return nil }
        var b64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hash = json["nonce"] as? String else { return nil }
        return issued[hash]
    }
    static func sha256(_ s: String) -> String { SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined() }
}

enum Keychain {
    static func delete(_ key: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key] as CFDictionary)
    }
    static func read(_ key: String) -> Data? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
    }
    static func write(_ key: String, _ data: Data) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
        var add = q
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}
