// Everything saved on the phone: onboarding answers, the week plan, learned moves.
// Card maths and drill picks are straight ports of src/onboarding/state.ts and src/data/recommend.ts.
import Foundation
import Observation
import UIKit

let STATS = ["SHO", "PAS", "DRI", "DEF", "PHY", "BC"]
let STAT_NAME = ["SHO": "Shooting", "PAS": "Passing", "DRI": "Dribbling", "DEF": "Defending", "PHY": "Physical", "BC": "Ball control"]

struct Answers: Codable, Equatable {
    var first = ""
    var last = ""
    var age: String?
    var level: String?
    var position = "CM"
    var foot: String?
    /// Onboarding v3 (2026-11-08). Optional so saves from before still decode.
    var gender: String?
    /// "What do you want most from Soccer Lab?" ? several picks, social first (onboarding v3).
    var wants: [String]?
    var best: [String] = []
    var fix: [String] = []
    var fear: String?
    var selfRating: [String: Int] = ["SHO": 5, "PAS": 5, "DRI": 5, "DEF": 5, "PHY": 5, "BC": 5]
    var with = "Solo"
    var gear: [String] = ["Ball"]
    var space: String?
    var days: [String] = ["Mon", "Wed", "Fri"]
    var minutes = 30
    var goal: String?
    var when: String?
    var source: String?
    var notify: Bool?
    /// When the player ticked the "Before you start" page (onboarding, 2026-11-21).
    var agreedAt: Date?
    var drills: [String] = []
    var pledged = false
    /// Onboarding v4 (2026-11-17): the body and routine behind the personal fuel targets and plan. Optional so older
    /// saves still decode.
    var heightCm: Double?
    var weightKg: Double?
    /// "1-2 days", "3-4 days", "5-6 days", "Every day"
    var trainDays: String?
    /// What they want from food: "Build muscle", "Stay lean and fast", "More energy for games", "Just eat better"
    var fuelGoal: String?

    /// Training days a week from the routine answer (for the fuel targets).
    var trainingDaysPerWeek: Int {
        switch trainDays { case "1-2 days": return 2; case "3-4 days": return 4; case "5-6 days": return 5; case "Every day": return 7; default: return 3 }
    }

    var firstName: String { first.trimmingCharacters(in: .whitespaces).isEmpty ? "Player" : first.trimmingCharacters(in: .whitespaces) }
    /// FC cards show the surname when there is one.
    var cardName: String { last.trimmingCharacters(in: .whitespaces).isEmpty ? firstName : last.trimmingCharacters(in: .whitespaces) }
    var positionName: String { Library.shared.positions[position] ?? position }
}

struct PlanItem: Codable, Hashable {
    var drill: String
    var sets: Int
    var reps: Int?
    var min: Int
    /// What a rep is counted in: "s", "min", "each foot", "shots"? ("" = plain reps, nil = an old save).
    var unit: String?

    init(_ id: String, sets: Int? = nil) {
        let d = Library.shared.drill(id)
        drill = d.id
        let base = Self.parse(d.reps)
        self.sets = sets ?? base?.sets ?? 3
        reps = base?.reps
        unit = base?.unit
        min = d.min
        retime()
    }

    /// "4 × 45 s" ? (4, 45, "s"); "3 × 8 each foot" ? (3, 8, "each foot"); "6 runs" ? nil.
    static func parse(_ s: String) -> (sets: Int, reps: Int, unit: String)? {
        guard let m = s.firstMatch(of: /^(\d+)\s*×\s*(\d+)\s*(.*)$/), let a = Int(m.1), let b = Int(m.2) else { return nil }
        return (a, b, String(m.3).trimmingCharacters(in: .whitespaces))
    }

    /// Minutes scale with the work picked (more sets or reps ? longer), from the drill's own dose and time.
    mutating func retime() {
        let d = Library.shared.drill(drill)
        guard let base = Self.parse(d.reps), let reps, base.sets * base.reps > 0 else {
            min = Swift.max(1, Int((Double(d.min) * Double(sets) / 3).rounded()))
            return
        }
        min = Swift.max(1, Int((Double(d.min) * Double(sets * reps) / Double(base.sets * base.reps)).rounded()))
    }

    /// How a rep reads after its number ("45 s", "8 each foot", "10").
    var repText: String? {
        guard let reps else { return nil }
        guard let unit, !unit.isEmpty else { return "\(reps)" }
        return "\(reps) \(unit)"
    }
    var dose: String { repText.map { "\(sets) × \($0)" } ?? "\(sets) set\(sets == 1 ? "" : "s") · \(min) min" }
}

/// A named session the player builds: drills with their own sets and reps. Start it any time (no days since
/// 2026-10-24: "remove the days from the sessions").
struct Session: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var items: [PlanItem]
    /// The Pro Session this was saved from (nil = the player built it).
    var pro: String?
    /// The side it was made on ("fitness" / nil = skills) ? only decides where an EMPTY session lives.
    var kind: String?
    /// The training level a saved premade copy was built at (it follows the level until the player changes it).
    var level: Int?

    init(id: String = UUID().uuidString, name: String, items: [PlanItem] = [], pro: String? = nil, fitness: Bool = false) {
        self.id = id
        self.name = name
        self.items = items
        self.pro = pro
        self.kind = fitness ? "fitness" : nil
    }

    /// Skills vs Fitness (2026-10-24): any drill with a ball ? Skills; no ball anywhere ? Fitness.
    /// A saved premade copy goes where it came from (a Park-level Kanté skills copy has no ball drill in it, but it's
    /// still a Skills session; "Kanté Engine" is Fitness).
    var isFitness: Bool {
        if let pro { return Library.shared.isFitness(pro: pro) }
        return items.isEmpty ? kind == "fitness" : !drills.contains(where: \.usesBall)
    }

    var minutes: Int { items.reduce(0) { $0 + $1.min } }
    var drills: [Drill] { items.map { Library.shared.drill($0.drill) } }
    var summary: String { "\(items.count) drill\(items.count == 1 ? "" : "s") · \(minutes) min" }
}

/// Where a drill on a day comes from: one of the day's sessions, or a raw drill put on the day by itself.
enum EntrySource: Hashable { case session(String, Int), raw(Int) }
struct DayEntry: Hashable { let item: PlanItem; let source: EntrySource }

typealias Week = [String: [PlanItem]]

/// How a day of the week reads on the Plan tab. `before` = a past day from before the app started tracking
/// (a new install mid-week must never open on "Missed").
enum DayState { case rest, done, today, upcoming, missed, before }

@Observable
final class AppStore {
    var answers: Answers { didSet { save(answers, "sm.answers.v1") } }
    /// Raw drills put straight on a day (no session).
    var week: Week { didSet { save(week, "sm.plan.v1") } }
    /// The player's named sessions.
    var sessions: [Session] { didSet { save(sessions, "sm.sessions.v1") } }
    /// Which sessions are on which day: "Mon" ? session ids.
    var daySessions: [String: [String]] { didSet { save(daySessions, "sm.daysessions.v1") } }
    var learned: [String] { didSet { save(learned, "sm.moves.v1") } }
    var onboarded: Bool { didSet { UserDefaults.standard.set(onboarded, forKey: "sm.onboarded") } }
    /// Sets ticked off, by date: "2026-10-23" ? drill id ? sets. Keyed by date, so every week starts clean.
    var log: [String: [String: Int]] { didSet { save(log, "sm.log.v1") } }
    /// Dates whose session got done (every set ticked, or FINISH). The streak counts these.
    var finished: Set<String> { didSet { save(finished, "sm.finished.v1") } }
    /// The first day tracked. Days before it are never "missed".
    var since: String { didSet { UserDefaults.standard.set(since, forKey: "sm.since") } }
    /// Minutes trained, by date ? credited per ticked set (drill time ÷ sets). ? 10 keeps the streak (Data/Stats.swift).
    var trained: [String: Double] { didSet { save(trained, "sm.trained.v1"); Task { @MainActor in WidgetSync.push() } } }
    /// Minutes of Matchday film watched, by date.
    var film: [String: Double] { didSet { save(film, "sm.film.v1") } }
    /// Every session finished (FINISH with time trained in it) ? the XP source for levels.
    var completions: [Completion] { didSet { save(completions, "sm.completions.v1") } }
    /// The highest level whose badge the player has seen (a newer one wears NEW on the Stats tab).
    var seenLevel: Int { didSet { UserDefaults.standard.set(seenLevel, forKey: "sm.seenlevel") } }
    /// The training level picked on the Sessions tab's stadium carousel (0 Park ? 4 World Class); nil = not picked
    /// yet, so it follows the onboarding level. It only changes the premade sessions (notes/23).
    var pickedLevel: Int? { didSet { UserDefaults.standard.set(pickedLevel, forKey: "sm.level.v1") } }
    /// The player's club, picked on the Profile tab from Hat Trick Local or typed in (Data/Club.swift).
    var club: Club? { didSet { save(club, "sm.club.v1") } }
    /// The profile photo (Application Support/avatar.jpg). nil = initials.
    private(set) var avatar: UIImage? = AppStore.loadAvatar()

    init() {
        answers = Self.load("sm.answers.v1") ?? Answers()
        week = Self.load("sm.plan.v1") ?? Self.starter
        sessions = Self.load("sm.sessions.v1") ?? Self.starterSessions
        // sessions are no longer put on days (2026-10-24) ? any old days are dropped
        daySessions = [:]
        learned = Self.load("sm.moves.v1") ?? []
        onboarded = UserDefaults.standard.bool(forKey: "sm.onboarded")
        log = Self.load("sm.log.v1") ?? [:]
        finished = Self.load("sm.finished.v1") ?? []
        trained = Self.load("sm.trained.v1") ?? [:]
        film = Self.load("sm.film.v1") ?? [:]
        completions = Self.load("sm.completions.v1") ?? []
        seenLevel = max(1, UserDefaults.standard.integer(forKey: "sm.seenlevel"))
        pickedLevel = UserDefaults.standard.object(forKey: "sm.level.v1") as? Int
        club = Self.load("sm.club.v1")
        since = UserDefaults.standard.string(forKey: "sm.since") ?? dateKey(Date())
        UserDefaults.standard.set(since, forKey: "sm.since")
        for d in DAYS { week[d] = (week[d] ?? []).filter { Library.shared.has($0.drill) } }
        for i in sessions.indices { sessions[i].items = sessions[i].items.filter { Library.shared.has($0.drill) } }
        UserDefaults.standard.removeObject(forKey: "sm.daysessions.v1")
        // Fitness arrived 2026-10-24: every install gets the ready-made fitness sessions once
        if !UserDefaults.standard.bool(forKey: "sm.fitness.v1") {
            UserDefaults.standard.set(true, forKey: "sm.fitness.v1")
            sessions += Self.fitnessSessions.filter { f in !sessions.contains { $0.id == f.id } }
        }
        if let last = DebugRoute.parts.last, last.hasPrefix("demo") { seedDemo(missed: last == "demo-missed") }
        if DebugRoute.parts.last == "fresh" { log = [:]; finished = []; since = dateKey(Date()); trained = [:]; film = [:]; completions = []; seenLevel = 1 }
    }

    /// Re-read everything from UserDefaults (after a backup came down from the cloud ? Data/Backup.swift).
    func reload() {
        answers = Self.load("sm.answers.v1") ?? answers
        week = Self.load("sm.plan.v1") ?? week
        sessions = (Self.load("sm.sessions.v1") ?? sessions).map { s in var s = s; s.items = s.items.filter { Library.shared.has($0.drill) }; return s }
        learned = Self.load("sm.moves.v1") ?? learned
        log = Self.load("sm.log.v1") ?? log
        finished = Self.load("sm.finished.v1") ?? finished
        trained = Self.load("sm.trained.v1") ?? trained
        film = Self.load("sm.film.v1") ?? film
        completions = Self.load("sm.completions.v1") ?? completions
        club = Self.load("sm.club.v1") ?? club
        seenLevel = max(1, UserDefaults.standard.integer(forKey: "sm.seenlevel"))
        pickedLevel = UserDefaults.standard.object(forKey: "sm.level.v1") as? Int
        since = UserDefaults.standard.string(forKey: "sm.since") ?? since
        for d in DAYS { week[d] = (week[d] ?? []).filter { Library.shared.has($0.drill) } }
    }
    /// Debug demo data (sim.sh routes) is never backed up.
    var isDemo: Bool { let l = DebugRoute.parts.last ?? ""; return l.hasPrefix("demo") || l == "fresh" }

    // MARK: profile photo

    private static var avatarURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("avatar.jpg")
    }
    private static func loadAvatar() -> UIImage? { UIImage(contentsOfFile: avatarURL.path) }
    /// Save a new photo (squared + shrunk to 600 px), or nil to go back to initials.
    func setAvatar(_ img: UIImage?) {
        guard let img else {
            try? FileManager.default.removeItem(at: Self.avatarURL)
            avatar = nil
            return
        }
        let side = min(img.size.width, img.size.height)
        let out = min(600, side)
        let r = UIGraphicsImageRenderer(size: CGSize(width: out, height: out), format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
        let square = r.image { _ in
            let k = out / side
            img.draw(in: CGRect(x: -(img.size.width - side) / 2 * k, y: -(img.size.height - side) / 2 * k, width: img.size.width * k, height: img.size.height * k))
        }
        try? square.jpegData(compressionQuality: 0.85)?.write(to: Self.avatarURL, options: .atomic)
        avatar = square
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    private func save<T: Encodable>(_ v: T, _ key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(v), forKey: key)
    }

    // MARK: week

    static var empty: Week { Dictionary(uniqueKeysWithValues: DAYS.map { ($0, [PlanItem]()) }) }
    /// A new install: three ready-made sessions on Mon / Wed / Fri, and juggling on its own on Saturday.
    static var starter: Week {
        var w = empty
        w["Sat"] = [PlanItem("juggling", sets: 3)]
        return w
    }
    static var starterSessions: [Session] {
        [Session(id: "s-quick-feet", name: "Quick Feet", items: [PlanItem("toe-taps", sets: 3), PlanItem("cone-slalom", sets: 4)]),
         Session(id: "s-weak-foot", name: "Weak Foot Day", items: [PlanItem("foundations", sets: 2), PlanItem("figure-8", sets: 3), PlanItem("weak-foot-laces", sets: 3)]),
         Session(id: "s-pass-go", name: "Pass & Go", items: [PlanItem("wall-passes", sets: 3), PlanItem("speed-dribble", sets: 3)])]
    }
    /// Ready-made Fitness sessions (no ball): runs in your cleats, core, and a mix.
    static var fitnessSessions: [Session] {
        [Session(id: "s-cleat-runs", name: "Cleat Runs", items: [PlanItem("walking-knee-hug", sets: 1), PlanItem("strides", sets: 1), PlanItem("flying-20s", sets: 1), PlanItem("diagonals", sets: 1)]),
         Session(id: "s-core-10", name: "Core 10", items: [PlanItem("dead-bug", sets: 2), PlanItem("front-plank", sets: 3), PlanItem("side-plank", sets: 2), PlanItem("glute-bridge", sets: 2)]),
         Session(id: "s-match-fit", name: "Match Fit", items: [PlanItem("high-knee-runs", sets: 1), PlanItem("repeat-sprints", sets: 1), PlanItem("mountain-climbers", sets: 3), PlanItem("plank-shoulder-taps", sets: 2)])]
    }

    /// Everything on a day, in order: its sessions' drills, then the raw drills. A drill shows once a day
    /// (the set log is keyed by drill).
    func entries(_ day: String) -> [DayEntry] {
        var out: [DayEntry] = []
        var seen = Set<String>()
        for s in sessions(on: day) {
            for (i, it) in s.items.enumerated() where seen.insert(it.drill).inserted {
                out.append(DayEntry(item: it, source: .session(s.id, i)))
            }
        }
        for (i, it) in raw(day).enumerated() where seen.insert(it.drill).inserted {
            out.append(DayEntry(item: it, source: .raw(i)))
        }
        return out
    }
    func items(_ day: String) -> [PlanItem] { entries(day).map(\.item) }
    func raw(_ day: String) -> [PlanItem] { week[day] ?? [] }
    func minutes(_ day: String) -> Int { items(day).reduce(0) { $0 + $1.min } }
    func add(_ id: String, to day: String) {
        guard !raw(day).contains(where: { $0.drill == id }) else { return }
        week[day, default: []].append(PlanItem(id))
    }
    func remove(_ id: String, from day: String) { week[day] = raw(day).filter { $0.drill != id } }
    func setRaw(_ item: PlanItem, day: String, index: Int) { if week[day]?.indices.contains(index) == true { week[day]![index] = item } }
    func move(day: String, from: IndexSet, to: Int) { week[day]?.move(fromOffsets: from, toOffset: to) }

    /// "Quick Feet", "Quick Feet + 1 drill" ? nil when the day only has raw drills (or nothing).
    func label(_ day: String) -> String? {
        let names = sessions(on: day).map(\.name)
        guard !names.isEmpty else { return nil }
        let extra = raw(day).count
        return names.joined(separator: " + ") + (extra > 0 ? " + \(extra) drill\(extra == 1 ? "" : "s")" : "")
    }

    // MARK: sessions

    func session(_ id: String) -> Session? { sessions.first { $0.id == id } }
    func sessions(on day: String) -> [Session] { (daySessions[day] ?? []).compactMap(session) }
    func days(of id: String) -> [String] { DAYS.filter { daySessions[$0]?.contains(id) == true } }
    func isOn(_ id: String, _ day: String) -> Bool { daySessions[day]?.contains(id) == true }
    func toggle(_ id: String, on day: String) {
        if isOn(id, day) { daySessions[day]?.removeAll { $0 == id } } else { daySessions[day, default: []].append(id) }
    }

    @discardableResult
    func newSession(_ name: String, fitness: Bool = false) -> Session {
        let s = Session(name: name.trimmingCharacters(in: .whitespaces).isEmpty ? (fitness ? "My Workout" : "My Session") : name.trimmingCharacters(in: .whitespaces), fitness: fitness)
        sessions.insert(s, at: 0)
        return s
    }
    func deleteSession(_ id: String) {
        sessions.removeAll { $0.id == id }
        for d in DAYS { daySessions[d]?.removeAll { $0 == id } }
    }
    func edit(_ id: String, _ change: (inout Session) -> Void) {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        change(&sessions[i])
    }
    func toggleDrill(_ drill: String, in id: String) {
        edit(id) { s in
            if s.items.contains(where: { $0.drill == drill }) { s.items.removeAll { $0.drill == drill } } else { s.items.append(PlanItem(drill)) }
        }
    }
    /// The player's own copy of a premade session, once saved.
    func saved(pro id: String) -> Session? { sessions.first { $0.pro == id } }
    /// Save a premade session to My sessions (once), at the training level: a copy they can re-dose and put on days.
    @discardableResult
    func save(_ p: ProSession) -> Session {
        if let s = saved(pro: p.id) { return s }
        var s = Session(name: p.title, items: p.items(trainingLevel), pro: p.id)
        s.level = trainingLevel
        sessions.insert(s, at: 0)
        return s
    }
    /// Take a saved premade session back out of My sessions (and off the days it was on).
    func unsave(pro id: String) {
        if let s = saved(pro: id) { deleteSession(s.id) }
    }

    // MARK: training level (the stadium carousel)

    /// 0 Park · 1 Club · 2 Academy · 3 Pro · 4 World Class.
    var trainingLevel: Int { pickedLevel ?? Self.startLevel(answers.level) }
    /// Where a new player starts, from "What level do you play?" in onboarding.
    static func startLevel(_ played: String?) -> Int {
        ["Just for fun": 0, "School team": 1, "Club": 1, "Academy": 2, "College": 2, "Semi-pro +": 3][played ?? ""] ?? 1
    }
    /// Set the level. Saved premade copies the player hasn't changed are rebuilt at it; returns how many moved.
    @discardableResult
    func setLevel(_ n: Int) -> Int {
        let old = trainingLevel
        pickedLevel = n
        var moved = 0
        for i in sessions.indices {
            guard let id = sessions[i].pro, let p = Library.shared.pro(id), sessions[i].items == p.items(sessions[i].level ?? old) else { continue }
            sessions[i].items = p.items(n)
            sessions[i].level = n
            moved += 1
        }
        return moved
    }

    func sessions(fitness: Bool) -> [Session] { sessions.filter { $0.isFitness == fitness } }

    // MARK: tracking (this week's dates)

    func setsDone(_ day: String, _ drill: String) -> Int { log[dateKey(dateOf(day))]?[drill] ?? 0 }
    func totalSets(_ day: String) -> Int { items(day).reduce(0) { $0 + $1.sets } }
    func doneSets(_ day: String) -> Int { items(day).reduce(0) { $0 + Swift.min($1.sets, setsDone(day, $1.drill)) } }
    func isDone(_ day: String) -> Bool { !items(day).isEmpty && finished.contains(dateKey(dateOf(day))) }
    func progress(_ day: String) -> Double {
        let t = totalSets(day)
        return isDone(day) ? 1 : t == 0 ? 0 : Double(doneSets(day)) / Double(t)
    }

    /// Tick sets on a drill. Ticking the last set finishes the day; un-ticking it takes that back.
    /// `item` = the drill's dose as it is being run (a session run any day may not be on today's plan).
    func setDone(_ n: Int, day: String, drill: String, item: PlanItem? = nil) {
        let k = dateKey(dateOf(day))
        let was = doneSets(day) >= totalSets(day)
        if let it = item ?? items(day).first(where: { $0.drill == drill }), it.sets > 0 {
            let old = log[k]?[drill] ?? 0
            let delta = Double(Swift.min(n, it.sets) - Swift.min(old, it.sets)) * Double(it.min) / Double(it.sets)
            trained[k] = Swift.max(0, (trained[k] ?? 0) + delta)
        }
        log[k, default: [:]][drill] = n
        if doneSets(day) >= totalSets(day) { finished.insert(k) } else if was { finished.remove(k) }
    }
    func finish(_ day: String) { finished.insert(dateKey(dateOf(day))) }
    /// The session player (2026-10-28): a drill finished with its timer ? the real time counts, and its sets tick.
    func logDrill(_ it: PlanItem, seconds: Double) {
        let k = dateKey(Date())
        trained[k] = (trained[k] ?? 0) + Swift.max(0, seconds) / 60
        log[k, default: [:]][it.drill] = Swift.max(log[k]?[it.drill] ?? 0, it.sets)
        let day = todayKey()
        if totalSets(day) > 0 && doneSets(day) >= totalSets(day) { finished.insert(k) }
    }

    func state(_ day: String) -> DayState {
        if items(day).isEmpty { return .rest }
        if isDone(day) { return .done }
        let i = DAYS.firstIndex(of: day)!, t = DAYS.firstIndex(of: todayKey())!
        if i < t { return dateKey(dateOf(day)) < since ? .before : .missed }
        return i == t ? .today : .upcoming
    }

    /// Training days done in a row, walking back from today. Rest days don't break it; today only counts once done.
    var streak: Int {
        let cal = Calendar.current
        var d = cal.startOfDay(for: Date())
        var n = 0
        for i in 0..<400 {
            if !items(todayKey(d)).isEmpty {
                if finished.contains(dateKey(d)) { n += 1 } else if i > 0 { break }
            }
            d = cal.date(byAdding: .day, value: -1, to: d)!
        }
        return n
    }
    /// Sessions finished since Monday, and minutes trained since Monday (sessions have no days now, so these come
    /// from what was actually run, not from a weekly plan).
    var sessionsThisWeek: Int {
        let monday = Calendar.current.startOfDay(for: dateOf("Mon"))
        return completions.filter { $0.date >= monday }.count
    }
    var minutesThisWeek: Int { Int(DAYS.reduce(0.0) { $0 + (trained[dateKey(dateOf($1))] ?? 0) }.rounded()) }

    /// DEBUG `-route plan:demo`: three weeks of history, Mon + Wed done, a set into today ? for screenshots.
    /// `plan:demo-missed` leaves Wednesday half done instead; `plan:fresh` wipes the history (a new install).
    private func seedDemo(missed: Bool) {
        week = Self.starter
        sessions = Self.starterSessions + Self.fitnessSessions
        log = [:]
        finished = []
        let cal = Calendar.current
        since = dateKey(cal.date(byAdding: .day, value: -21, to: dateOf("Mon"))!)
        for back in 1...21 {
            let d = cal.date(byAdding: .day, value: -back, to: dateOf("Mon"))!
            if !items(todayKey(d)).isEmpty { finished.insert(dateKey(d)) }
        }
        for day in DAYS where DAYS.firstIndex(of: day)! < DAYS.firstIndex(of: todayKey())! {
            for (i, it) in items(day).enumerated() { setDone(missed && day == "Wed" ? (i == 0 ? 1 : 0) : it.sets, day: day, drill: it.drill) }
        }
        if let first = items(todayKey()).first { setDone(1, day: todayKey(), drill: first.drill) }
        if DebugRoute.parts.contains("done") { finish(todayKey()) }
        seedStatsDemo()
    }

    func apply(_ t: Template) {
        var w = Self.empty
        var c = 0
        for d in t.days {
            var list: [PlanItem] = []
            for _ in 0..<t.perDay {
                let id = t.drills[c % t.drills.count]
                c += 1
                if !list.contains(where: { $0.drill == id }) { list.append(PlanItem(id)) }
            }
            w[d] = list
        }
        week = w
        daySessions = [:]
    }

    func setWeek(_ days: [WeekDay]) {
        var w = Self.empty
        for d in days { w[d.day] = d.drills.map { PlanItem($0.id) } }
        week = w
        daySessions = [:]
    }

    // MARK: moves

    var nextMove: Move { Library.shared.moves.first { !learned.contains($0.id) } ?? Library.shared.moves[0] }
    func setLearned(_ id: String, _ on: Bool) {
        if on { if !learned.contains(id) { learned.append(id) } } else { learned.removeAll { $0 == id } }
    }

    func resetOnboarding() {
        answers = Answers()
        onboarded = false
    }
}

// MARK: - the player card (FC-style six stats + overall)

struct PlayerCardStats: Equatable { var stats: [String: Int]; var ovr: Int }
enum Tier: String { case bronze, silver, gold, max }

enum CardMath {
    static let base: [String: Double] = ["Just for fun": 60, "School team": 66, "Club": 71, "Academy": 76, "College": 78, "Semi-pro +": 82]
    static let skillStat: [String: String] = [
        "Dribbling": "DRI", "1v1s": "DRI", "Passing": "PAS", "Crossing": "PAS", "Long balls": "PAS", "Vision": "PAS",
        "Shooting": "SHO", "Finishing": "SHO", "Free kicks": "SHO", "Weak foot": "SHO",
        "First touch": "BC", "Ball control": "BC", "Composure": "BC",
        "Defending": "DEF", "Tackling": "DEF", "Positioning": "DEF", "Heading": "PHY", "Speed": "PHY", "Stamina": "PHY", "Strength": "PHY",
    ]
    private static func w(_ a: Double, _ b: Double, _ c: Double, _ d: Double, _ e: Double, _ f: Double) -> [String: Double] {
        ["SHO": a, "PAS": b, "DRI": c, "DEF": d, "PHY": e, "BC": f]
    }
    static let weight: [String: [String: Double]] = [
        "ST": w(3, 1, 2, 0.2, 1.5, 2), "LW": w(2, 1.5, 3, 0.2, 1.2, 2.2), "RW": w(2, 1.5, 3, 0.2, 1.2, 2.2),
        "CAM": w(1.8, 2.5, 2.5, 0.3, 0.8, 2.5), "LM": w(1.2, 2.2, 2.4, 0.8, 1.5, 2), "RM": w(1.2, 2.2, 2.4, 0.8, 1.5, 2),
        "CM": w(1, 3, 2, 1, 1.2, 2.5), "CDM": w(0.5, 2.5, 1, 2.5, 1.8, 2),
        "LWB": w(0.6, 2, 2, 2, 2, 1.5), "RWB": w(0.6, 2, 2, 2, 2, 1.5), "LB": w(0.4, 1.8, 1.5, 2.8, 2, 1.4), "RB": w(0.4, 1.8, 1.5, 2.8, 2, 1.4),
        "CB": w(0.2, 1.5, 0.6, 3.2, 2.5, 1.2), "GK": w(0.1, 1.5, 0.3, 3, 2, 2),
    ]
    static let lean: [String: [String: Double]] = [
        "ST": ["SHO": 4, "DEF": -6], "LW": ["DRI": 4, "DEF": -5], "RW": ["DRI": 4, "DEF": -5], "CAM": ["PAS": 3, "DRI": 2, "DEF": -5],
        "LM": ["DRI": 2, "PAS": 2], "RM": ["DRI": 2, "PAS": 2], "CM": ["PAS": 3], "CDM": ["DEF": 3, "PAS": 2, "SHO": -3],
        "LWB": ["PHY": 3, "DEF": 1, "SHO": -3], "RWB": ["PHY": 3, "DEF": 1, "SHO": -3], "LB": ["DEF": 3, "PHY": 2, "SHO": -4],
        "RB": ["DEF": 3, "PHY": 2, "SHO": -4], "CB": ["DEF": 5, "PHY": 3, "SHO": -6, "DRI": -4], "GK": ["DEF": 4, "SHO": -10, "DRI": -8],
    ]
    static func clamp(_ v: Double, _ lo: Double = 40, _ hi: Double = 99) -> Int { Int(Swift.max(lo, Swift.min(hi, v.rounded()))) }

    static func stat(_ a: Answers, _ s: String, selfRating: Int? = nil) -> Int {
        let b = base[a.level ?? ""] ?? 70
        var v = b + (Double(selfRating ?? a.selfRating[s] ?? 5) - 5.5) * 2.8 + (lean[a.position]?[s] ?? 0)
        if a.best.contains(where: { skillStat[$0] == s }) { v += 2 }
        return clamp(v)
    }
    static func overall(_ stats: [String: Int], _ pos: String) -> Int {
        let wt = weight[pos] ?? weight["CM"]!
        let tot = STATS.reduce(0) { $0 + wt[$1]! }
        return clamp(STATS.reduce(0) { $0 + Double(stats[$1]!) * wt[$1]! } / tot)
    }
    static func card(_ a: Answers) -> PlayerCardStats {
        var s: [String: Int] = [:]
        for k in STATS { s[k] = stat(a, k) }
        return PlayerCardStats(stats: s, ovr: overall(s, a.position))
    }
    /// The 6-week target if they stick to the plan.
    static func projection(_ a: Answers) -> PlayerCardStats {
        let now = card(a)
        let focus = Set(a.fix.compactMap { skillStat[$0] })
        let effort = Double(Swift.max(1, a.days.count)) * 2 + Double(a.minutes) / 20
        var s: [String: Int] = [:]
        for k in STATS { s[k] = clamp(Double(now.stats[k]!) + effort * (focus.contains(k) ? 2.1 : 1.5) + 2) }
        return PlayerCardStats(stats: s, ovr: Swift.max(now.ovr + 1, overall(s, a.position)))
    }
    static func tier(_ ovr: Int) -> Tier { ovr >= 75 ? .gold : ovr >= 65 ? .silver : .bronze }
}

// MARK: - drill picks from the answers

struct Scored: Identifiable, Hashable { let drill: Drill; let score: Double; let why: String; let feasible: Bool; var id: String { drill.id } }
struct WeekDay: Identifiable { let day: String; let drills: [Drill]; let minutes: Int; var id: String { day } }

enum Recommend {
    static let posCats: [String: [String: Double]] = [
        "ST": ["Shooting": 3, "First touch": 2, "Dribbling": 1.5, "Ball mastery": 1, "Awareness": 1],
        "LW": ["Dribbling": 3, "Shooting": 2, "Ball mastery": 1.5, "Fitness": 1, "First touch": 1],
        "RW": ["Dribbling": 3, "Shooting": 2, "Ball mastery": 1.5, "Fitness": 1, "First touch": 1],
        "CAM": ["First touch": 2.5, "Passing": 2, "Awareness": 2, "Dribbling": 1.5, "Shooting": 1.5],
        "LM": ["Dribbling": 2, "Passing": 2, "Fitness": 1.5, "First touch": 1.5, "Shooting": 1],
        "RM": ["Dribbling": 2, "Passing": 2, "Fitness": 1.5, "First touch": 1.5, "Shooting": 1],
        "CM": ["Passing": 3, "Awareness": 2.5, "First touch": 2, "Ball mastery": 1, "Fitness": 1],
        "CDM": ["Passing": 2.5, "Defending": 2.5, "Awareness": 2, "First touch": 1, "Fitness": 1],
        "LWB": ["Fitness": 2, "Defending": 2, "Dribbling": 1.5, "Passing": 1.5, "First touch": 1],
        "RWB": ["Fitness": 2, "Defending": 2, "Dribbling": 1.5, "Passing": 1.5, "First touch": 1],
        "LB": ["Defending": 3, "Fitness": 2, "Passing": 1.5, "First touch": 1],
        "RB": ["Defending": 3, "Fitness": 2, "Passing": 1.5, "First touch": 1],
        "CB": ["Defending": 3, "Passing": 1.5, "Awareness": 1.5, "Fitness": 1],
        "GK": ["Goalkeeping": 4, "Fitness": 1.5, "Passing": 1],
    ]
    static let levelTarget: [String: Double] = ["Just for fun": 1.5, "School team": 2, "Club": 3, "Academy": 3.5, "College": 4, "Semi-pro +": 4.5]

    static func canDo(_ d: Drill, _ a: Answers) -> Bool {
        let gear = Set(a.gear.map { $0.lowercased() })
        let needGear = d.needs.filter { !["Solo", "Partner", "Group"].contains($0) }
        if !needGear.allSatisfy({ gear.contains($0.lowercased()) }) { return false }
        if d.who == "Partner" && a.with == "Solo" { return false }
        if d.who == "Group" && a.with != "Team" { return false }
        return true
    }

    static func score(_ d: Drill, _ a: Answers) -> Scored {
        var score = 0.0
        var reasons: [(Double, String)] = []
        for (i, f) in a.fix.enumerated() where d.fixes.contains(f) {
            let v = Double(5 - i)
            score += v
            reasons.append((v, "Fixes your \(f.lowercased())"))
        }
        if let fear = a.fear, d.fears?.contains(fear) == true {
            score += 3
            reasons.append((3, "For \"\(fear.lowercased())\""))
        }
        let pw = posCats[a.position]?[d.skill] ?? 0
        score += pw
        if pw >= 2 { reasons.append((pw, "Built for \(a.positionName.lowercased())s")) }
        if d.skill == "Goalkeeping" && a.position != "GK" { score -= 8 }
        let target = levelTarget[a.level ?? ""] ?? 2.5
        let gap = abs(Double(d.level) - target)
        if gap > 1 { score -= gap - 1 }
        if d.min > a.minutes { score -= 3 }
        let feasible = canDo(d, a)
        if !feasible { score -= 6 }
        if a.best.contains(where: { d.fixes.contains($0) }) && !a.fix.contains(where: { d.fixes.contains($0) }) { score -= 1 }
        reasons.sort { $0.0 > $1.0 }
        let why = reasons.first?.1 ?? (d.level <= 2 ? "A solid base" : "Good for your level")
        return Scored(drill: d, score: score, why: why, feasible: feasible)
    }

    static func top(_ a: Answers, _ n: Int = 8) -> [Scored] {
        Array(Library.shared.drills.map { score($0, a) }.sorted { $0.score > $1.score }.filter(\.feasible).prefix(n))
    }

    /// Their first week: training days filled to their minutes from the picks, rotating so no two days match.
    static func week(_ a: Answers) -> [WeekDay] {
        var pool: [Drill] = a.drills.filter { Library.shared.has($0) }.map { Library.shared.drill($0) }
        for s in top(a) where !pool.contains(s.drill) { pool.append(s.drill) }
        if pool.isEmpty { pool = [Library.shared.drills[0]] }
        var cursor = 0
        return DAYS.filter { a.days.contains($0) }.map { day in
            var drills: [Drill] = []
            var minutes = 0
            var tries = 0
            while Double(minutes) < Double(a.minutes) * 0.85 && drills.count < 4 && tries < pool.count {
                let d = pool[cursor % pool.count]
                cursor += 1
                tries += 1
                if drills.contains(d) { continue }
                if minutes + d.min > a.minutes + 4 && !drills.isEmpty { continue }
                drills.append(d)
                minutes += d.min
            }
            return WeekDay(day: day, drills: drills, minutes: minutes)
        }
    }
}
