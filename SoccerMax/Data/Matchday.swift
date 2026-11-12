// Matchday (notes/22): real matches from API-Football (v3.football.api-sports.io), taught as film-room classes.
// The free plan gives 100 calls a day, 10 a minute, and ONLY today ? +2 days (no yesterday, no season stats),
// so the app keeps every finished match it pulls on disk, and a pull costs 1 call (today's fixtures) + 1 per match
// (`fixtures?id=` returns events, lineups, team stats and every player's ratings in one call).
// Bundled: Resources/Matchday/<id>.json (real matches from 2026-10-23) so a fresh install always has tapes.
import Foundation
import Observation
import SwiftUI
import UIKit

// MARK: - API shapes (only what we use; every number is Flex because the API mixes 7, "7", "70%" and null)

struct Flex: Codable, Hashable {
    let v: Double?
    init(from d: Decoder) throws {
        let c = try d.singleValueContainer()
        if c.decodeNil() { v = nil }
        else if let n = try? c.decode(Double.self) { v = n }
        else if let s = try? c.decode(String.self) { v = Double(s.replacingOccurrences(of: "%", with: "")) }
        else { v = nil }
    }
    func encode(to e: Encoder) throws { var c = e.singleValueContainer(); try c.encode(v) }
}

struct Fixture: Codable, Identifiable {
    struct Info: Codable { let id: Int; let date: String; let timestamp: Int; let status: Status; let venue: Venue? }
    struct Status: Codable { let short: String; let elapsed: Int? }
    struct Venue: Codable { let name: String?; let city: String? }
    struct League: Codable { let id: Int; let name: String; let country: String?; let logo: String?; let round: String? }
    struct Team: Codable { let id: Int; let name: String; let logo: String }
    struct Teams: Codable { let home: Team; let away: Team }
    struct Goals: Codable { let home: Int?; let away: Int? }
    struct Ref: Codable { let id: Int?; let name: String? }
    struct Event: Codable {
        struct Time: Codable { let elapsed: Int; let extra: Int? }
        let time: Time; let team: Ref; let player: Ref; let assist: Ref; let type: String; let detail: String
        /// why (cards: "Foul", "Dissent", "Violent Conduct", "Handball", "Time Wasting", "Not Retreating"?)
        let comments: String?
    }
    struct Lineup: Codable {
        struct Slot: Codable { let player: P }
        struct P: Codable { let id: Int?; let name: String; let number: Int?; let pos: String?; let grid: String? }
        let team: Ref; let formation: String?; let startXI: [Slot]; let substitutes: [Slot]
    }
    struct TeamStats: Codable {
        struct S: Codable { let type: String; let value: Flex }
        let team: Ref; let statistics: [S]
    }
    struct TeamPlayers: Codable {
        struct Line: Codable { let player: PI; let statistics: [PS] }
        struct PI: Codable { let id: Int; let name: String; let photo: String? }
        struct PS: Codable {
            struct Games: Codable { let minutes: Flex?; let position: String?; let rating: Flex? }
            struct Shots: Codable { let total: Flex?; let on: Flex? }
            struct Goals: Codable { let total: Flex?; let assists: Flex?; let saves: Flex? }
            struct Passes: Codable { let total: Flex?; let key: Flex?; let accuracy: Flex? }
            struct Tackles: Codable { let total: Flex?; let blocks: Flex?; let interceptions: Flex? }
            struct Duels: Codable { let total: Flex?; let won: Flex? }
            struct Dribbles: Codable { let attempts: Flex?; let success: Flex? }
            struct Pen: Codable { let saved: Flex?; let missed: Flex? }
            let games: Games?; let shots: Shots?; let goals: Goals?; let passes: Passes?; let tackles: Tackles?
            let duels: Duels?; let dribbles: Dribbles?; let penalty: Pen?
        }
        let team: Ref; let players: [Line]
    }
    let fixture: Info
    let league: League
    let teams: Teams
    let goals: Goals
    let events: [Event]?
    let lineups: [Lineup]?
    let statistics: [TeamStats]?
    let players: [TeamPlayers]?
    var id: Int { fixture.id }
}

// MARK: - the game's view of a match

enum Side: String, Codable { case home, away
    var other: Side { self == .home ? .away : .home }
}

struct Person: Identifiable, Hashable {
    let id: Int
    var name: String
    let side: Side
    var number: Int?
    var pos: String?          // G D M F
    var grid: String?         // formation slot (subs inherit the slot of the man they replaced)
    var starter = false
    var rating: Double?
    var minutes = 0
    var stats: [String: Double] = [:]
    var photo: URL? { URL(string: "https://media.api-sports.io/football/players/\(id).png") }
    /// "Joe Scally" ? "Scally"; the API's short "J. Scally" ? "Scally".
    var short: String { name.components(separatedBy: " ").last ?? name }
}

struct Moment: Identifiable, Hashable {
    enum Kind: Hashable { case goal, penalty, ownGoal, missedPen, savedPen, varNoGoal, red, yellow }
    let id: Int
    let kind: Kind
    let side: Side           // goals: the team it counts for; misses/VAR/red: the player's team
    let elapsed: Int
    let extra: Int?
    let player: Person?
    let assist: Person?
    var reason: String? = nil  // cards: the data's reason (event comments)
    var minute: String { extra.map { "\(elapsed)+\($0)'" } ?? "\(elapsed)'" }
    var key: Int { elapsed * 100 + (extra ?? 0) }
    var counts: Bool { kind == .goal || kind == .penalty || kind == .ownGoal }
}

struct TeamStat { let name: String; let home: Double; let away: Double }

struct MatchTape: Identifiable {
    let fx: Fixture
    let moments: [Moment]          // in order: goals, missed pens, VAR'd goals, reds
    let cards: [(key: Int, side: Side, red: Bool)]
    let people: [Int: Person]
    let stats: [String: TeamStat]
    var id: Int { fx.id }
    var home: Fixture.Team { fx.teams.home }
    var away: Fixture.Team { fx.teams.away }
    func team(_ s: Side) -> Fixture.Team { s == .home ? home : away }
    var score: (Int, Int) { (fx.goals.home ?? 0, fx.goals.away ?? 0) }
    var goals: Int { score.0 + score.1 }
    var date: Date { Date(timeIntervalSince1970: TimeInterval(fx.fixture.timestamp)) }
    var dayKey: String { dateKey(date) }
    var length: Int { max(90, (moments.last?.elapsed ?? 90)) }
    func grids(_ s: Side) -> [String] {
        people.values.filter { $0.side == s && $0.starter }.compactMap(\.grid).sorted()
    }

    /// How much a match is worth playing: goals, a close finish, a big league, late drama.
    var rank: Double {
        let league = Matchday.leaguePriority[fx.league.id].map { 6 - Double($0) * 0.25 } ?? 0
        let close = abs(score.0 - score.1) <= 1 ? 1.5 : 0
        let late = moments.contains { $0.counts && $0.elapsed >= 80 } ? 1 : 0
        return Double(goals) * 1.2 + max(0, league) + close + Double(late) + Double(moments.filter { $0.kind == .missedPen || $0.kind == .savedPen || $0.kind == .varNoGoal }.count)
    }

    /// Who was on the pitch for `side` at a moment (for the "who scored?" decoys).
    func onPitch(_ side: Side, at key: Int) -> [Person] {
        var ids = Set(people.values.filter { $0.side == side && $0.starter }.map(\.id))
        for e in fx.events ?? [] where e.type == "subst" && e.time.elapsed * 100 + (e.time.extra ?? 0) < key {
            guard let out = e.player.id, let inn = e.assist.id, ids.contains(out) else { continue }
            ids.remove(out); ids.insert(inn)
        }
        return ids.compactMap { people[$0] }
    }

    init?(_ fx: Fixture) {
        guard let lineups = fx.lineups, lineups.count == 2, ["FT", "AET", "PEN"].contains(fx.fixture.status.short) else { return nil }
        self.fx = fx
        let sideOf: (Int?) -> Side = { $0 == fx.teams.home.id ? .home : .away }
        var people: [Int: Person] = [:]
        for l in lineups {
            let s = sideOf(l.team.id)
            for x in l.startXI { if let id = x.player.id { people[id] = Person(id: id, name: x.player.name, side: s, number: x.player.number, pos: x.player.pos, grid: x.player.grid, starter: true) } }
            for x in l.substitutes { if let id = x.player.id { people[id] = Person(id: id, name: x.player.name, side: s, number: x.player.number, pos: x.player.pos) } }
        }
        // full names + match stats (the lineups use "J. Scally")
        for tp in fx.players ?? [] {
            for line in tp.players {
                let st = line.statistics.first
                var p = people[line.player.id] ?? Person(id: line.player.id, name: line.player.name, side: sideOf(tp.team.id))
                p.name = line.player.name
                p.rating = st?.games?.rating?.v
                p.minutes = Int(st?.games?.minutes?.v ?? 0)
                var s: [String: Double] = [:]
                s["shots"] = st?.shots?.total?.v ?? 0
                s["onTarget"] = st?.shots?.on?.v ?? 0
                s["keyPasses"] = st?.passes?.key?.v ?? 0
                s["passes"] = st?.passes?.total?.v ?? 0
                s["tackles"] = st?.tackles?.total?.v ?? 0
                s["interceptions"] = st?.tackles?.interceptions?.v ?? 0
                s["blocks"] = st?.tackles?.blocks?.v ?? 0
                // match stats give accurate passes as a count ("38"); season stats as a % ? handle both
                let tot = st?.passes?.total?.v ?? 0, acc = st?.passes?.accuracy?.v ?? 0
                if tot > 0 && acc > 0 { s["passAcc"] = acc <= tot ? (acc / tot * 100).rounded() : min(100, acc) }
                s["duelsWon"] = st?.duels?.won?.v ?? 0
                s["dribbles"] = st?.dribbles?.success?.v ?? 0
                s["saves"] = st?.goals?.saves?.v ?? 0
                s["penSaved"] = st?.penalty?.saved?.v ?? 0
                p.stats = s
                people[p.id] = p
            }
        }
        // subs take the slot of the man they replaced
        for e in fx.events ?? [] where e.type == "subst" {
            if let out = e.player.id, let inn = e.assist.id, let g = people[out]?.grid, people[inn]?.grid == nil { people[inn]?.grid = g }
        }
        func person(_ r: Fixture.Ref, _ s: Side) -> Person? {
            guard let id = r.id else { return nil }
            return people[id] ?? Person(id: id, name: r.name ?? "", side: s)
        }
        var moments: [Moment] = []
        var cards: [(Int, Side, Bool)] = []
        for (i, e) in (fx.events ?? []).enumerated() {
            let s = sideOf(e.team.id)
            let key = e.time.elapsed * 100 + (e.time.extra ?? 0)
            func add(_ k: Moment.Kind, _ side: Side, _ p: Person?, _ a: Person?) {
                moments.append(Moment(id: i, kind: k, side: side, elapsed: e.time.elapsed, extra: e.time.extra, player: p, assist: a, reason: e.comments))
            }
            switch (e.type, e.detail) {
            case ("Goal", "Normal Goal"): add(.goal, s, person(e.player, s), person(e.assist, s))
            case ("Goal", "Penalty"): add(.penalty, s, person(e.player, s), nil)
            case ("Goal", "Own Goal"): add(.ownGoal, s, person(e.player, s.other), nil)
            case ("Goal", "Missed Penalty"):
                // a keeper with a save on his line ? it was saved, otherwise it went wide/over
                let saved = (people.values.contains { $0.side == s.other && $0.pos == "G" && ($0.stats["penSaved"] ?? 0) > 0 })
                add(saved ? .savedPen : .missedPen, s, person(e.player, s), nil)
            case ("Var", "Goal cancelled"), ("Var", "Goal Disallowed"): add(.varNoGoal, s, person(e.player, s), nil)
            case ("Card", let d) where d.contains("Red") || d.contains("Second"):
                add(.red, s, person(e.player, s), nil); cards.append((key, s, true))
            case ("Card", _): add(.yellow, s, person(e.player, s), nil); cards.append((key, s, false))
            default: break
            }
        }
        self.moments = moments.sorted { ($0.key, $0.id) < ($1.key, $1.id) }
        self.cards = cards.map { (key: $0.0, side: $0.1, red: $0.2) }
        self.people = people
        var stats: [String: TeamStat] = [:]
        if let st = fx.statistics, st.count == 2 {
            let h = st.first { sideOf($0.team.id) == .home } ?? st[0]
            let a = st.first { sideOf($0.team.id) == .away } ?? st[1]
            for s in h.statistics {
                if let hv = s.value.v, let av = a.statistics.first(where: { $0.type == s.type })?.value.v {
                    stats[s.type] = TeamStat(name: s.type, home: hv, away: av)
                }
            }
        }
        self.stats = stats
    }
}

func hexString(_ v: UInt32) -> String { String(format: "#%06X", v) }

// MARK: - kit colours (the API has none): each crest's strongest colour, cached per team

enum Kits {
    /// The two kits + two keeper kits for a match, as "#RRGGBB". Never two that clash, never pitch green.
    static func colours(_ t: MatchTape) async -> (home: String, away: String, homeGk: String, awayGk: String) {
        var h = await crest(t.home)
        var a = await crest(t.away)
        let white: UInt32 = 0xF2F2F2, navy: UInt32 = 0x1B2A4A
        if grassy(h) { h = white }
        if grassy(a) { a = navy }
        if dist(h, a) < 120 { a = dist(h, white) < 160 ? navy : white }
        let gks: [UInt32] = [0xE8B21E, 0x2B2B2B, 0xFF7A1A, 0x7B3FE4, 0x14B8C8]
        let hg = gks.first { dist($0, h) > 130 && dist($0, a) > 130 } ?? 0xE8B21E
        let ag = gks.first { $0 != hg && dist($0, h) > 130 && dist($0, a) > 130 } ?? 0x2B2B2B
        return (hexString(h), hexString(a), hexString(hg), hexString(ag))
    }

    static func dist(_ x: UInt32, _ y: UInt32) -> Double {
        let d = [16, 8, 0].map { Double(Int((x >> $0) & 0xFF) - Int((y >> $0) & 0xFF)) }
        return (d[0] * d[0] + d[1] * d[1] + d[2] * d[2]).squareRoot()
    }
    private static func grassy(_ c: UInt32) -> Bool {
        var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0
        UIColor(rgb: c).getHue(&hue, saturation: &sat, brightness: &bri, alpha: nil)
        return hue > 0.2 && hue < 0.45 && sat > 0.3
    }

    /// Downsample the crest to 24×24 and vote: saturated pixels by hue (weighted by how vivid they are); a crest with
    /// no real colour (black-and-white clubs) gets white or near-black from its average brightness.
    static func crest(_ team: Fixture.Team) async -> UInt32 {
        let key = "sm.kit.\(team.id)"
        if let v = UserDefaults.standard.object(forKey: key) as? Int { return UInt32(v) }
        guard let img = await RemoteImages.load(team.logo)?.cgImage else { return 0xF2F2F2 }
        let n = 24
        var px = [UInt8](repeating: 0, count: n * n * 4)
        guard let ctx = CGContext(data: &px, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0xF2F2F2 }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: n, height: n))
        var bins = [(w: Double, r: Double, g: Double, b: Double)](repeating: (0, 0, 0, 0), count: 12)
        var lum = 0.0, opaque = 0.0
        for i in stride(from: 0, to: px.count, by: 4) where px[i + 3] > 200 {
            let r = Double(px[i]) / 255, g = Double(px[i + 1]) / 255, b = Double(px[i + 2]) / 255
            var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0
            UIColor(red: r, green: g, blue: b, alpha: 1).getHue(&hue, saturation: &sat, brightness: &bri, alpha: nil)
            opaque += 1
            lum += 0.3 * r + 0.59 * g + 0.11 * b
            guard sat > 0.35, bri > 0.25 else { continue }
            let k = min(11, Int(hue * 12)), w = Double(sat * bri)
            bins[k].w += w; bins[k].r += r * w; bins[k].g += g * w; bins[k].b += b * w
        }
        var out: UInt32
        if let top = bins.max(by: { $0.w < $1.w }), top.w > max(4, opaque * 0.06) {
            let c = { (v: Double) in UInt32(max(0, min(255, (v / top.w * 255).rounded()))) }
            out = c(top.r) << 16 | c(top.g) << 8 | c(top.b)
        } else {
            out = opaque > 0 && lum / opaque > 0.55 ? 0xF2F2F2 : 0x2B2B2B
        }
        UserDefaults.standard.set(Int(out), forKey: key)
        return out
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

// MARK: - the store: tapes on disk, the daily pull, what you've watched

@Observable
final class Matchday {
    static let shared = Matchday()

    /// Big leagues first (rank bonus + which matches are worth a call).
    static let leaguePriority: [Int: Int] = [2: 0, 39: 1, 140: 2, 135: 3, 78: 4, 61: 5, 3: 6, 1: 0, 4: 0, 9: 1, 13: 6, 848: 7,
                                             94: 8, 88: 9, 40: 10, 253: 11, 71: 12, 307: 13, 262: 14, 45: 8, 143: 8, 137: 8, 81: 8, 66: 9]

    private(set) var tapes: [MatchTape] = []
    var loading = false
    var status = ""
    private(set) var updated: Date?

    /// Films you've watched to the end (fixture ids).
    var watched: Set<Int> { didSet { save(watched, "sm.md.watched.v1"); Task { @MainActor in WidgetSync.push() } } }

    private let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("matchday", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    init() {
        watched = (UserDefaults.standard.data(forKey: "sm.md.watched.v1")).flatMap { try? JSONDecoder().decode(Set<Int>.self, from: $0) } ?? []
        updated = UserDefaults.standard.object(forKey: "sm.md.updated") as? Date
        loadDisk()
    }

    private func save<T: Encodable>(_ v: T, _ key: String) { UserDefaults.standard.set(try? JSONEncoder().encode(v), forKey: key) }

    /// The night's best match (most recent day, then best rank).
    var hero: MatchTape? { tapes.first }
    var latestDay: String? { tapes.first?.dayKey }
    func tape(_ id: Int) -> MatchTape? { tapes.first { $0.id == id } }

    private func loadDisk() {
        var byId: [Int: Fixture] = [:]
        let dec = JSONDecoder()
        if let bundled = Bundle.main.url(forResource: "Matchday", withExtension: nil),
           let files = try? FileManager.default.contentsOfDirectory(at: bundled, includingPropertiesForKeys: nil) {
            for f in files where f.pathExtension == "json" {
                if let d = try? Data(contentsOf: f), let fx = try? dec.decode(Fixture.self, from: d) { byId[fx.id] = fx }
            }
        }
        if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for f in files where f.pathExtension == "json" {
                if let d = try? Data(contentsOf: f), let fx = try? dec.decode(Fixture.self, from: d) { byId[fx.id] = fx }
            }
        }
        sort(byId.values.compactMap(MatchTape.init).filter { !$0.moments.filter(\.counts).isEmpty })
    }

    private func sort(_ list: [MatchTape]) {
        tapes = list.sorted { a, b in a.dayKey != b.dayKey ? a.dayKey > b.dayKey : a.rank > b.rank }
    }

    // ---- the nightly pack (2026-10-28): the server pulls API-Football twice a night (supabase/functions/matchday-pull)
    // and saves each finished match in public.matchday_fixtures. Phones only read that table ? no football key in the app.

    private struct Row: Decodable { let id: Int; let data: Fixture; let created_at: String }

    /// Pick up matches the server saved since we last looked. At most once every 30 minutes.
    @MainActor
    func refresh(force: Bool = false) async {
        guard !loading else { return }
        if !force, let updated, Date().timeIntervalSince(updated) < 30 * 60 { return }
        loading = true
        defer { loading = false }
        let since = UserDefaults.standard.string(forKey: "sm.md.since") ?? "1970-01-01T00:00:00Z"
        var c = URLComponents(url: SupabaseConfig.url.appendingPathComponent("rest/v1/matchday_fixtures"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "select", value: "id,data,created_at"),
                        URLQueryItem(name: "created_at", value: "gt.\(since)"),
                        URLQueryItem(name: "order", value: "created_at.asc"),
                        URLQueryItem(name: "limit", value: "60")]
        var r = URLRequest(url: c.url!)
        r.setValue(SupabaseConfig.key, forHTTPHeaderField: "apikey")
        r.timeoutInterval = 20
        status = "Checking for new matches?"
        defer { status = "" }
        guard let (data, resp) = try? await URLSession.shared.data(for: r), (resp as? HTTPURLResponse)?.statusCode == 200,
              let rows = try? JSONDecoder().decode([Row].self, from: data) else { return }
        updated = Date()
        UserDefaults.standard.set(updated, forKey: "sm.md.updated")
        let have = Set(tapes.map(\.id))
        var fresh: [MatchTape] = []
        for row in rows {
            if let raw = try? JSONEncoder().encode(row.data) { try? raw.write(to: dir.appendingPathComponent("\(row.id).json")) }
            if !have.contains(row.id), let t = MatchTape(row.data), t.moments.contains(where: { (m: Moment) in m.counts }) { fresh.append(t) }
        }
        if let lastRow = rows.last { UserDefaults.standard.set(lastRow.created_at, forKey: "sm.md.since") }
        if !fresh.isEmpty { sort(tapes + fresh); WidgetSync.push() }   // a new match of the day for the widget
    }
}
