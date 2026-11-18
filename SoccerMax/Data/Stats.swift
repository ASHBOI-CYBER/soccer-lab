// The Stats tab's maths (notes/19 "Stats tab"): the AIR streak (10 min of training at least once every 3 days keeps
// the ball pumped) and XP + levels from finished sessions. A level IS a badge: every level up sews on a new one.
import Foundation

/// One finished session: FINISH pressed with training time in it. XP = 50 + 10 per minute.
struct Completion: Codable, Hashable {
    var date: Date
    var name: String
    var minutes: Int
    /// Since the session player (2026-10-28): the exact time and each drill done ? the LOGGED list shows them.
    var seconds: Int? = nil
    var drills: [LoggedDrill]? = nil
    /// Free sessions (2026-11-08): the area picked at START (`TrainingArea.id`) and the photos/videos added at the end
    /// (file names in Documents/SessionMedia ? on this phone only, never backed up).
    var area: String? = nil
    var media: [String]? = nil
    /// MAP tab (2026-11-08): where it was played (rounded to ~100 m), if location was allowed.
    var lat: Double? = nil
    var lng: Double? = nil
    /// Live sessions v2 (2026-11-08): every category done in this session, in order (switching mid-session).
    var parts: [SessionPart]? = nil
    var xp: Int { 50 + 10 * minutes }
}

/// One drill inside a logged session: what it was, the dose, and how long it really took.
struct LoggedDrill: Codable, Hashable {
    var drill: String
    var name: String
    var dose: String
    var seconds: Int
}

// keyDate / addDays / daysBetween live in Shared/Streak.swift (the widgets use them too).

/// "84 min", "3 h 20"
func minText(_ m: Double) -> String {
    let n = Int(m.rounded())
    return n < 120 ? "\(n) min" : "\(n / 60) h \(n % 60 < 10 ? "0" : "")\(n % 60)"
}

// MARK: - the streak (AirStreak itself is in Shared/Streak.swift, so the home-screen widgets count it the same way)

extension AppStore {
    var keptDays: [Date] { trained.filter { $0.value >= AirStreak.keep }.keys.compactMap(keyDate).sorted() }

    var air: AirStreak { AirStreak.compute(trained) }

    // MARK: levels

    /// Finished sessions plus what Soccer Lab's tabs earn (Lab.bonusXP: drills, full sessions, film, runs, food).
    @MainActor var xp: Int { completions.reduce(0) { $0 + $1.xp } + Lab.shared.bonusXP }
    @MainActor var level: Level { Level(xp: xp) }

    /// Record a finished session (only when it put training time in).
    @MainActor func complete(_ name: String?, minutes: Double, seconds: Int? = nil, drills: [LoggedDrill]? = nil,
                  area: String? = nil, media: [String]? = nil, parts: [SessionPart]? = nil) {
        guard minutes >= 1 else { return }
        let spot = TEAMS_ON ? SessionSpot.shared.here : nil
        completions.append(Completion(date: Date(), name: name ?? "Today", minutes: Int(minutes.rounded()), seconds: seconds,
                                      drills: drills, area: area, media: media, lat: spot?.lat, lng: spot?.lng, parts: parts))
    }

    // MARK: totals

    var totalTrained: Double { trained.values.reduce(0, +) }
    var totalFilm: Double { film.values.reduce(0, +) }
    func addFilm(_ minutes: Double) {
        guard minutes > 0.1 else { return }
        film[dateKey(Date()), default: 0] += min(minutes, 180)
    }

    /// The seven days of a Mon?Sun week, `back` weeks ago: (date, training, film).
    func week(back: Int) -> [(date: Date, train: Double, film: Double)] {
        let mon = addDays(dateOf("Mon"), -7 * back)
        return (0..<7).map { i in
            let d = addDays(mon, i), k = dateKey(d)
            return (d, trained[k] ?? 0, film[k] ?? 0)
        }
    }

    // MARK: debug

    /// DEBUG `stats:demo`: a year of training + film + sessions. `stats:demo-urgent` = last kept day 3 days ago
    /// (hours of air left); `stats:demo-flat` = the streak ran out.
    func seedStatsDemo() {
        let mode = DebugRoute.parts.last ?? ""
        let cal = Calendar.current
        var rng = SystemRandomNumberGenerator()
        var t: [String: Double] = [:], fm: [String: Double] = [:], done: [Completion] = []
        let today = cal.startOfDay(for: Date())
        let quiet: ClosedRange<Int> = mode == "demo-urgent" ? 0...2 : mode == "demo-flat" ? 0...6 : 999...999
        for back in stride(from: 300, through: 0, by: -1) {
            let d = addDays(today, -back)
            if quiet.contains(back) { continue }
            let busy = back < 40 ? 0.62 : back < 120 ? 0.45 : 0.3
            if Double.random(in: 0...1, using: &rng) < busy {
                let counts = back < 35   // XP only from the last ~10 weeks, so the demo sits mid-ladder
                let m = Double(Int.random(in: 8...48, using: &rng))
                t[dateKey(d)] = m
                if counts { done.append(Completion(date: cal.date(byAdding: .hour, value: Int.random(in: 7...21, using: &rng), to: d)!,
                                       name: ["Quick Feet", "Weak Foot Day", "Pass & Go"].randomElement()!, minutes: Int(m))) }
            }
            if Double.random(in: 0...1, using: &rng) < 0.22 { fm[dateKey(d)] = Double(Int.random(in: 4...26, using: &rng)) }
        }
        // a solid recent run so the hero has a streak to show
        if mode == "demo" { for back in [0, 2, 3, 6, 9, 11, 13, 16, 19, 22] { t[dateKey(addDays(today, -back))] = Double(Int.random(in: 14...40, using: &rng)) } }
        if mode == "demo-urgent" { t[dateKey(addDays(today, -3))] = 22; t[dateKey(addDays(today, -6))] = 18 }
        if mode == "demo" { t[dateKey(today)] = 6 }   // today: 6 of 10 min
        trained = t
        film = fm
        completions = done
        seenLevel = max(1, Level(xp: completions.reduce(0) { $0 + $1.xp }).lv - 1)   // so the demo shows a NEW badge
    }
}

// MARK: - levels

struct Level {
    let lv: Int
    let into: Int     // XP into this level
    let need: Int     // XP this level takes
    init(xp: Int) {
        var l = 1, left = xp
        while left >= Self.need(l) { left -= Self.need(l); l += 1 }
        lv = l; into = left; need = Self.need(l)
    }
    static func need(_ l: Int) -> Int { 200 + 100 * (l - 1) }
    var progress: Double { Double(into) / Double(need) }

    var badge: LevelBadge { LevelBadge.of(lv) }
    var title: String { badge.name.uppercased() }
}

// MARK: - badges: one per level

enum Rarity: Int, CaseIterable {
    case common, rare, epic, legend
    var name: String { ["BRONZE", "SILVER", "GOLD", "DIAMOND"][rawValue] }
}

struct LevelBadge: Identifiable {
    let lv: Int
    /// Tier + roman numeral (2026-11-08, user: "rename all the badges to be like silver I, gold III").
    var name: String {
        let tier = ["Bronze", "Silver", "Gold", "Diamond"][rarity.rawValue]
        return "\(tier) \(["I", "II", "III", "IV", "V"][(lv - 1) % 5])"
    }
    let icon: String          // SF Symbol, or a short word when `word` is true
    var word = false
    var id: Int { lv }
    /// Every 5 levels the patch gets rarer: bronze ? silver ? gold ? shimmering diamond.
    var rarity: Rarity { Rarity(rawValue: min(3, (lv - 1) / 5))! }

    static let all: [LevelBadge] = [
        LevelBadge(lv: 1, icon: "soccerball"),
        LevelBadge(lv: 2, icon: "shoeprints.fill"),
        LevelBadge(lv: 3, icon: "figure.run"),
        LevelBadge(lv: 4, icon: "arrow.left.arrow.right"),
        LevelBadge(lv: 5, icon: "sun.max.fill"),
        LevelBadge(lv: 6, icon: "graduationcap.fill"),
        LevelBadge(lv: 7, icon: "eye.fill"),
        LevelBadge(lv: 8, icon: "3", word: true),
        LevelBadge(lv: 9, icon: "moon.stars.fill"),
        LevelBadge(lv: 10, icon: "tshirt.fill"),
        LevelBadge(lv: 11, icon: "lungs.fill"),
        LevelBadge(lv: 12, icon: "shoe.2.fill"),
        LevelBadge(lv: 13, icon: "C", word: true),
        LevelBadge(lv: 14, icon: "binoculars.fill"),
        LevelBadge(lv: 15, icon: "flame.fill"),
        LevelBadge(lv: 16, icon: "globe.europe.africa.fill"),
        LevelBadge(lv: 17, icon: "star.fill"),
        LevelBadge(lv: 18, icon: "building.columns.fill"),
        LevelBadge(lv: 19, icon: "crown.fill"),
        LevelBadge(lv: 20, icon: "trophy.fill"),
    ]
    /// Past the last level the top badge stays (the level number keeps climbing).
    static func of(_ lv: Int) -> LevelBadge { all[min(max(lv, 1), all.count) - 1] }
}
