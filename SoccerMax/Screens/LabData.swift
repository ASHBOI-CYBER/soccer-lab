// SOCCER LAB data for the Training, Film and Nutrition tabs (2026-11-12). Everything here stays on the phone, in
// UserDefaults as one small JSON blob per area: no server, no AI service. The "coach" is a set of plain rules:
//   TRAINING  today's session = a warm-up + ball work everyone does + drills for the position picked in onboarding.
//   FILM      the player tags what went wrong in a clip; each mistake maps to drills, which join the Fix List.
//   NUTRITION daily fuel targets from the player's own numbers, and a log of what they ate and drank.
import Foundation
import Observation
import SwiftUI

// MARK: - training plan rules

enum LabPlan {
    /// Ball work every player does, whatever their position.
    static let core = ["toe-taps", "foundations", "sole-rolls", "inside-outside", "juggling", "figure-8"]
    static let warmups = ["walking-knee-hug", "hamstring-sweep", "high-knee-runs"]

    /// Position code from onboarding -> the group whose drills fill the rest of the session.
    static func group(_ position: String) -> String {
        switch position {
        case "GK": return "Goalkeeper"
        case "CB", "LB", "RB", "LWB", "RWB": return "Defender"
        case "CDM", "CM", "LM", "RM": return "Midfielder"
        default: return "Attacker"
        }
    }

    static func focus(_ group: String) -> [String] {
        switch group {
        case "Goalkeeper": return ["gk-set-and-catch", "gk-low-dive", "gk-angle-shuffle", "wall-passes", "side-plank", "glute-bridge"]
        case "Defender": return ["jockey-shuffle", "recovery-run", "long-pass-target", "wall-passes", "repeat-sprints", "front-plank"]
        case "Midfielder": return ["wall-passes", "scan-and-turn", "long-pass-target", "wall-first-touch", "figure-8", "diagonals"]
        default: return ["laces-strike", "touch-and-finish", "stop-and-go", "cone-slalom", "speed-dribble", "wall-first-touch"]
        }
    }

    /// Today's six drills. The day of the year turns the lists, so tomorrow is different and the week covers them all.
    static func today(position: String, date: Date = Date()) -> [Drill] {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 1
        let lib = Library.shared
        var ids: [String] = [warmups[day % warmups.count]]
        ids += pick(core, 2, from: day)
        ids += pick(focus(group(position)), 3, from: day)
        var seen = Set<String>()
        return ids.filter { lib.has($0) && seen.insert($0).inserted }.map { lib.drill($0) }
    }

    private static func pick(_ list: [String], _ n: Int, from start: Int) -> [String] {
        guard !list.isEmpty else { return [] }
        return (0..<min(n, list.count)).map { list[(start + $0) % list.count] }
    }
}

// MARK: - film: mistakes and the drills that fix them

struct FilmMistake: Identifiable, Hashable {
    let id: String
    let label: String
    let area: String
    /// Drill ids from the library that work on this.
    let drills: [String]
    /// Only shown to goalkeepers.
    var keeper = false
}

enum FilmRules {
    static let all: [FilmMistake] = [
        FilmMistake(id: "pass-soft", label: "Pass too soft or short", area: "Passing", drills: ["wall-passes", "weak-foot-laces"]),
        FilmMistake(id: "pass-wide", label: "Pass off target", area: "Passing", drills: ["wall-passes", "long-pass-target"]),
        FilmMistake(id: "pass-slow", label: "Held the ball too long", area: "Passing", drills: ["scan-and-turn", "wall-first-touch"]),
        FilmMistake(id: "touch-heavy", label: "Heavy first touch", area: "First touch", drills: ["wall-first-touch", "juggling"]),
        FilmMistake(id: "touch-blind", label: "Didn't look before receiving", area: "First touch", drills: ["scan-and-turn"]),
        FilmMistake(id: "dribble-lost", label: "Lost the ball dribbling", area: "Dribbling", drills: ["cone-slalom", "foundations"]),
        FilmMistake(id: "dribble-pace", label: "No change of pace", area: "Dribbling", drills: ["stop-and-go", "speed-dribble"]),
        FilmMistake(id: "weak-foot", label: "Avoided my weak foot", area: "Dribbling", drills: ["weak-foot-laces", "inside-outside"]),
        FilmMistake(id: "shot-wide", label: "Shot off target", area: "Shooting", drills: ["laces-strike"]),
        FilmMistake(id: "shot-rushed", label: "Rushed the finish", area: "Shooting", drills: ["touch-and-finish"]),
        FilmMistake(id: "shot-weak", label: "Shot had no power", area: "Shooting", drills: ["laces-strike", "glute-bridge"]),
        FilmMistake(id: "def-beaten", label: "Beaten one on one", area: "Defending", drills: ["jockey-shuffle"]),
        FilmMistake(id: "def-dived", label: "Dived into the tackle", area: "Defending", drills: ["jockey-shuffle", "recovery-run"]),
        FilmMistake(id: "def-recover", label: "Slow to get back", area: "Defending", drills: ["recovery-run", "repeat-sprints"]),
        FilmMistake(id: "fit-tired", label: "Tired late in the game", area: "Fitness", drills: ["diagonals", "repeat-sprints"]),
        FilmMistake(id: "fit-sprint", label: "Lost the sprint", area: "Fitness", drills: ["flying-20s", "strides"]),
        FilmMistake(id: "gk-dive", label: "Dive was late or short", area: "Goalkeeping", drills: ["gk-low-dive", "glute-bridge"], keeper: true),
        FilmMistake(id: "gk-catch", label: "Dropped or spilled the ball", area: "Goalkeeping", drills: ["gk-set-and-catch"], keeper: true),
        FilmMistake(id: "gk-position", label: "Out of position for the shot", area: "Goalkeeping", drills: ["gk-angle-shuffle", "gk-set-and-catch"], keeper: true),
    ]

    /// What this player is offered: keepers see keeper mistakes first; everyone else never sees them.
    static func list(position: String) -> [FilmMistake] {
        position == "GK" ? all.filter(\.keeper) + all.filter { !$0.keeper } : all.filter { !$0.keeper }
    }
    static func areas(position: String) -> [String] {
        var out: [String] = []
        for m in list(position: position) where !out.contains(m.area) { out.append(m.area) }
        return out
    }
    static func find(_ id: String) -> FilmMistake? { all.first { $0.id == id } }
    /// The drills for a set of mistakes, each once, in order.
    static func drills(for mistakes: [String]) -> [String] {
        var out: [String] = []
        for id in mistakes { for d in find(id)?.drills ?? [] where !out.contains(d) && Library.shared.has(d) { out.append(d) } }
        return out
    }
}

/// One yes/no question about the clip. The answer that means "this went wrong" (`problemIs`) points at a mistake.
struct FilmQuestion: Identifiable, Hashable {
    let id: String
    let text: String
    /// true = answering Yes is the problem; false = answering No is.
    let problemIs: Bool
    let mistake: String
}

/// A part of the game the clip shows. The player picks the ones in their clip and only gets those questions.
struct FilmMoment: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String
    let questions: [FilmQuestion]
    var keeper = false
}

/// The guided review (2026-11-12): the app asks, the player answers yes or no, and the app says what to work on.
/// Still plain rules, no AI: each answer maps to one entry in FilmRules.all.
enum FilmGuide {
    static let moments: [FilmMoment] = [
        FilmMoment(id: "keeper", title: "In goal", icon: "hand.raised.fill", questions: [
            FilmQuestion(id: "k1", text: "Did the ball go past you before you got down to it?", problemIs: true, mistake: "gk-dive"),
            FilmQuestion(id: "k2", text: "Did the ball come back out of your hands?", problemIs: true, mistake: "gk-catch"),
            FilmQuestion(id: "k3", text: "Were you in the middle of the angle when the shot came?", problemIs: false, mistake: "gk-position"),
        ], keeper: true),
        FilmMoment(id: "receive", title: "Receiving the ball", icon: "arrow.down.to.line", questions: [
            FilmQuestion(id: "r1", text: "Did the ball bounce away from you when it arrived?", problemIs: true, mistake: "touch-heavy"),
            FilmQuestion(id: "r2", text: "Did you look around before the ball reached you?", problemIs: false, mistake: "touch-blind"),
        ]),
        FilmMoment(id: "pass", title: "Passing", icon: "arrow.up.right", questions: [
            FilmQuestion(id: "p1", text: "Did your pass stop short or get cut out?", problemIs: true, mistake: "pass-soft"),
            FilmQuestion(id: "p2", text: "Did your pass go to your teammate's feet or into their run?", problemIs: false, mistake: "pass-wide"),
            FilmQuestion(id: "p3", text: "Did you keep the ball while a teammate was free?", problemIs: true, mistake: "pass-slow"),
        ]),
        FilmMoment(id: "dribble", title: "Dribbling", icon: "figure.run", questions: [
            FilmQuestion(id: "d1", text: "Did a defender take the ball off you?", problemIs: true, mistake: "dribble-lost"),
            FilmQuestion(id: "d2", text: "Did you change speed to get away from them?", problemIs: false, mistake: "dribble-pace"),
            FilmQuestion(id: "d3", text: "Did you turn away from your weaker foot when it was the better side?", problemIs: true, mistake: "weak-foot"),
        ]),
        FilmMoment(id: "shoot", title: "Shooting", icon: "scope", questions: [
            FilmQuestion(id: "s1", text: "Was your shot on target?", problemIs: false, mistake: "shot-wide"),
            FilmQuestion(id: "s2", text: "Did you shoot before you were balanced?", problemIs: true, mistake: "shot-rushed"),
            FilmQuestion(id: "s3", text: "Did the shot have enough power to trouble the keeper?", problemIs: false, mistake: "shot-weak"),
        ]),
        FilmMoment(id: "defend", title: "Defending", icon: "shield.fill", questions: [
            FilmQuestion(id: "f1", text: "Did the attacker get past you?", problemIs: true, mistake: "def-beaten"),
            FilmQuestion(id: "f2", text: "Did you lunge in and miss the ball?", problemIs: true, mistake: "def-dived"),
            FilmQuestion(id: "f3", text: "Did you get back behind the ball quickly after your team lost it?", problemIs: false, mistake: "def-recover"),
        ]),
        FilmMoment(id: "fitness", title: "Late in the game", icon: "timer", questions: [
            FilmQuestion(id: "t1", text: "Were you slower at the end than at the start?", problemIs: true, mistake: "fit-tired"),
            FilmQuestion(id: "t2", text: "Did an opponent beat you to a ball you both ran for?", problemIs: true, mistake: "fit-sprint"),
        ]),
    ]

    static func list(position: String) -> [FilmMoment] { moments.filter { !$0.keeper || position == "GK" } }

    /// The mistakes the answers point to, in the order the questions are asked.
    static func mistakes(moments picked: Set<String>, answers: [String: Bool], position: String) -> [String] {
        var out: [String] = []
        for m in list(position: position) where picked.contains(m.id) {
            for q in m.questions {
                if let a = answers[q.id], a == q.problemIs, !out.contains(q.mistake) { out.append(q.mistake) }
            }
        }
        return out
    }

    /// What the coach says about each mistake: what is happening and the one thing to change.
    static let feedback: [String: String] = [
        "pass-soft": "Your passes are dying before they arrive. Strike through the middle of the ball and follow through to your target.",
        "pass-wide": "Your passes are missing the target. Point your standing foot where you want the ball to go.",
        "pass-slow": "You are holding the ball too long. Look before it arrives, so you already know your pass.",
        "touch-heavy": "Your first touch is getting away from you. Soften your foot as the ball arrives and take it into space.",
        "touch-blind": "You are receiving without knowing what is around you. Check over your shoulder while the ball is travelling.",
        "dribble-lost": "You are losing the ball when you dribble. Keep it closer with more, smaller touches.",
        "dribble-pace": "You are dribbling at one speed, which is easy to defend. Slow down, then explode past.",
        "weak-foot": "You are avoiding your weaker foot, so defenders know which way you will go. Use it every session.",
        "shot-wide": "Your shots are missing the goal. Keep your head over the ball and pick a corner before you strike.",
        "shot-rushed": "You are shooting before you are set. One good touch out of your feet first, then strike.",
        "shot-weak": "Your shots lack power. Lock your ankle, hit through the ball with your laces and land on your kicking foot.",
        "def-beaten": "Attackers are getting past you. Stay side-on, stay on your toes and let them make the first move.",
        "def-dived": "You are diving into tackles. Hold your ground and only go when their touch gets away from them.",
        "def-recover": "You are slow to get back when the ball is lost. Turn and sprint straight away, then slow down as you arrive.",
        "fit-tired": "You are fading late in games. Build your engine with repeated runs and short rests.",
        "fit-sprint": "You are losing races to the ball. Work on your top speed with short, full-effort sprints.",
        "gk-dive": "You are getting down late. Take a small step toward the ball first and lead with your hands.",
        "gk-catch": "The ball is coming out of your hands. Get your hands behind it, thumbs together, and bring it into your chest.",
        "gk-position": "You are off your angle when shots come. Keep moving so you are always on the line between ball and goal.",
    ]
}

struct FilmReview: Codable, Identifiable, Hashable {
    var id = UUID()
    var date = Date()
    var title: String
    var mistakes: [String]
    var note: String
    /// File name of the clip inside Documents/film, if one was attached.
    var clip: String?
    var drills: [String]
}

/// Where attached clips live: Documents/film/<name>. Not tied to the main thread.
enum FilmFiles {
    static var folder: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("film", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    static func url(_ name: String) -> URL { folder.appendingPathComponent(name) }
}

// MARK: - nutrition

struct FoodItem: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let serving: String
    let kcal: Int
    let protein: Double
    let carbs: Double
    let fat: Double
    let group: String
}

/// Common foods with rounded, typical values per serving. A guide for a training log, not a lab measurement.
enum Foods {
    static let groups = ["Meals", "Protein", "Carbs", "Fruit and veg", "Snacks", "Drinks"]
    static let all: [FoodItem] = [
        FoodItem(name: "Chicken and rice", serving: "1 plate", kcal: 550, protein: 40, carbs: 65, fat: 12, group: "Meals"),
        FoodItem(name: "Pasta with tomato sauce", serving: "1 bowl", kcal: 480, protein: 16, carbs: 85, fat: 8, group: "Meals"),
        FoodItem(name: "Beef burger", serving: "1 burger", kcal: 520, protein: 28, carbs: 40, fat: 27, group: "Meals"),
        FoodItem(name: "Pizza", serving: "2 slices", kcal: 560, protein: 24, carbs: 66, fat: 22, group: "Meals"),
        FoodItem(name: "Chicken wrap", serving: "1 wrap", kcal: 430, protein: 28, carbs: 42, fat: 15, group: "Meals"),
        FoodItem(name: "Rice and beans", serving: "1 plate", kcal: 450, protein: 16, carbs: 80, fat: 7, group: "Meals"),
        FoodItem(name: "Omelette", serving: "3 eggs", kcal: 290, protein: 19, carbs: 2, fat: 22, group: "Meals"),
        FoodItem(name: "Tuna sandwich", serving: "1 sandwich", kcal: 380, protein: 25, carbs: 38, fat: 13, group: "Meals"),
        FoodItem(name: "Chicken breast", serving: "1 piece, 150 g", kcal: 250, protein: 46, carbs: 0, fat: 5, group: "Protein"),
        FoodItem(name: "Eggs", serving: "2 eggs", kcal: 150, protein: 13, carbs: 1, fat: 10, group: "Protein"),
        FoodItem(name: "Salmon", serving: "1 fillet, 130 g", kcal: 270, protein: 28, carbs: 0, fat: 17, group: "Protein"),
        FoodItem(name: "Greek yogurt", serving: "1 pot, 170 g", kcal: 130, protein: 17, carbs: 6, fat: 4, group: "Protein"),
        FoodItem(name: "Lentils", serving: "1 cup cooked", kcal: 230, protein: 18, carbs: 40, fat: 1, group: "Protein"),
        FoodItem(name: "Beef mince", serving: "125 g cooked", kcal: 270, protein: 30, carbs: 0, fat: 16, group: "Protein"),
        FoodItem(name: "White rice", serving: "1 cup cooked", kcal: 205, protein: 4, carbs: 45, fat: 0, group: "Carbs"),
        FoodItem(name: "Pasta", serving: "1 cup cooked", kcal: 220, protein: 8, carbs: 43, fat: 1, group: "Carbs"),
        FoodItem(name: "Bread", serving: "2 slices", kcal: 160, protein: 6, carbs: 30, fat: 2, group: "Carbs"),
        FoodItem(name: "Oats", serving: "1 bowl with milk", kcal: 300, protein: 13, carbs: 45, fat: 8, group: "Carbs"),
        FoodItem(name: "Potato", serving: "1 medium, baked", kcal: 160, protein: 4, carbs: 37, fat: 0, group: "Carbs"),
        FoodItem(name: "Cereal with milk", serving: "1 bowl", kcal: 250, protein: 9, carbs: 45, fat: 4, group: "Carbs"),
        FoodItem(name: "Roti or chapati", serving: "2 pieces", kcal: 240, protein: 7, carbs: 44, fat: 4, group: "Carbs"),
        FoodItem(name: "Banana", serving: "1 medium", kcal: 105, protein: 1, carbs: 27, fat: 0, group: "Fruit and veg"),
        FoodItem(name: "Apple", serving: "1 medium", kcal: 95, protein: 0, carbs: 25, fat: 0, group: "Fruit and veg"),
        FoodItem(name: "Orange", serving: "1 medium", kcal: 60, protein: 1, carbs: 15, fat: 0, group: "Fruit and veg"),
        FoodItem(name: "Mixed salad", serving: "1 bowl", kcal: 60, protein: 3, carbs: 10, fat: 1, group: "Fruit and veg"),
        FoodItem(name: "Cooked vegetables", serving: "1 cup", kcal: 80, protein: 4, carbs: 14, fat: 1, group: "Fruit and veg"),
        FoodItem(name: "Dates", serving: "3 dates", kcal: 200, protein: 1, carbs: 54, fat: 0, group: "Fruit and veg"),
        FoodItem(name: "Peanut butter toast", serving: "1 slice", kcal: 190, protein: 7, carbs: 17, fat: 10, group: "Snacks"),
        FoodItem(name: "Mixed nuts", serving: "1 handful, 30 g", kcal: 180, protein: 5, carbs: 6, fat: 16, group: "Snacks"),
        FoodItem(name: "Protein bar", serving: "1 bar", kcal: 210, protein: 20, carbs: 22, fat: 7, group: "Snacks"),
        FoodItem(name: "Granola bar", serving: "1 bar", kcal: 120, protein: 2, carbs: 20, fat: 4, group: "Snacks"),
        FoodItem(name: "Crisps", serving: "1 small bag", kcal: 160, protein: 2, carbs: 15, fat: 10, group: "Snacks"),
        FoodItem(name: "Chocolate bar", serving: "1 bar, 45 g", kcal: 235, protein: 3, carbs: 26, fat: 13, group: "Snacks"),
        FoodItem(name: "Milk", serving: "1 glass, 250 ml", kcal: 150, protein: 8, carbs: 12, fat: 8, group: "Drinks"),
        FoodItem(name: "Chocolate milk", serving: "1 glass, 250 ml", kcal: 200, protein: 8, carbs: 26, fat: 7, group: "Drinks"),
        FoodItem(name: "Orange juice", serving: "1 glass, 250 ml", kcal: 110, protein: 2, carbs: 26, fat: 0, group: "Drinks"),
        FoodItem(name: "Sports drink", serving: "1 bottle, 500 ml", kcal: 130, protein: 0, carbs: 32, fat: 0, group: "Drinks"),
        FoodItem(name: "Protein shake", serving: "1 scoop with water", kcal: 120, protein: 24, carbs: 3, fat: 2, group: "Drinks"),
        FoodItem(name: "Fizzy drink", serving: "1 can, 330 ml", kcal: 140, protein: 0, carbs: 35, fat: 0, group: "Drinks"),
    ]
}

struct FoodEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var kcal: Int
    var protein: Double
    var carbs: Double
    var fat: Double
    var time = Date()
}

struct FuelDay: Codable, Hashable {
    var entries: [FoodEntry] = []
    /// Glasses of water (250 ml each).
    var water = 0

    var kcal: Int { entries.reduce(0) { $0 + $1.kcal } }
    var protein: Double { entries.reduce(0) { $0 + $1.protein } }
    var carbs: Double { entries.reduce(0) { $0 + $1.carbs } }
    var fat: Double { entries.reduce(0) { $0 + $1.fat } }
}

/// What the targets are worked out from. Nothing is asked for that isn't used.
struct FuelBody: Codable, Hashable {
    var weightKg: Double = 0
    var heightCm: Double = 0
    var age: Int = 0
    var trainingDays: Int = 3
    var isSet: Bool { weightKg > 0 && heightCm > 0 && age > 0 }
}

struct FuelTargets: Hashable {
    let kcal: Int
    let protein: Int
    let carbs: Int
    let fat: Int
    let water: Int

    /// Energy to train and recover on, never a diet: resting energy (Mifflin-St Jeor, the middle of its two
    /// constants) times an activity factor that rises with training days. Protein 1.6 g per kg, fat a quarter of
    /// the energy, carbohydrate the rest. Without the player's numbers, a typical active teenager's day.
    static func make(_ b: FuelBody) -> FuelTargets {
        guard b.isSet else { return FuelTargets(kcal: 2400, protein: 100, carbs: 330, fat: 70, water: 8) }
        let rest = 10 * b.weightKg + 6.25 * b.heightCm - 5 * Double(b.age) - 78
        let active = 1.4 + 0.075 * Double(min(max(b.trainingDays, 0), 7))
        let kcal = max(1800, min(4500, rest * active))
        let protein = 1.6 * b.weightKg
        let fat = kcal * 0.25 / 9
        let carbs = max(0, (kcal - protein * 4 - fat * 9) / 4)
        let water = Int((b.weightKg * 35 / 250).rounded())
        return FuelTargets(kcal: Int((kcal / 50).rounded()) * 50, protein: Int(protein.rounded()), carbs: Int(carbs.rounded()),
                           fat: Int(fat.rounded()), water: min(16, max(6, water)))
    }
}

// MARK: - the store

@MainActor @Observable
final class Lab {
    static let shared = Lab()

    /// Drills the player ticked off, by day ("2026-11-12" -> drill ids).
    var done: [String: [String]] { didSet { save(done, "lab.done.v1") } }
    /// Drills added by Film reviews, newest first. They stay until the player has done each one three times.
    var fixList: [String] { didSet { save(fixList, "lab.fix.v1") } }
    /// How many times each Fix List drill has been done.
    var fixCount: [String: Int] { didSet { save(fixCount, "lab.fixcount.v1") } }
    var reviews: [FilmReview] { didSet { save(reviews, "lab.film.v1") } }
    var fuel: [String: FuelDay] { didSet { save(fuel, "lab.fuel.v1") } }
    var body: FuelBody { didSet { save(body, "lab.body.v1") } }

    static let fixGoal = 3

    private init() {
        done = Self.load("lab.done.v1") ?? [:]
        fixList = Self.load("lab.fix.v1") ?? []
        fixCount = Self.load("lab.fixcount.v1") ?? [:]
        reviews = Self.load("lab.film.v1") ?? []
        fuel = Self.load("lab.fuel.v1") ?? [:]
        body = Self.load("lab.body.v1") ?? FuelBody()
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        guard let d = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }
    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let d = try? JSONEncoder().encode(value) { UserDefaults.standard.set(d, forKey: key) }
    }

    // training

    var today: String { dateKey(Date()) }
    func isDone(_ drill: String) -> Bool { done[today]?.contains(drill) == true }

    /// Tick a drill off for today: its minutes count toward the streak and stats, once per drill per day.
    func complete(_ drill: Drill, store: AppStore) {
        guard !isDone(drill.id) else { return }
        done[today, default: []].append(drill.id)
        store.logDrill(PlanItem(drill.id), seconds: Double(drill.min) * 60)
        if fixList.contains(drill.id) {
            let n = (fixCount[drill.id] ?? 0) + 1
            fixCount[drill.id] = n
            if n >= Self.fixGoal { fixList.removeAll { $0 == drill.id }; fixCount[drill.id] = nil }
        }
        // keep a month of ticks, not forever
        if done.count > 40 { for k in done.keys.sorted().dropLast(31) { done[k] = nil } }
    }

    // film

    /// Save a review: its drills go to the top of the Fix List. Returns the drills that were added.
    @discardableResult
    func add(_ review: FilmReview) -> [String] {
        reviews.insert(review, at: 0)
        var list = fixList
        for d in review.drills.reversed() {
            list.removeAll { $0 == d }
            list.insert(d, at: 0)
        }
        fixList = Array(list.prefix(12))
        return review.drills
    }

    func delete(_ review: FilmReview) {
        if let c = review.clip { try? FileManager.default.removeItem(at: FilmFiles.url(c)) }
        reviews.removeAll { $0.id == review.id }
    }

    // nutrition

    var targets: FuelTargets { FuelTargets.make(body) }
    var fuelToday: FuelDay { fuel[today] ?? FuelDay() }

    func eat(_ f: FoodItem, servings: Double = 1) {
        let e = FoodEntry(name: f.name, kcal: Int((Double(f.kcal) * servings).rounded()), protein: f.protein * servings,
                          carbs: f.carbs * servings, fat: f.fat * servings)
        var day = fuelToday
        day.entries.append(e)
        fuel[today] = day
        trimFuel()
    }
    func eat(custom name: String, kcal: Int, protein: Double, carbs: Double, fat: Double) {
        var day = fuelToday
        day.entries.append(FoodEntry(name: name, kcal: kcal, protein: protein, carbs: carbs, fat: fat))
        fuel[today] = day
        trimFuel()
    }
    func remove(_ e: FoodEntry) {
        var day = fuelToday
        day.entries.removeAll { $0.id == e.id }
        fuel[today] = day
    }
    func water(_ change: Int) {
        var day = fuelToday
        day.water = min(30, max(0, day.water + change))
        fuel[today] = day
    }
    private func trimFuel() {
        if fuel.count > 100 { for k in fuel.keys.sorted().dropLast(90) { fuel[k] = nil } }
    }
}

// MARK: - shared pieces

/// A dark rounded panel with the app's ink outline.
struct LabPanel<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(C.char800).overlay(shape.stroke(C.charInk, lineWidth: 2.5)))
    }
}

/// A small heading above a section: "TODAY'S SESSION".
struct LabKicker: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(F.round(13, .bold)).kerning(1.4).foregroundStyle(C.muted)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A filled bar: how far `value` is toward `goal`.
struct LabBar: View {
    let value: Double
    let goal: Double
    var color: Color = C.brand
    var body: some View {
        GeometryReader { g in
            let f = goal > 0 ? min(1, max(0, value / goal)) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(C.char950)
                Capsule().fill(color).frame(width: max(f > 0 ? 8 : 0, g.size.width * f))
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}
