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
        case "Goalkeeper": return ["gk-set-and-catch", "gk-low-dive", "gk-angle-shuffle", "gk-throw-target", "wall-passes", "side-plank", "glute-bridge"]
        case "Defender": return ["jockey-shuffle", "recovery-run", "press-and-recover", "long-pass-target", "wall-passes", "repeat-sprints", "front-plank"]
        case "Midfielder": return ["wall-passes", "scan-and-turn", "one-touch-wall", "long-pass-target", "press-and-recover", "wall-first-touch", "figure-8", "diagonals"]
        default: return ["laces-strike", "touch-and-finish", "check-and-go", "stop-and-go", "shield-and-turn", "cone-slalom", "speed-dribble", "wall-first-touch"]
        }
    }

    /// Recovery days (2026-11-18, Fasih: "5 days a week, so two days should show recovery day"): the weekdays a player
    /// who trains `days` days a week rests, spread out so no two hard days pile up. Test builds: `-route ...:rest`
    /// makes today a recovery day.
    static func restDays(training days: Int) -> Set<String> {
        switch days {
        case ...2: return ["Mon", "Wed", "Thu", "Fri", "Sun"]   // trains Tue and Sat
        case 3: return ["Tue", "Thu", "Sat", "Sun"]             // trains Mon, Wed, Fri
        case 4: return ["Wed", "Fri", "Sun"]                    // trains Mon, Tue, Thu, Sat
        case 5: return ["Wed", "Sun"]
        case 6: return ["Sun"]
        default: return []
        }
    }
    static func isRest(_ day: String, training days: Int) -> Bool {
        if DebugRoute.parts.contains("rest"), day == todayKey() { return true }
        return restDays(training: days).contains(day)
    }

    /// Light mobility for a recovery day: optional, easy on the body.
    static let recovery = ["walking-knee-hug", "hamstring-sweep", "glute-bridge"]

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
        FilmMistake(id: "pass-touches", label: "Too many touches before passing", area: "Passing", drills: ["one-touch-wall", "wall-passes"]),
        FilmMistake(id: "switch-short", label: "Long pass fell short", area: "Passing", drills: ["long-pass-target", "weak-foot-laces"]),
        FilmMistake(id: "move-static", label: "Standing still off the ball", area: "Movement", drills: ["check-and-go", "strides"]),
        FilmMistake(id: "move-timing", label: "Run was mistimed", area: "Movement", drills: ["check-and-go", "flying-20s"]),
        FilmMistake(id: "hold-lost", label: "Lost it with a defender behind me", area: "Movement", drills: ["shield-and-turn", "front-plank"]),
        FilmMistake(id: "press-late", label: "Late to close down", area: "Defending", drills: ["press-and-recover", "repeat-sprints"]),
        FilmMistake(id: "track-lost", label: "Lost the player I was marking", area: "Defending", drills: ["recovery-run", "jockey-shuffle"]),
        FilmMistake(id: "build-panic", label: "Gave it away under pressure", area: "Passing", drills: ["wall-first-touch", "scan-and-turn"]),
        FilmMistake(id: "clear-weak", label: "Clearance didn't clear the danger", area: "Defending", drills: ["long-pass-target", "laces-strike"]),
        FilmMistake(id: "gk-set", label: "Not set when the shot came", area: "Goalkeeping", drills: ["gk-set-and-catch", "gk-angle-shuffle"], keeper: true),
        FilmMistake(id: "gk-dist", label: "Throw or kick didn't find a teammate", area: "Goalkeeping", drills: ["gk-throw-target", "long-pass-target"], keeper: true),
        FilmMistake(id: "gk-feet", label: "Shaky with the ball at my feet", area: "Goalkeeping", drills: ["wall-passes", "wall-first-touch"], keeper: true),
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

    init(_ id: String, _ text: String, yes mistake: String) { self.id = id; self.text = text; problemIs = true; self.mistake = mistake }
    init(_ id: String, _ text: String, no mistake: String) { self.id = id; self.text = text; problemIs = false; self.mistake = mistake }
}

/// A part of the game the clip shows. Each has a pool of questions; a review asks a few of them, picked fresh each
/// time, so two reviews of the same kind of clip don't read the same.
struct FilmMoment: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String
    let pool: [FilmQuestion]
}

/// The guided review (2026-11-12): the app asks, the player answers yes or no, and the app says what to work on and
/// which drills to do. Plain rules, no AI: each answer maps to one entry in FilmRules.all. What is asked depends on
/// the position picked in onboarding (LabPlan.group): a striker is asked about finishing and runs, a centre back
/// about duels and playing out, a keeper about saves, angles and distribution.
enum FilmGuide {
    /// How many questions a review asks for each part of the game picked.
    static let perMoment = 4

    // shared by every outfield player
    private static let receive = FilmMoment(id: "receive", title: "Receiving the ball", icon: "arrow.down.to.line", pool: [
        FilmQuestion("r1", "Did the ball bounce away from you when it arrived?", yes: "touch-heavy"),
        FilmQuestion("r2", "Did you look around before the ball reached you?", no: "touch-blind"),
        FilmQuestion("r3", "Did your first touch take you away from the nearest defender?", no: "touch-heavy"),
        FilmQuestion("r4", "Did you have to chase your own first touch?", yes: "touch-heavy"),
        FilmQuestion("r5", "Did you know where your next pass was before you got the ball?", no: "touch-blind"),
        FilmQuestion("r6", "Did you receive it standing flat, facing your own goal?", yes: "touch-blind"),
    ])
    private static let pass = FilmMoment(id: "pass", title: "Passing", icon: "arrow.up.right", pool: [
        FilmQuestion("p1", "Did your pass stop short or get cut out?", yes: "pass-soft"),
        FilmQuestion("p2", "Did your pass go to your teammate's feet or into their run?", no: "pass-wide"),
        FilmQuestion("p3", "Did you keep the ball while a teammate was free?", yes: "pass-slow"),
        FilmQuestion("p4", "Did your teammate have to stretch or stop to reach your pass?", yes: "pass-wide"),
        FilmQuestion("p5", "Did you take more touches than you needed before passing?", yes: "pass-touches"),
        FilmQuestion("p6", "Could you have played it first time?", yes: "pass-touches"),
        FilmQuestion("p7", "Did you use your weaker foot when the pass was on that side?", no: "weak-foot"),
    ])
    private static let dribble = FilmMoment(id: "dribble", title: "Dribbling and taking players on", icon: "figure.run", pool: [
        FilmQuestion("d1", "Did a defender take the ball off you?", yes: "dribble-lost"),
        FilmQuestion("d2", "Did you change speed to get away from them?", no: "dribble-pace"),
        FilmQuestion("d3", "Did you turn away from your weaker foot when it was the better side?", yes: "weak-foot"),
        FilmQuestion("d4", "Was the ball more than a step away from you when the defender arrived?", yes: "dribble-lost"),
        FilmQuestion("d5", "Did you have your head down the whole time you ran with it?", yes: "touch-blind"),
        FilmQuestion("d6", "Did you slow down, then burst past?", no: "dribble-pace"),
    ])
    private static let fitness = FilmMoment(id: "fitness", title: "Late in the game", icon: "timer", pool: [
        FilmQuestion("t1", "Were you slower at the end than at the start?", yes: "fit-tired"),
        FilmQuestion("t2", "Did an opponent beat you to a ball you both ran for?", yes: "fit-sprint"),
        FilmQuestion("t3", "Did you walk when your team needed you to run?", yes: "fit-tired"),
        FilmQuestion("t4", "Could you still sprint flat out in the last ten minutes?", no: "fit-tired"),
        FilmQuestion("t5", "Were you first to the loose balls near you?", no: "fit-sprint"),
    ])

    // attackers
    private static let finish = FilmMoment(id: "finish", title: "Finishing", icon: "scope", pool: [
        FilmQuestion("s1", "Was your shot on target?", no: "shot-wide"),
        FilmQuestion("s2", "Did you shoot before you were balanced?", yes: "shot-rushed"),
        FilmQuestion("s3", "Did the shot have enough power to trouble the keeper?", no: "shot-weak"),
        FilmQuestion("s4", "Did you pick a corner before you hit it?", no: "shot-wide"),
        FilmQuestion("s5", "Did your touch before the shot set it up well?", no: "shot-rushed"),
        FilmQuestion("s6", "Did the shot fly over the bar?", yes: "shot-wide"),
        FilmQuestion("s7", "Did you avoid shooting with your weaker foot?", yes: "weak-foot"),
    ])
    private static let movement = FilmMoment(id: "movement", title: "Runs off the ball", icon: "arrow.triangle.turn.up.right.diamond.fill", pool: [
        FilmQuestion("m1", "Were you standing still when your teammate looked up?", yes: "move-static"),
        FilmQuestion("m2", "Did you make a run that gave the passer an option?", no: "move-static"),
        FilmQuestion("m3", "Did you start your run too early and get caught offside or marked?", yes: "move-timing"),
        FilmQuestion("m4", "Did you move one way first to lose your marker, then go the other?", no: "move-timing"),
        FilmQuestion("m5", "Were you hiding behind a defender where the ball couldn't reach you?", yes: "move-static"),
        FilmQuestion("m6", "Did you arrive in the box as the ball did?", no: "move-timing"),
    ])
    private static let holdUp = FilmMoment(id: "holdup", title: "Holding the ball up", icon: "shield.lefthalf.filled", pool: [
        FilmQuestion("h1", "Did the defender win the ball from behind you?", yes: "hold-lost"),
        FilmQuestion("h2", "Did you get your body between the defender and the ball?", no: "hold-lost"),
        FilmQuestion("h3", "Were you knocked off the ball easily?", yes: "hold-lost"),
        FilmQuestion("h4", "Did you keep it long enough for a teammate to arrive?", no: "hold-lost"),
    ])

    // midfielders
    private static let pressure = FilmMoment(id: "pressure", title: "On the ball under pressure", icon: "person.2.wave.2.fill", pool: [
        FilmQuestion("u1", "Did you look over your shoulder before you received it?", no: "touch-blind"),
        FilmQuestion("u2", "Did you get caught on the ball?", yes: "pass-slow"),
        FilmQuestion("u3", "Did you turn into a defender you hadn't seen?", yes: "touch-blind"),
        FilmQuestion("u4", "Did you play out of the pressure with one or two touches?", no: "pass-touches"),
        FilmQuestion("u5", "Did you receive on your back foot, half turned?", no: "touch-heavy"),
        FilmQuestion("u6", "Did you just kick it away because you were closed down?", yes: "build-panic"),
    ])
    private static let switchPlay = FilmMoment(id: "switch", title: "Long passes and switches", icon: "arrow.left.arrow.right", pool: [
        FilmQuestion("w1", "Did your long pass reach your teammate?", no: "switch-short"),
        FilmQuestion("w2", "Did your long pass fall short or get intercepted?", yes: "switch-short"),
        FilmQuestion("w3", "Did you see the free player on the far side?", no: "touch-blind"),
        FilmQuestion("w4", "Did the pass get off the ground when it needed to?", no: "switch-short"),
        FilmQuestion("w5", "Did it take you several touches to set up the long pass?", yes: "pass-touches"),
    ])
    private static let press = FilmMoment(id: "press", title: "Pressing and winning it back", icon: "bolt.horizontal.fill", pool: [
        FilmQuestion("q1", "Did you close the player down as the ball travelled to them?", no: "press-late"),
        FilmQuestion("q2", "Did they have time to look up and pick a pass?", yes: "press-late"),
        FilmQuestion("q3", "Did you sprint in, then slow down before you got there?", no: "def-dived"),
        FilmQuestion("q4", "Did you react straight away when your team lost the ball?", no: "def-recover"),
        FilmQuestion("q5", "Did they play around you easily?", yes: "press-late"),
    ])

    // defenders
    private static let duel = FilmMoment(id: "duel", title: "One on one defending", icon: "shield.fill", pool: [
        FilmQuestion("f1", "Did the attacker get past you?", yes: "def-beaten"),
        FilmQuestion("f2", "Did you lunge in and miss the ball?", yes: "def-dived"),
        FilmQuestion("f3", "Were you side-on, not square, as they came at you?", no: "def-beaten"),
        FilmQuestion("f4", "Did you show them away from goal?", no: "def-beaten"),
        FilmQuestion("f5", "Did you go to ground when you could have stayed on your feet?", yes: "def-dived"),
        FilmQuestion("f6", "Were you close enough to touch them when they received it?", no: "press-late"),
        FilmQuestion("f7", "Did they turn you with one change of direction?", yes: "def-beaten"),
    ])
    private static let track = FilmMoment(id: "track", title: "Tracking runners and getting back", icon: "figure.run.circle.fill", pool: [
        FilmQuestion("g1", "Did you get back behind the ball quickly after your team lost it?", no: "def-recover"),
        FilmQuestion("g2", "Did the player you were marking get free behind you?", yes: "track-lost"),
        FilmQuestion("g3", "Were you watching only the ball when your runner went?", yes: "track-lost"),
        FilmQuestion("g4", "Did you lose a foot race to the attacker?", yes: "fit-sprint"),
        FilmQuestion("g5", "Could you see both the ball and your player?", no: "track-lost"),
        FilmQuestion("g6", "Did you jog back when you needed to sprint?", yes: "def-recover"),
    ])
    private static let buildOut = FilmMoment(id: "buildout", title: "Playing out from the back", icon: "arrow.up.forward.circle.fill", pool: [
        FilmQuestion("b1", "Did you kick it long because you were closed down?", yes: "build-panic"),
        FilmQuestion("b2", "Did your first touch give you room to pass?", no: "touch-heavy"),
        FilmQuestion("b3", "Did you pass to a teammate who was already marked?", yes: "touch-blind"),
        FilmQuestion("b4", "Did your pass reach the midfielder's feet?", no: "pass-soft"),
        FilmQuestion("b5", "Did you look for a pass before the ball came to you?", no: "touch-blind"),
        FilmQuestion("b6", "Did you lose the ball in your own third?", yes: "build-panic"),
    ])
    private static let clear = FilmMoment(id: "clear", title: "Clearing danger", icon: "arrow.up.to.line", pool: [
        FilmQuestion("c1", "Did your clearance go straight back to the other team near your box?", yes: "clear-weak"),
        FilmQuestion("c2", "Did your clearance get height and distance?", no: "clear-weak"),
        FilmQuestion("c3", "Did you swing at it with your weaker foot and miss-hit it?", yes: "weak-foot"),
        FilmQuestion("c4", "Did you clear it to the side, away from the middle?", no: "clear-weak"),
    ])

    // goalkeepers
    private static let shotStop = FilmMoment(id: "shotstop", title: "Shot stopping", icon: "hand.raised.fill", pool: [
        FilmQuestion("k1", "Did the ball go past you before you got down to it?", yes: "gk-dive"),
        FilmQuestion("k2", "Were your feet set and still when the shot was hit?", no: "gk-set"),
        FilmQuestion("k3", "Were you still moving when they struck it?", yes: "gk-set"),
        FilmQuestion("k4", "Did you take a step toward the ball before you dived?", no: "gk-dive"),
        FilmQuestion("k5", "Did you fall backward instead of going across?", yes: "gk-dive"),
        FilmQuestion("k6", "Did a low shot go under your body?", yes: "gk-dive"),
    ])
    private static let handling = FilmMoment(id: "handling", title: "Handling", icon: "hands.and.sparkles.fill", pool: [
        FilmQuestion("n1", "Did the ball come back out of your hands?", yes: "gk-catch"),
        FilmQuestion("n2", "Did you get your body behind the ball as well as your hands?", no: "gk-catch"),
        FilmQuestion("n3", "Did you push a shot back into the middle of the box?", yes: "gk-catch"),
        FilmQuestion("n4", "Did you bring the ball into your chest after you caught it?", no: "gk-catch"),
    ])
    private static let angles = FilmMoment(id: "angles", title: "Positioning", icon: "angle", pool: [
        FilmQuestion("a1", "Were you in the middle of the angle when the shot came?", no: "gk-position"),
        FilmQuestion("a2", "Were you standing on your goal line when you could have come out?", yes: "gk-position"),
        FilmQuestion("a3", "Did the shot go in at the post nearest to you?", yes: "gk-position"),
        FilmQuestion("a4", "Did you move across your goal as the ball moved?", no: "gk-position"),
        FilmQuestion("a5", "Did you cross your feet when you moved across?", yes: "gk-set"),
    ])
    private static let distribution = FilmMoment(id: "distribution", title: "Throws and kicks", icon: "arrow.up.right.circle.fill", pool: [
        FilmQuestion("x1", "Did your throw or kick reach a teammate?", no: "gk-dist"),
        FilmQuestion("x2", "Did you give the ball straight back to the other team?", yes: "gk-dist"),
        FilmQuestion("x3", "Did you look for a free teammate before you released it?", no: "touch-blind"),
        FilmQuestion("x4", "Did your goal kick get past the first line of players?", no: "gk-dist"),
        FilmQuestion("x5", "Did you take too long and lose the chance to start an attack?", yes: "pass-slow"),
    ])
    private static let keeperFeet = FilmMoment(id: "feet", title: "With the ball at your feet", icon: "shoeprints.fill", pool: [
        FilmQuestion("y1", "Was your first touch from a back pass under control?", no: "gk-feet"),
        FilmQuestion("y2", "Did you kick it away when a simple pass was on?", yes: "build-panic"),
        FilmQuestion("y3", "Did your pass reach your defender's feet?", no: "gk-feet"),
        FilmQuestion("y4", "Were you comfortable using either foot?", no: "weak-foot"),
    ])

    /// The parts of the game offered to a player, most relevant for their position first.
    static func list(position: String) -> [FilmMoment] {
        switch LabPlan.group(position) {
        case "Goalkeeper": return [shotStop, handling, angles, distribution, keeperFeet]
        case "Defender": return [duel, track, buildOut, clear, pass, receive, fitness]
        case "Midfielder": return [pressure, pass, switchPlay, press, dribble, finish, fitness]
        default: return [finish, movement, holdUp, dribble, receive, pass, fitness]
        }
    }

    /// A fresh pick of questions for one part of the game.
    static func ask(_ m: FilmMoment) -> [FilmQuestion] { Array(m.pool.shuffled().prefix(perMoment)) }

    /// The mistakes the answers point to, in the order the questions were asked.
    static func mistakes(asked: [FilmQuestion], answers: [String: Bool]) -> [String] {
        var out: [String] = []
        for q in asked {
            if let a = answers[q.id], a == q.problemIs, !out.contains(q.mistake) { out.append(q.mistake) }
        }
        return out
    }

    /// What the coach says about each mistake: what is happening and the one thing to change.
    static let feedback: [String: String] = [
        "pass-soft": "Your passes are dying before they arrive. Strike through the middle of the ball and follow through to your target.",
        "pass-wide": "Your passes are missing the target. Point your standing foot where you want the ball to go.",
        "pass-slow": "You are holding the ball too long. Look before it arrives, so you already know your pass.",
        "pass-touches": "You are taking too many touches. Decide early and play it in one or two.",
        "touch-heavy": "Your first touch is getting away from you. Soften your foot as the ball arrives and take it into space.",
        "touch-blind": "You are playing without knowing what is around you. Check over your shoulder while the ball is travelling.",
        "dribble-lost": "You are losing the ball when you dribble. Keep it closer with more, smaller touches.",
        "dribble-pace": "You are dribbling at one speed, which is easy to defend. Slow down, then explode past.",
        "weak-foot": "You are avoiding your weaker foot, so opponents know which way you will go. Use it every session.",
        "shot-wide": "Your shots are missing the goal. Keep your head over the ball and pick a corner before you strike.",
        "shot-rushed": "You are shooting before you are set. One good touch out of your feet first, then strike.",
        "shot-weak": "Your shots lack power. Lock your ankle, hit through the ball with your laces and land on your kicking foot.",
        "move-static": "You are standing still when your team has the ball. Keep moving so the passer always has you as an option.",
        "move-timing": "Your runs are mistimed. Move away first to lose your marker, then go as the passer looks up.",
        "hold-lost": "You are losing the ball with a defender on your back. Get side-on, arm out, and keep the ball on your far foot.",
        "switch-short": "Your long passes are falling short. Get your standing foot beside the ball and strike its bottom half.",
        "press-late": "You are arriving late when you press. Go as the ball travels, and slow down for the last two steps.",
        "def-beaten": "Attackers are getting past you. Stay side-on, stay on your toes and let them make the first move.",
        "def-dived": "You are diving into tackles. Hold your ground and only go when their touch gets away from them.",
        "def-recover": "You are slow to get back when the ball is lost. Turn and sprint straight away, then slow down as you arrive.",
        "track-lost": "You are losing the player you are marking. Stand so you can see the ball and your player at once.",
        "build-panic": "You are giving the ball away under pressure. Take a touch into space and find the simple pass.",
        "clear-weak": "Your clearances are not getting the ball out of danger. Go for height and distance, toward the side.",
        "fit-tired": "You are fading late in games. Build your engine with repeated runs and short rests.",
        "fit-sprint": "You are losing races to the ball. Work on your top speed with short, full-effort sprints.",
        "gk-dive": "You are getting down late. Take a small step toward the ball first and lead with your hands.",
        "gk-catch": "The ball is coming out of your hands. Get your hands behind it, thumbs together, and bring it into your chest.",
        "gk-position": "You are off your angle when shots come. Keep moving so you are always on the line between ball and goal.",
        "gk-set": "You are still moving when the shot is hit. Get your feet set and your weight forward just before they strike.",
        "gk-dist": "Your throws and kicks are not reaching teammates. Pick your target first, then throw or strike through it.",
        "gk-feet": "You are not comfortable with the ball at your feet. Treat back passes like an outfield player: touch, look, pass.",
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
    /// The AI film review (2026-11-15), when the player asked for one; nil for answer-the-questions reviews.
    var ai: FilmAIReport? = nil
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
    static let groups = ["Meals", "South Asian", "Breakfast", "Protein", "Carbs", "Fruit and veg", "Snacks", "Drinks", "Fast food"]
    /// The first 39 plus Screens/FoodList.swift's 227 (2026-11-15).
    static let all: [FoodItem] = base + more
    static let base: [FoodItem] = [
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
    /// From onboarding (2026-11-17): "Build muscle" / "Stay lean and fast" / "More energy for games" / "Just eat better"
    var goal: String? = nil
    /// Position code ("ST", "CM", "GK"...): midfielders run the most, keepers the least.
    var position: String? = nil
    var isSet: Bool { weightKg > 0 && heightCm > 0 && age > 0 }
}

struct FuelTargets: Hashable {
    let kcal: Int
    let protein: Int
    let carbs: Int
    let fat: Int
    let water: Int

    /// Energy to train and recover on, never a diet: resting energy (Mifflin-St Jeor, the middle of its two
    /// constants) times an activity factor that rises with training days, a little more for midfielders (they run the
    /// most) and a little less for keepers, plus the player's food goal: building muscle adds 300 kcal and more
    /// protein, "more energy" adds carbs. "Stay lean" never cuts below what training needs (no weight-loss mode:
    /// many players are teenagers). Protein 1.6 g/kg (1.8 to build muscle), fat a quarter of the energy, carbs the
    /// rest. Without the player's numbers, a typical active teenager's day.
    static func make(_ b: FuelBody) -> FuelTargets {
        guard b.isSet else { return FuelTargets(kcal: 2400, protein: 100, carbs: 330, fat: 70, water: 8) }
        let rest = 10 * b.weightKg + 6.25 * b.heightCm - 5 * Double(b.age) - 78
        var active = 1.4 + 0.075 * Double(min(max(b.trainingDays, 0), 7))
        switch b.position.map(LabPlan.group) {
        case "Midfielder": active += 0.05
        case "Goalkeeper": active -= 0.05
        default: break
        }
        let extra: Double = b.goal == "Build muscle" ? 300 : b.goal == "More energy for games" ? 150 : 0
        let kcal = max(1800, min(4500, rest * active + extra))
        let protein = (b.goal == "Build muscle" ? 1.8 : 1.6) * b.weightKg
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
    /// GPS runs, newest first (Screens/RunTracker.swift).
    var runs: [RunLog] { didSet { save(runs, "lab.runs.v1") } }
    /// XP earned in Soccer Lab's tabs (2026-11-15): drills ticked, full sessions, film reviews, runs, days with food
    /// logged. Added to the finished-session XP for levels, badges and the global leaderboard (Data/Stats.swift).
    var bonusXP: Int { didSet { UserDefaults.standard.set(bonusXP, forKey: "lab.xp.v1") } }
    /// The last day the full-session bonus was given ("2026-11-15").
    private var sessionBonusDay: String { didSet { UserDefaults.standard.set(sessionBonusDay, forKey: "lab.xp.session") } }

    static let xpSession = 50, xpReview = 40, xpFoodDay = 10
    /// The first day the player opened Training: week 1 starts on that week's Monday.
    let startDate: Date

    static let fixGoal = 3

    private init() {
        done = Self.load("lab.done.v1") ?? [:]
        fixList = Self.load("lab.fix.v1") ?? []
        fixCount = Self.load("lab.fixcount.v1") ?? [:]
        reviews = Self.load("lab.film.v1") ?? []
        fuel = Self.load("lab.fuel.v1") ?? [:]
        body = Self.load("lab.body.v1") ?? FuelBody()
        runs = Self.load("lab.runs.v1") ?? []
        bonusXP = UserDefaults.standard.integer(forKey: "lab.xp.v1")
        sessionBonusDay = UserDefaults.standard.string(forKey: "lab.xp.session") ?? ""
        if let t = UserDefaults.standard.object(forKey: "lab.start") as? Date {
            startDate = t
        } else {
            startDate = Date()
            UserDefaults.standard.set(startDate, forKey: "lab.start")
        }
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

    /// What one timed drill earned (Screens/DrillsViews.swift DrillTimer shows it).
    struct Earned { var drill = 0; var session = 0; var seconds: Double = 0; var total: Int { drill + session } }

    /// The shortest timed drill that counts, and how far past the drill's own time the clock keeps earning.
    static let minDrillSeconds: Double = 30
    static func drillCap(_ drill: Drill) -> Double { max(Double(drill.min) * 60 * 2, 120) }

    /// XP for timed training (2026-11-18, the Start Drill timer): harder drills earn more per minute (level 1 = 3 XP a
    /// minute ... level 5 = 7), plus 5 for reaching the drill's full time. Time past twice the drill's length earns
    /// nothing, so a clock left running doesn't farm XP.
    static func drillXP(_ drill: Drill, seconds: Double) -> Int {
        let t = min(seconds, drillCap(drill))
        guard t >= minDrillSeconds else { return 0 }
        let perMinute = Double(2 + min(max(drill.level, 1), 5))
        return max(1, Int((t / 60 * perMinute).rounded())) + (t >= Double(drill.min) * 60 ? 5 : 0)
    }

    /// A drill trained with the timer: the real minutes count toward the streak and stats, XP for the time trained.
    /// The first time today also ticks the drill off (today's plan, the Fix List, the full-session bonus).
    @discardableResult
    func complete(_ drill: Drill, store: AppStore, seconds: Double) -> Earned {
        let t = min(seconds, Self.drillCap(drill))
        guard t >= Self.minDrillSeconds else { return Earned() }
        var got = Earned(drill: Self.drillXP(drill, seconds: t), seconds: t)
        store.logDrill(PlanItem(drill.id), seconds: t)
        if !isDone(drill.id) {
            done[today, default: []].append(drill.id)
            // the whole of today's session done: a bonus, once a day
            let plan = LabPlan.today(position: store.answers.position)
            if sessionBonusDay != today, !plan.isEmpty, plan.allSatisfy({ isDone($0.id) }) {
                sessionBonusDay = today
                got.session = Self.xpSession
            }
            if fixList.contains(drill.id) {
                let n = (fixCount[drill.id] ?? 0) + 1
                fixCount[drill.id] = n
                if n >= Self.fixGoal { fixList.removeAll { $0 == drill.id }; fixCount[drill.id] = nil }
            }
        }
        bonusXP += got.total
        // keep a month of ticks, not forever
        if done.count > 40 { for k in done.keys.sorted().dropLast(31) { done[k] = nil } }
        return got
    }

    // runs and the calendar

    func add(run: RunLog) {
        runs = Array(([run] + runs).prefix(200))
        bonusXP += min(100, Int(run.meters / 50))   // 1 XP per 50 m, up to 100 a run
    }

    /// Which training week this is, counting from the week the player started (1, 2, 3...).
    func week(of date: Date = Date()) -> Int {
        let cal = Calendar.current
        let a = dateOf("Mon", now: startDate), b = dateOf("Mon", now: date)
        return max(1, (cal.dateComponents([.day], from: a, to: b).day ?? 0) / 7 + 1)
    }

    // film

    /// Save a review: its drills go to the top of the Fix List. Returns the drills that were added.
    @discardableResult
    func add(_ review: FilmReview) -> [String] {
        reviews.insert(review, at: 0)
        bonusXP += Self.xpReview
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

    /// The end of onboarding: the player's own numbers become their fuel targets.
    func setBody(from a: Answers) {
        var b = body
        if let w = a.weightKg { b.weightKg = w }
        if let h = a.heightCm { b.heightCm = h }
        if let s = a.age, let n = Int(s) { b.age = n }
        if a.trainDays != nil { b.trainingDays = a.trainingDaysPerWeek }
        b.goal = a.fuelGoal ?? b.goal
        b.position = a.position
        body = b
    }
    var fuelToday: FuelDay { fuel[today] ?? FuelDay() }

    func eat(_ f: FoodItem, servings: Double = 1) {
        let e = FoodEntry(name: f.name, kcal: Int((Double(f.kcal) * servings).rounded()), protein: f.protein * servings,
                          carbs: f.carbs * servings, fat: f.fat * servings)
        foodDayXP()
        var day = fuelToday
        day.entries.append(e)
        fuel[today] = day
        trimFuel()
    }
    func eat(custom name: String, kcal: Int, protein: Double, carbs: Double, fat: Double) {
        foodDayXP()
        var day = fuelToday
        day.entries.append(FoodEntry(name: name, kcal: kcal, protein: protein, carbs: carbs, fat: fat))
        fuel[today] = day
        trimFuel()
    }
    /// Log a meal plan: every food in it, and its glasses of water (Screens/NutritionTab.swift MealPlan).
    func eat(plan: MealPlan) {
        foodDayXP()
        var day = fuelToday
        for f in plan.items {
            day.entries.append(FoodEntry(name: f.name, kcal: f.kcal, protein: f.protein, carbs: f.carbs, fat: f.fat))
        }
        day.water = min(30, day.water + plan.water)
        fuel[today] = day
        trimFuel()
    }
    /// List foods logged in the last 30 days, most-logged first (the add-food sheet's Recent tab).
    var recentFoods: [FoodItem] {
        let byName = Dictionary(Foods.all.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        let since = dateKey(Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date())
        var count: [String: Int] = [:]
        for (k, day) in fuel where k >= since { for e in day.entries where byName[e.name] != nil { count[e.name, default: 0] += 1 } }
        return count.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(15).compactMap { byName[$0.key] }
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
    /// Called before a food is added: the first one of the day earns the food-day XP.
    private func foodDayXP() { if fuelToday.entries.isEmpty { bonusXP += Self.xpFoodDay } }

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
            .background(
                shape.fill(LinearGradient(colors: [Color(hex: 0x13161D), C.char850], startPoint: .top, endPoint: .bottom))
                    .overlay(shape.stroke(LinearGradient(colors: [Color.white.opacity(0.10), C.line], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            )
    }
}

/// A ring that fills as `value` approaches `goal`, with anything in the middle.
struct LabRing<Center: View>: View {
    let value: Double
    let goal: Double
    var color: Color = C.brand
    var width: CGFloat = 10
    @ViewBuilder var center: Center
    var body: some View {
        let f = goal > 0 ? min(1, max(0, value / goal)) : 0
        ZStack {
            Circle().stroke(color.opacity(0.16), lineWidth: width)
            Circle().trim(from: 0, to: f)
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.8), radius: 7)
                .animation(.snappy, value: f)
            center
        }
    }
}

/// One colour per kind of drill, so a list reads at a glance.
func labSkillColor(_ skill: String) -> Color {
    switch skill {
    case "Shooting": return Color(hex: 0xFF6B5E)
    case "Passing", "Awareness": return Color(hex: 0x3DD6C6)
    case "Dribbling", "First touch": return C.gold
    case "Defending", "Goalkeeping": return Color(hex: 0xA78BFA)
    case "Runs", "Fitness", "Core": return Color(hex: 0xFF9F43)
    case "Stretching": return Color(hex: 0x7BE495)
    default: return C.brandHi
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
                Capsule().fill(C.char700)
                Capsule().fill(color).frame(width: max(f > 0 ? 8 : 0, g.size.width * f))
                    .shadow(color: color.opacity(0.8), radius: 6)
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}
