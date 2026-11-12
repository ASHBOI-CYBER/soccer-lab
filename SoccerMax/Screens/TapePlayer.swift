// MATCH FILM (notes/22) ? HIGHLIGHT REEL (2026-10-24): not one continuous film any more (the run-overs between plays
// glitched) ? 5?10 key moments of a real finished match, each its own clip that cuts in clean. Every moment FREEZES
// on its key frames: one circle / arrow / line draws in on the pitch with a short caption (THE GAP, THE CROSS,
// GOAL-SIDE?), then the play runs on to the payoff. You learn it while you watch it. No YouTube, no web player. The picture is
// the 3D rebuild (both real lineups in their real formations, the real scorers, assisters and star players at their
// real slots); everything around it is SwiftUI: play / pause, a scrubber with a marker per play, the match clock, and
// callouts that point at the player who made the play ? every goal, the night's STAR DEFENDER (big tackle) and THE
// BRAIN (the midfielder's key pass). The film stops after each play so the class underneath can be read.
//
// Every moment is labelled with the POSITION of the man it's about (GOALKEEPER, CENTER MID, STRIKER?), so you can see
// which plays are your position's (2026-10-26: YOUR SHADOW / FOLLOW HIM were cut ? "useless"). No guessing, no points.
import PostHog
import SwiftUI

// MARK: - the plan: clips (what the film shows) + lessons (what the class says)

struct NumberBar: Equatable {
    var title: String
    var home: Double
    var away: Double
    var unit: String
}

struct Lesson {
    var tag: String
    var title: String
    var text: String
    var lens: String? = nil       // FOR YOU: what to watch, as a player in your position
    var steal: String? = nil      // one thing to take into your own game
    var drill: String? = nil      // a library drill that trains it (for your gear / partner), one tap onto today
    var faces: [Person] = []
    var board = false             // the formation board
    var bars: [NumberBar] = []
    var final = false
}

enum CallTone { case green, creme, gold }

/// The label on the video that points at the player.
struct Callout {
    var title: String
    var sub: String
    var tone: CallTone
    var at: Double                // play time it pops (the strike, the tackle, the pass)
}

/// A freeze on the moment's key frame: what the 3D draws (`marks`) + the caption on the picture. Few and bold.
struct ReelStop {
    var anchor: String            // 'start' | 'pass' | 'strike' (+ off seconds)
    var off: Double
    var marks: [String]
    var title: String             // ? ~16 chars, the big word
    var sub: String               // one plain line
    var hold = 2.6
    var stage: FilmStage.Stop { FilmStage.Stop(anchor: anchor, off: off, hold: hold, marks: marks) }
}

struct FilmClip: Identifiable {
    enum Kind: String { case roll, goal, og, pen, miss, save, tackle, keypass, chance, card }
    enum Mark: Equatable { case none, goal(Side), miss, red, yellow, star }
    var id = 0
    var kind: Kind
    var side: Side
    var scorer: String? = nil
    var assist: String? = nil
    var star: String? = nil
    var focus: String? = nil      // "home:3:2": who the callout points at
    var pos: String? = nil        // the position of the man this moment is about: "CENTER MID", "GOALKEEPER"?
    var len: Double
    var seed: Int
    var key: Int                  // where it sits on the match clock (star plays: in a quiet stretch ? no real minute)
    var allGame = false
    var mark: Mark = .none
    var call: Callout? = nil
    var before = (0, 0)
    var after = (0, 0)
    var lesson: Lesson
    var stops: [ReelStop] = []
    var play: String? = nil       // the 3D's play variant (so the captions match what's drawn)
    var end: String? = nil        // key pass / big save: save | wide
    var card: String? = nil       // card clips: yellow | red
    var rank = 0                  // reel priority: 0 goals · 1 star plays · 2 VAR + missed pens · 3 red cards

    var stage: FilmStage.Clip {
        FilmStage.Clip(id: id, kind: kind.rawValue, side: side.rawValue, scorer: scorer, assist: assist, star: star,
                       len: len, seed: seed, focus: focus, focusAt: call?.at ?? 0, stops: stops.map(\.stage), play: play, end: end, card: card)
    }
    var marker: Bool { mark != .none }
    /// GK, CB, FB, WB, WM, CM, W, ST ? for the reel bar
    static func short(_ pos: String) -> String {
        ["GOALKEEPER": "GK", "CENTER BACK": "CB", "FULL BACK": "FB", "WING BACK": "WB", "WIDE MID": "WM",
         "CENTER MID": "CM", "WINGER": "W", "STRIKER": "ST"][pos] ?? ""
    }
}

/// The goal types we can name honestly from the data (who assisted and where he plays).
enum Pattern { case cross, pocket, solo }


extension MatchTape {
    var formations: (String, String) {
        let l = fx.lineups ?? []
        let h = l.first { $0.team.id == home.id }?.formation ?? "?"
        let a = l.first { $0.team.id == away.id }?.formation ?? "?"
        return (h, a)
    }
    func formation(_ s: Side) -> String { s == .home ? formations.0 : formations.1 }
    func backLine(_ s: Side) -> Int { Int(formation(s).split(separator: "-").first ?? "") ?? 4 }

    /// Wide or central from his slot in the lineup grid ("row:col").
    func isWide(_ p: Person) -> Bool {
        guard let g = p.grid else { return false }
        let rc = g.split(separator: ":").compactMap { Int($0) }
        guard rc.count == 2 else { return false }
        let n = grids(p.side).filter { $0.hasPrefix("\(rc[0]):") }.count
        guard n > 1 else { return false }
        let k = Double(rc[1] - 1) - Double(n - 1) / 2
        return abs(k) * min(11, 34 / Double(n - 1)) > 11
    }

    func role(_ p: Person) -> String {
        let wide = isWide(p)
        switch p.pos {
        case "G": return "keeper"
        case "D": return wide ? "full back" : "centre back"
        case "M": return wide ? (backLine(p.side) == 3 ? "wing back" : "wide midfielder") : "midfielder"
        case "F": return wide ? "winger" : "striker"
        default: return "player"
        }
    }

    func pattern(_ m: Moment) -> Pattern {
        guard let a = m.assist else { return .solo }
        return isWide(a) ? .cross : .pocket
    }

    func goals(of p: Person) -> Int { moments.filter { ($0.kind == .goal || $0.kind == .penalty) && $0.player?.id == p.id }.count }
    func assists(of p: Person) -> Int { moments.filter { $0.counts && $0.assist?.id == p.id }.count }

    /// Players we can put on the 3D pitch (they have a slot) who played a real part.
    var slotted: [Person] { people.values.filter { $0.grid != nil && $0.minutes >= 30 } }
    func stat(_ p: Person, _ k: String) -> Int { Int(p.stats[k] ?? 0) }
    func wins(_ p: Person) -> Int { stat(p, "tackles") + stat(p, "interceptions") + stat(p, "blocks") }

    /// STAR DEFENDER: most tackles + interceptions + blocks (4+), defenders and central midfielders.
    var defStar: Person? {
        slotted.filter { $0.pos == "D" || ($0.pos == "M" && !isWide($0)) }
            .filter { wins($0) >= 4 }
            .max { wins($0) != wins($1) ? wins($0) < wins($1) : ($0.rating ?? 0) < ($1.rating ?? 0) }
    }
    /// THE BLOCK: a defender / midfielder who got his body in front of 2+ shots.
    func blockStar(not other: Person?) -> Person? {
        slotted.filter { ($0.pos == "D" || $0.pos == "M") && stat($0, "blocks") >= 2 && $0.id != other?.id }
            .max { stat($0, "blocks") < stat($1, "blocks") }
    }
    /// STAR DRIBBLER: a forward / wide man who beat his man 3+ times.
    var dribStar: Person? {
        slotted.filter { ($0.pos == "F" || ($0.pos == "M" && isWide($0))) && stat($0, "dribbles") >= 3 }
            .max { stat($0, "dribbles") < stat($1, "dribbles") }
    }
    /// SO CLOSE: a forward who kept shooting (4+) and never scored.
    func shotStar(not other: Person?) -> Person? {
        slotted.filter { $0.pos != "G" && $0.pos != "D" && stat($0, "shots") >= 4 && goals(of: $0) == 0 && $0.id != other?.id }
            .max { stat($0, "shots") < stat($1, "shots") }
    }
    /// STAR KEEPER: a keeper with 4+ saves (a real busy night).
    var keeperStar: Person? {
        slotted.filter { $0.pos == "G" && stat($0, "saves") >= 4 }.max { stat($0, "saves") < stat($1, "saves") }
    }
    /// THE BRAIN: the central midfielder who made the game ? key passes first, then passes.
    func midStar(not other: Person?) -> Person? {
        func score(_ p: Person) -> Double { Double(stat(p, "keyPasses")) * 3 + Double(stat(p, "passes")) / 25 }
        return slotted.filter { $0.pos == "M" && !isWide($0) && $0.id != other?.id }
            .filter { stat($0, "keyPasses") >= 2 || stat($0, "passes") >= 55 }
            .max { score($0) < score($1) }
    }

    /// The on-screen position label for a moment: who it's about, by his slot (2026-10-26: "if a center mid or goal
    /// keeper is highlighted then label that").
    func posLabel(_ p: Person?) -> String? {
        guard let p else { return nil }
        switch role(p) {
        case "keeper": return "GOALKEEPER"
        case "centre back": return "CENTER BACK"
        case "full back": return "FULL BACK"
        case "wing back": return "WING BACK"
        case "wide midfielder": return "WIDE MID"
        case "midfielder": return "CENTER MID"
        case "winger": return "WINGER"
        case "striker": return "STRIKER"
        default: return nil
        }
    }
}

/// What a player in your position should watch, and which drills train it.
enum Lens {
    enum Group { case keeper, defender, midfielder, forward }
    static func group(_ pos: String) -> Group {
        switch pos {
        case "GK": return .keeper
        case "CB", "LB", "RB", "LWB", "RWB": return .defender
        case "CDM", "CM", "CAM", "LM", "RM": return .midfielder
        default: return .forward
        }
    }

    static func goal(_ g: Group, _ p: Pattern, scorer: String, assister: String?) -> String {
        let a = assister ?? "the passer"
        switch (g, p) {
        case (.forward, .cross): return "Watch \(scorer)'s run: he arrives as the ball does — not early, not standing still."
        case (.forward, .pocket): return "Watch where \(scorer) stands: between their defence and midfield, where nobody can pick him up."
        case (.forward, .solo): return "Watch how early \(scorer) shoots once he has a yard of space. No extra touch."
        case (.midfielder, .cross): return "Watch \(a) before the cross: head up first, then he picks the man."
        case (.midfielder, .pocket): return "Watch \(a): one look at the run, then the pass — into the gap, not to feet."
        case (.midfielder, .solo): return "Watch who should have closed \(scorer) down. From midfield, that's often you."
        case (.defender, .cross): return "Watch the space \(scorer) runs into. Whose job was it? Track the runner, not the ball."
        case (.defender, .pocket): return "Watch the gap between their back line and midfield. Step up together and it closes."
        case (.defender, .solo): return "Watch the defenders backing off. Show him wide before he's in range to shoot."
        case (.keeper, _): return "Watch where the shot goes. Set your feet before the strike — a keeper moving at the kick can't dive."
        }
    }

    static func skills(_ g: Group) -> [String] {
        switch g {
        case .keeper: return ["Goalkeeping"]
        case .defender: return ["Defending"]
        case .midfielder: return ["Passing", "Awareness"]
        case .forward: return ["Shooting", "Dribbling"]
        }
    }

    /// The best drill of those skills for this player (their gear, partner, level, what they want to fix).
    static func drill(_ skills: [String], _ a: Answers) -> String? {
        Library.shared.drills.filter { skills.contains($0.skill) }
            .map { Recommend.score($0, a) }.filter(\.feasible)
            .max { $0.score < $1.score }?.drill.id
    }
}

/// A tiny seeded generator, so a game's reel is the same every time you open it (and different from the next game's).
struct Seeded: RandomNumberGenerator {
    var x: UInt64
    init(_ seed: Int) { x = UInt64(truncatingIfNeeded: seed) &* 0x9E3779B97F4A7C15 | 1 }
    mutating func next() -> UInt64 {
        x ^= x << 13; x ^= x >> 7; x ^= x << 17
        return x
    }
}

enum FilmPlan {
    static let goalLen = 6.6, penLen = 6.0, missLen = 5.2, tackleLen = 5.6, passLen = 6.4, rollLen = 4.5, saveLen = 5.4

    /// Each goal pattern can be drawn two ways; the reel takes the one it has used least so far (seed breaks ties), so
    /// no game shows the same pass twice in a row (2026-10-25: "I'm seeing a similar pass a lot").
    static func variant(_ p: Pattern, seed: Int, used: inout [String: Int]) -> String {
        let opts: [String]
        switch p {
        case .cross: opts = ["cross", "cutback"]
        case .pocket: opts = ["pocket", "through"]
        case .solo: opts = ["solo", "long"]
        }
        let pick = opts.enumerated().min { a, b in
            let ua = used[a.element, default: 0], ub = used[b.element, default: 0]
            return ua != ub ? ua < ub : (a.offset + seed) % 2 < (b.offset + seed) % 2
        }!.element
        used[pick, default: 0] += 1
        return pick
    }
    /// When the shot is hit in the 3D for that play (Film.tsx STRIKE + SHOT) ? the GOAL! callout pops there.
    static func strikeAt(_ play: String) -> Double {
        switch play {
        case "through": return 4.15
        case "long": return 3.65
        default: return 3.4
        }
    }

    /// How long the reel takes to watch: every clip + its freezes (0.4 s ease in each) + the beat between moments.
    static func seconds(_ clips: [FilmClip]) -> Double {
        clips.reduce(0) { $0 + $1.len + $1.stops.reduce(0) { $0 + $1.hold + 0.4 } } + Double(max(0, clips.count - 1)) * (FilmPlayer.autoWait + 0.5)
    }
    /// "1 MIN", "2 MIN"? for the previews (rounded, never 0).
    static func minutes(_ t: MatchTape, _ a: Answers) -> Int { max(1, Int((seconds(build(t, a)) / 60).rounded())) }

    static func build(_ t: MatchTape, _ a: Answers) -> [FilmClip] {
        let group = Lens.group(a.position)
        var out: [FilmClip] = []
        var score = (0, 0)
        func key(_ p: Person?) -> String? { p.flatMap { q in q.grid.map { "\(q.side.rawValue):\($0)" } } }
        func bump(_ s: Side) { if s == .home { score.0 += 1 } else { score.1 += 1 } }
        func seed(_ m: Moment) -> Int { m.elapsed * 31 + (m.extra ?? 0) * 7 + 7 }

        // 1 · kick-off: the shapes
        let (fh, fa) = t.formations
        // seeded by the game, so every opening build-up is its own (2026-10-30: "the beginning is very repetitive")
        var kick = FilmClip(kind: .roll, side: t.fx.id % 2 == 0 ? .home : .away, len: rollLen + 1.2, seed: t.fx.id % 9973 + 3, key: 0,
                            lesson: Lesson(tag: "KICK-OFF", title: "\(fh)  v  \(fa)",
                                           text: "\(nick(t.home.name)): \(fh). \(nick(t.away.name)): \(fa). " + shapeNote(t), board: true))
        kick.stops = [ReelStop(anchor: "start", off: 2.2, marks: ["backs"], title: "THE BACK LINES",
                               sub: "\(t.backLine(.home)) at the back v \(t.backLine(.away)). Gaps open between these men.")]
        out.append(kick)

        // 2 · every real moment, in order
        var goalNo = 0
        var used: [String: Int] = [:]
        let yellows = t.moments.filter { $0.kind == .yellow && $0.player?.grid != nil }
        let pickYellow = yellows.isEmpty ? -1 : yellows[t.fx.id % yellows.count].id
        for m in t.moments {
            let team = nick(t.team(m.side).name)
            let who = m.player
            let before = score
            var c: FilmClip
            switch m.kind {
            case .goal, .varNoGoal:
                let pat = t.pattern(m)
                let s = who.map { "\($0.short), the \(t.role($0))," } ?? team
                var text: String
                let steal: String
                switch pat {
                case .cross:
                    text = "\(m.assist!.short), the \(t.role(m.assist!)), gets it out wide and puts it in. \(s) scores."
                    steal = "When your winger has it wide, sprint to the penalty spot — not toward the defenders."
                case .pocket:
                    text = "\(m.assist!.short), the \(t.role(m.assist!)), passes it through the middle. \(s) scores."
                    steal = "Stand in the pocket between their defenders and midfielders. Get it there, turn, shoot."
                case .solo:
                    text = "No assist — \(s) does it on his own."
                    steal = "If nobody steps out to you, keep carrying the ball until someone does. Then shoot."
                }
                let lens = Lens.goal(group, pat, scorer: who?.short ?? "the scorer", assister: m.assist?.short)
                let sc = who?.short ?? "He", asr = m.assist?.short ?? "The passer"
                let play = variant(pat, seed: seed(m), used: &used)
                // a play the reel has already explained gets ONE freeze (its payoff), so every goal isn't the same class
                let seen = (used[play] ?? 0) > 1
                var stops: [ReelStop]
                switch play {
                case "cross": stops = [ReelStop(anchor: "pass", off: -0.1, marks: ["gap", "run"], title: "THE GAP", sub: "Nobody is marking this spot. \(sc) runs into it."),
                                       ReelStop(anchor: "pass", off: 0.12, marks: ["pass"], title: "THE CROSS", sub: "\(asr) puts it where \(sc) arrives.", hold: 2.2)]
                case "cutback": stops = [ReelStop(anchor: "pass", off: -0.1, marks: ["press"], title: "HE'S CLOSING", sub: "So \(asr) doesn't wait. He looks up."),
                                         ReelStop(anchor: "pass", off: 0.1, marks: ["pass", "gap"], title: "THE CUTBACK", sub: "Back to the spot. The defenders can't turn in time.", hold: 2.2)]
                case "pocket": stops = [ReelStop(anchor: "pass", off: -0.1, marks: ["line", "gap"], title: "THE POCKET", sub: "In front of their back line. Too far for them to step out."),
                                        ReelStop(anchor: "pass", off: 0.12, marks: ["pass", "run"], title: "INTO THE GAP", sub: "\(asr) passes to the space, not to feet.", hold: 2.2)]
                case "through": stops = [ReelStop(anchor: "pass", off: -0.1, marks: ["line", "gap"], title: "IN BEHIND", sub: "Their line is high. \(sc) waits on the last man's shoulder."),
                                         ReelStop(anchor: "strike", off: -0.12, marks: ["shot"], title: "ACROSS THE KEEPER", sub: "Low, to the far side. Hardest save there is.", hold: 2.2)]
                case "long": stops = [ReelStop(anchor: "strike", off: -0.12, marks: ["shot", "press"], title: "FROM DISTANCE", sub: "25 m out, he's closing. Hit it before he gets there.")]
                default: stops = [ReelStop(anchor: "strike", off: -1.3, marks: ["press"], title: "HE'S CLOSING", sub: "A defender steps out. \(sc) doesn't wait for him."),
                                  ReelStop(anchor: "strike", off: -0.12, marks: ["shot"], title: "SHOOT EARLY", sub: "One yard of space is enough.", hold: 2.2)]
                }
                if seen, stops.count > 1 { stops = [stops[stops.count - 1]] }
                if m.kind == .goal {
                    goalNo += 1
                    bump(m.side)
                    text += " \(m.minute), \(score.0)–\(score.1)."
                    c = FilmClip(kind: .goal, side: m.side, scorer: who?.grid, assist: m.assist?.grid, focus: key(who), len: goalLen, seed: seed(m), key: m.key,
                                 mark: .goal(m.side), call: Callout(title: "GOAL!", sub: "\(m.minute) · \((who?.short ?? team).uppercased())", tone: .green, at: strikeAt(play)),
                                 lesson: Lesson(tag: "GOAL \(goalNo) · \(m.minute)", title: who?.name.uppercased() ?? "GOAL", text: text, lens: lens, steal: steal,
                                                faces: [who, m.assist].compactMap { $0 }), stops: stops)
                } else {
                    c = FilmClip(kind: .goal, side: m.side, scorer: who?.grid, assist: m.assist?.grid, focus: key(who), len: goalLen, seed: seed(m), key: m.key,
                                 mark: .miss, call: Callout(title: "NO GOAL", sub: "\(m.minute) · VAR RULES IT OUT", tone: .creme, at: 5.0),
                                 lesson: Lesson(tag: "VAR · \(m.minute)", title: "NO GOAL",
                                                text: "\(who?.short ?? "He") puts it in for \(team) — then VAR rules it out. The data doesn't say why; it's usually offside or a foul in the build-up.",
                                                lens: "Watch the build-up again: was anyone past the last defender when the pass was played?", faces: [who].compactMap { $0 }),
                                 stops: [ReelStop(anchor: "pass", off: -0.1, marks: ["line"], title: "THE LAST LINE", sub: "Anyone past it when the ball is played is offside.")], rank: 2)
                }
                c.play = play

            case .ownGoal:
                goalNo += 1
                bump(m.side)
                c = FilmClip(kind: .og, side: m.side, scorer: who?.grid, focus: key(who), len: penLen, seed: seed(m), key: m.key,
                             mark: .goal(m.side), call: Callout(title: "OWN GOAL", sub: "\(m.minute) · \((who?.short ?? "").uppercased())", tone: .green, at: 3.2),
                             lesson: Lesson(tag: "GOAL \(goalNo) · \(m.minute)", title: "OWN GOAL",
                                            text: "\(who?.name ?? "A defender") turns it into his own net — \(team)'s goal. \(m.minute), \(score.0)?\(score.1).",
                                            lens: group == .defender || group == .keeper
                                                ? "Watch the ball across the box: fast and low between keeper and defenders is the hardest ball there is to defend."
                                                : "Watch the ball across the box: fast and low, so the defender has to stretch for it.",
                                            steal: "Cross low and hard between the keeper and the defenders. Someone has to touch it.",
                                            faces: [who].compactMap { $0 }),
                             stops: [ReelStop(anchor: "pass", off: 0.15, marks: ["pass", "gap"], title: "THE CROSS", sub: "Into the space between the keeper and the defenders.")])

            case .penalty, .missedPen, .savedPen:
                let scored = m.kind == .penalty
                if scored { goalNo += 1; bump(m.side) }
                let how = scored ? " and scores." : m.kind == .savedPen ? " — the keeper saves it." : " — it goes off target."
                let title = scored ? "PENALTY — SCORED" : (m.kind == .savedPen ? "PENALTY — SAVED" : "PENALTY — MISSED")
                c = FilmClip(kind: scored ? .pen : m.kind == .savedPen ? .save : .miss, side: m.side, scorer: who?.grid, focus: key(who),
                             len: scored ? penLen : missLen, seed: seed(m), key: m.key, mark: scored ? .goal(m.side) : .miss,
                             call: Callout(title: scored ? "GOAL!" : (m.kind == .savedPen ? "SAVED!" : "MISSED!"), sub: "\(m.minute) · PENALTY", tone: scored ? .green : .creme, at: 3.15),
                             lesson: Lesson(tag: scored ? "GOAL \(goalNo) · \(m.minute)" : "PENALTY · \(m.minute)", title: title,
                                            text: "Penalty to \(team). \(who?.name ?? "") takes it" + how + " \(m.minute), \(score.0)–\(score.1).",
                                            lens: group == .keeper ? "Watch the keeper: he waits, then goes. Diving early gives the taker the other side."
                                                                   : "Watch the taker's run-up: same speed all the way, eyes on the ball, side picked before he starts.",
                                            steal: "Pick your side before the run-up — and don't change your mind.", faces: [who].compactMap { $0 }),
                             stops: [m.kind == .savedPen
                                     ? ReelStop(anchor: "strike", off: -0.1, marks: ["keeper"], title: "THE KEEPER WAITS", sub: "He goes when it's hit — not before.")
                                     : ReelStop(anchor: "start", off: 1.2, marks: ["shot"], title: "SIDE PICKED", sub: "Before the run-up. No changing his mind.")],
                             rank: scored ? 0 : 2)

            case .red, .yellow:
                // cards are SHOWN, not just announced (2026-10-30): the foul / the dissent / the handball drawn from the
                // real reason, then the referee holds the card up. Every red; ONE yellow per film (picked by the game).
                if m.kind == .yellow && m.id != pickYellow { continue }
                c = cardClip(t, m, group: group)
            }
            c.before = before
            c.after = score
            c.pos = t.posLabel(who)
            out.append(c)
        }

        // 3 · the star plays the numbers say happened (no minute in the data ? placed in a quiet stretch, "ALL GAME").
        // VARIETY (2026-10-30: "each one is the same, key pass, some type of goal/save, big tackle. Spice it up"): every
        // star the stats earn goes in a pool (tackle · key pass · big save · shot block · dribbler · so close), the reel
        // takes 2?3 of them picked by the game's own seed (fewer when the goals already fill it), in a shuffled order,
        // each dropped into a quiet stretch picked at random ? so no two films run the same pattern.
        var rnd = Seeded(t.fx.id)
        let def = t.defStar
        let mid = t.midStar(not: def)
        let drib = t.dribStar
        var pool: [FilmClip] = []
        if let d = def, let k = key(d) { pool.append(tackle(t, d, k, group: group, a: a)) }
        if let m = mid, let k = key(m) { pool.append(keyPass(t, m, k, group: group, a: a)) }
        if let g = t.keeperStar, let k = key(g) { pool.append(bigSave(t, g, k, group: group, a: a)) }
        if let b = t.blockStar(not: def), let k = key(b) { pool.append(shotBlock(t, b, k, group: group, a: a)) }
        if let w = drib, let k = key(w) { pool.append(dribbler(t, w, k, group: group, a: a)) }
        if let f = t.shotStar(not: drib), let k = key(f) { pool.append(nearMiss(t, f, k, group: group, a: a)) }
        pool.shuffle(using: &rnd)
        let goals = out.filter { $0.rank == 0 }.count
        let take = min(pool.count, goals >= 4 ? 2 : goals >= 2 ? 2 + Int(rnd.next() % 2) : 3)
        for var s in pool.prefix(take) {
            let keys = [0] + out.filter { $0.key > 0 }.map(\.key) + [t.length * 100]
            // any of the three quietest stretches, not always the biggest one
            let gaps = zip(keys, keys.dropFirst()).sorted { ($0.1 - $0.0) > ($1.1 - $1.0) }
            let pick = gaps.isEmpty ? (0, 9000) : gaps[Int(rnd.next() % UInt64(min(3, gaps.count)))]
            s.key = (pick.0 + pick.1) / 2
            let at = out.lastIndex { $0.key <= s.key } ?? 0
            s.before = out[at].after
            s.after = out[at].after
            out.insert(s, at: at + 1)
        }

        // the reel: kick-off + at most 9 moments (10 pieces). Over that, drop red cards, then VAR / missed pens, then the
        // latest of the rest ? goals go last. Kept in match order.
        while out.count > 10, let drop = out.indices.dropFirst().max(by: { (out[$0].rank, $0) < (out[$1].rank, $1) }) {
            out.remove(at: drop)
        }

        // 4 · full time: the numbers + what to steal
        var ft = FilmClip(kind: .roll, side: t.score.0 >= t.score.1 ? .home : .away, len: rollLen, seed: t.fx.id % 9973 + 5, key: t.length * 100,
                          call: Callout(title: "FULL TIME", sub: "\(abbr(t.home.name)) \(t.score.0)–\(t.score.1) \(abbr(t.away.name))", tone: .creme, at: 0.4),
                          lesson: final(t, out, group, a))
        ft.before = score
        ft.after = score
        out.append(ft)
        for i in out.indices { out[i].id = i }
        return out
    }

    static func tackle(_ t: MatchTape, _ p: Person, _ k: String, group: Lens.Group, a: Answers) -> FilmClip {
        let n = (t.stat(p, "tackles"), t.stat(p, "interceptions"), t.stat(p, "blocks"))
        var bits = ["\(n.0) tackle\(n.0 == 1 ? "" : "s")", "\(n.1) interception\(n.1 == 1 ? "" : "s")"]
        if n.2 > 0 { bits.append("\(n.2) block\(n.2 == 1 ? "" : "s")") }
        // which win to draw (2026-10-30: the old one looked like the attacker kept it): more interceptions than tackles ?
        // he reads a pass; otherwise a standing block tackle or a slide (by player, so a game doesn't always get the same)
        let v = n.1 > n.0 ? "intercept" : (p.id % 2 == 0 ? "block" : "slide")
        let lens: String, steal: String, title: String, stops: [ReelStop]
        switch v {
        case "intercept":
            title = "INTERCEPTION"
            lens = "Watch where he stands: touching distance behind the striker, goal-side — close enough to step in front."
            steal = "Stay tight behind your man. Watch the passer's hips — when he opens up, step in front."
            stops = [ReelStop(anchor: "start", off: 1.5, marks: ["focus", "goalside"], title: "TIGHT BEHIND HIM", sub: "\(p.short) is goal-side, close enough to touch him."),
                     ReelStop(anchor: "pass", off: 0.15, marks: ["read"], title: "READ THE PASS", sub: "He sees it coming. He steps in front.", hold: 2.4)]
        case "slide":
            title = "SLIDE TACKLE"
            lens = "Watch his foot: it gets to the BALL first. A slide that hits the man first is a foul."
            steal = "Slide from the side, never from behind. Ball first — then the man can't complain."
            stops = [ReelStop(anchor: "start", off: 2.25, marks: ["ball"], title: "HE'S PAST HIM", sub: "\(p.short) doesn't give up. He gets down on the ball side."),
                     ReelStop(anchor: "strike", off: -0.06, marks: ["ball"], title: "BALL FIRST", sub: "Foot on the ball, not the man. Clean.", hold: 2.2)]
        default:
            title = "BIG TACKLE"
            lens = group == .defender
                ? "Watch his feet: side-on, goal-side, backing off — he only steps in when the attacker's touch goes too far."
                : "Watch what he does NOT do: he doesn't dive in. He waits for the heavy touch."
            steal = "Don't dive in. Show him one way, wait for the touch that's too big, then step in and put your body between him and the ball."
            stops = [ReelStop(anchor: "start", off: 1.9, marks: ["focus", "goalside"], title: "GOAL-SIDE", sub: "\(p.short) stays between his man and the goal. No diving in."),
                     ReelStop(anchor: "strike", off: -0.12, marks: ["ball"], title: "THE BIG TOUCH", sub: "The ball leaves his feet. NOW step in.", hold: 2.2)]
        }
        var l = Lesson(tag: "STAR DEFENDER", title: p.name.uppercased(),
                       text: "\(p.short), the \(t.role(p)) for \(nick(t.team(p.side).name)): \(bits.joined(separator: ", ")) tonight — real numbers. The play is drawn: it's what one of those wins looks like.",
                       lens: lens, steal: steal, faces: [p])
        if group == .defender { l.drill = Lens.drill(["Defending"], a) }
        var c = FilmClip(kind: .tackle, side: p.side, star: p.grid, focus: k, pos: t.posLabel(p), len: tackleLen, seed: p.id % 997 + 11, key: 0, allGame: true,
                         mark: .star,
                         call: Callout(title: title, sub: "\(p.short.uppercased()) · \(n.0 + n.1 + n.2) WINS TONIGHT", tone: .green, at: 2.75),
                         lesson: l, stops: stops, rank: 1)
        c.play = v
        return c
    }

    /// The drawing for a card, from the data's reason (event comments).
    static func foulDrawing(_ m: Moment) -> String {
        let r = (m.reason ?? "").lowercased(), id = m.player?.id ?? 0
        if r.contains("dissent") || r.contains("argument") || r.contains("abusive") || r.contains("language") { return "dissent" }
        if r.contains("violent") || r.contains("elbow") || r.contains("serious") { return "violent" }
        if r.contains("handball") { return "handball" }
        if r.contains("time") { return "delay" }
        if r.contains("retreat") || r.contains("distance") { return "retreat" }
        if m.kind == .red { return id % 2 == 0 ? "reckless" : "pull" }
        return id % 3 == 0 ? "pull" : "trip"
    }

    static func cardClip(_ t: MatchTape, _ m: Moment, group: Lens.Group) -> FilmClip {
        let red = m.kind == .red
        let who = m.player
        let team = nick(t.team(m.side).name)
        let v = foulDrawing(m)
        let name = who?.short ?? "He"
        let keeper = who?.pos == "G"
        let (title, sub, anchor, off, marks, what, steal): (String, String, String, Double, [String], String, String)
        switch v {
        case "pull":
            (title, sub, anchor, off, marks) = red ? ("LAST MAN", "He's through on goal. Pull him back there and it's red.", "strike", 0.12, ["focus"])
                                                   : ("SHIRT PULL", "\(name) is beaten, so he grabs him.", "strike", 0.12, ["focus"])
            what = "pulls his man back"; steal = "Beaten? Run, don't grab. A shirt pull is a card every time the ref sees it."
        case "reckless":
            (title, sub, anchor, off, marks) = ("BOTH FEET", "Off the ground, out of control. That's a red.", "strike", -0.05, ["focus"])
            what = "flies in with both feet"; steal = "Stay on your feet. A slide that's late, from the side and two-footed is a red."
        case "dissent":
            (title, sub, anchor, off, marks) = ("TOO MUCH TALK", "Shout at the referee and he'll book you.", "start", 2.9, ["focus"])
            what = "won't stop arguing with the referee"; steal = "Disagree? Walk away. Only your captain should talk to the ref."
        case "violent":
            (title, sub, anchor, off, marks) = ("HANDS ON HIM", "The ball isn't even here. That's a red.", "strike", -0.04, ["focus"])
            what = "shoves a man to the ground off the ball"; steal = "Lose your head and your team plays a man down. Walk away."
        case "handball":
            (title, sub, anchor, off, marks) = ("ARM UP", "Away from his body. The shot hits it: handball.", "strike", 0.02, ["ball"])
            what = "blocks it with his arm"; steal = "Blocking a shot? Arms behind your back or tight to your side."
        case "delay":
            (title, sub, anchor, off, marks) = keeper ? ("TIME WASTING", "Holding the ball too long. The ref has seen enough.", "start", 2.3, ["focus"])
                                                      : ("TIME WASTING", "No hurry to play it. The ref has seen enough.", "start", 2.3, ["focus"])
            what = "wastes time with the ball"; steal = "Winning late? Play quickly anyway. A booking for time wasting is a cheap one."
        case "retreat":
            (title, sub, anchor, off, marks) = ("10 YARDS", "At a free kick you stand 9.15 m away. He's right on it.", "start", 2.0, ["ten"])
            what = "won't back off at a free kick"; steal = "Free kick against you? Get 10 yards back fast — or get booked."
        default:
            (title, sub, anchor, off, marks) = ("TOO LATE", "The ball's gone. He only gets the man.", "strike", -0.05, ["focus"])
            what = "is late and takes his man's legs"; steal = "Can't get the ball? Don't go through the man. Stay on your feet, stay goal-side."
        }
        let reason = m.reason.map { " The data says: \($0.lowercased())." } ?? ""
        let card = red ? "RED CARD" : "YELLOW CARD"
        let cardAt = v == "dissent" ? 3.5 : 3.9
        var c = FilmClip(kind: .card, side: m.side, star: who?.grid, focus: who.flatMap { p in p.grid.map { "\(p.side.rawValue):\($0)" } },
                         len: 6.4, seed: m.elapsed * 31 + 7, key: m.key, mark: red ? .red : .yellow,
                         call: Callout(title: card, sub: "\(m.minute) · \(name.uppercased())", tone: .creme, at: cardAt),
                         lesson: Lesson(tag: "\(red ? "RED" : "YELLOW") CARD · \(m.minute)", title: who?.name.uppercased() ?? card,
                                        text: "\(who?.name ?? "A player") (\(team)) \(what) — \(red ? "sent off" : "booked").\(reason) The play is drawn\(red ? "; " + team + " play the rest with 10." : ".")",
                                        steal: steal, faces: [who].compactMap { $0 }),
                         stops: [ReelStop(anchor: anchor, off: off, marks: marks, title: title, sub: sub)],
                         rank: red ? 2 : 3)
        c.play = v
        c.card = red ? "red" : "yellow"
        return c
    }

    /// THE BLOCK: their striker gets a shot away from the edge of the box ? and this man is on its line.
    static func shotBlock(_ t: MatchTape, _ p: Person, _ k: String, group: Lens.Group, a: Answers) -> FilmClip {
        let b = t.stat(p, "blocks")
        let shooter = t.slotted.filter { $0.side == p.side.other && $0.pos == "F" }.max { t.stat($0, "shots") < t.stat($1, "shots") }
        var l = Lesson(tag: "THE BLOCK", title: p.name.uppercased(),
                       text: "\(p.short), the \(t.role(p)) for \(nick(t.team(p.side).name)): \(b) blocks tonight — real numbers. The play is drawn: it's what one of them looks like.",
                       lens: "Watch where he runs: not at the shooter, but onto the line between the ball and the goal.",
                       steal: "Blocking a shot? Get on its line, stay big, arms behind your back so it can't be handball.",
                       faces: [p])
        if group == .defender { l.drill = Lens.drill(["Defending"], a) }
        var c = FilmClip(kind: .chance, side: p.side.other, scorer: shooter?.grid, star: p.grid, focus: k, pos: t.posLabel(p), len: saveLen, seed: p.id % 997 + 19, key: 0, allGame: true,
                         mark: .star,
                         call: Callout(title: "WHAT A BLOCK", sub: "\(p.short.uppercased()) · \(b) BLOCKS TONIGHT", tone: .green, at: 3.05),
                         lesson: l,
                         stops: [ReelStop(anchor: "strike", off: -0.1, marks: ["press"], title: "BODY IN THE WAY", sub: "On the shot's line. Arms behind his back.")],
                         rank: 1)
        c.play = "solo"
        c.end = "block"
        return c
    }

    /// STAR DRIBBLER: he runs at a midfielder, drops his shoulder, goes the other way ? then shoots.
    static func dribbler(_ t: MatchTape, _ p: Person, _ k: String, group: Lens.Group, a: Answers) -> FilmClip {
        let d = t.stat(p, "dribbles")
        var l = Lesson(tag: "STAR DRIBBLER", title: p.name.uppercased(),
                       text: "\(p.short), the \(t.role(p)) for \(nick(t.team(p.side).name)): \(d) dribbles past a man tonight — real numbers. The play is drawn: it's what one of them looks like.",
                       lens: "Watch his shoulder: it dips one way for a split second. The defender's weight goes with it — then he goes the other way.",
                       steal: "Run straight at the defender. When he's a step away, drop your shoulder one way and push the ball the other.",
                       faces: [p])
        if group == .forward || group == .midfielder { l.drill = Lens.drill(["Dribbling"], a) }
        var c = FilmClip(kind: .chance, side: p.side, scorer: p.grid, focus: k, pos: t.posLabel(p), len: 5.9, seed: p.id % 997 + 23, key: 0, allGame: true,
                         mark: .star,
                         call: Callout(title: "SKILL", sub: "\(p.short.uppercased()) · \(d) DRIBBLES TONIGHT", tone: .green, at: 2.3),
                         lesson: l,
                         stops: [ReelStop(anchor: "start", off: 1.62, marks: ["beat"], title: "MAKE HIM COMMIT", sub: "Run right at him. Drop the shoulder when he's close.")],
                         rank: 1)
        c.play = "dribble"
        c.end = p.id % 3 == 0 ? "wide" : "save"
        return c
    }

    /// SO CLOSE: the man who kept shooting and never scored ? one of those near misses.
    static func nearMiss(_ t: MatchTape, _ p: Person, _ k: String, group: Lens.Group, a: Answers) -> FilmClip {
        let sh = t.stat(p, "shots"), on = t.stat(p, "onTarget")
        let over = p.id % 2 == 0
        var l = Lesson(tag: "SO CLOSE", title: p.name.uppercased(),
                       text: "\(p.short), the \(t.role(p)) for \(nick(t.team(p.side).name)): \(sh) shots, \(on) on target, no goal tonight — real numbers. The play is drawn: it's what one of those near misses looks like.",
                       lens: over ? "Watch his body as he hits it: leaning back. That's what sends it over." : "Watch his shot: hit hard at the corner, but no target picked — it goes just wide.",
                       steal: over ? "Shooting? Head and chest over the ball, toe down. Lean back and it flies over." : "Pick your corner BEFORE you shoot. Low and hard to the far post.",
                       faces: [p])
        if group == .forward { l.drill = Lens.drill(["Shooting"], a) }
        var c = FilmClip(kind: .chance, side: p.side, scorer: p.grid, focus: k, pos: t.posLabel(p), len: saveLen, seed: p.id % 997 + 29, key: 0, allGame: true,
                         mark: .star,
                         call: Callout(title: "SO CLOSE", sub: "\(p.short.uppercased()) · \(sh) SHOTS TONIGHT", tone: .creme, at: 3.5),
                         lesson: l,
                         stops: [ReelStop(anchor: "strike", off: -0.12, marks: ["shot"], title: over ? "LEANING BACK" : "NO CORNER PICKED",
                                          sub: over ? "Body back = ball up. It's going over." : "Hard — but not aimed. Just wide.")],
                         rank: 1)
        c.play = p.id % 3 == 0 ? "long" : "solo"
        c.end = over ? "over" : "wide"
        return c
    }

    static func keyPass(_ t: MatchTape, _ p: Person, _ k: String, group: Lens.Group, a: Answers) -> FilmClip {
        let kp = t.stat(p, "keyPasses"), ps = t.stat(p, "passes")
        let acc = p.stats["passAcc"].map { ", \(Int($0))% found a teammate" } ?? ""
        var l = Lesson(tag: "THE BRAIN", title: p.name.uppercased(),
                       text: "\(p.short), the \(t.role(p)) for \(nick(t.team(p.side).name)): \(ps) passes\(acc), \(kp) key pass\(kp == 1 ? "" : "es") (a pass that sets up a shot). The play is drawn: it's what one of them looks like.",
                       lens: group == .midfielder
                           ? "Watch his head before the ball reaches him: he looks, so he can play it the moment it arrives."
                           : "Watch the runner: he goes as the passer looks up. The pass and the run happen together.",
                       steal: "Check your shoulder before the ball comes. Then you already know where the pass goes.",
                       faces: [p])
        if group == .midfielder { l.drill = Lens.drill(["Passing", "Awareness"], a) }
        // a key pass sets up a SHOT that didn't go in (the goals have their own clips) ? the 3D always shows it
        let lofted = p.id % 2 == 1
        let stops = lofted
            ? [ReelStop(anchor: "pass", off: 0.15, marks: ["pass", "run"], title: "OVER THE TOP", sub: "Their line is high, so \(p.short) chips it over them.")]
            : [ReelStop(anchor: "pass", off: -0.3, marks: ["line", "gap"], title: "THE SPACE BEHIND", sub: "Their line is high. \(p.short) has already seen it."),
               ReelStop(anchor: "pass", off: 0.15, marks: ["pass", "run"], title: "PASS + RUN", sub: "Into space, so the runner never slows down.", hold: 2.2)]
        var c = FilmClip(kind: .keypass, side: p.side, star: p.grid, focus: k, pos: t.posLabel(p), len: passLen, seed: p.id % 997 + 13, key: 0, allGame: true,
                         mark: .star,
                         call: Callout(title: "THE KEY PASS", sub: "\(p.short.uppercased()) · \(kp) KEY PASS\(kp == 1 ? "" : "ES") TONIGHT", tone: .green, at: 2.45),
                         lesson: l, stops: stops, rank: 1)
        c.play = lofted ? "lofted" : nil
        c.end = p.id % 3 == 0 ? "wide" : "save"
        return c
    }

    /// STAR KEEPER: their best chance of the night, drawn ? the keeper is set, then dives the right way and saves it.
    static func bigSave(_ t: MatchTape, _ g: Person, _ k: String, group: Lens.Group, a: Answers) -> FilmClip {
        let sv = t.stat(g, "saves")
        // the shooter = their best-rated forward (the man who most often had the chance)
        let shooter = t.slotted.filter { $0.side == g.side.other && $0.pos == "F" }.max { ($0.rating ?? 0) < ($1.rating ?? 0) }
        var l = Lesson(tag: "STAR KEEPER", title: g.name.uppercased(),
                       text: "\(g.short) for \(nick(t.team(g.side).name)): \(sv) saves tonight — real numbers. The play is drawn: it's what one of them looks like.",
                       lens: group == .keeper
                           ? "Watch his feet as the shot is hit: set, weight forward — then one big step and dive toward the ball."
                           : "Watch where the shot goes: near the keeper's body is a save. Low and across him is a goal.",
                       steal: "Shooting? Low and across the keeper. Keeping? Feet set before the strike, then dive at the ball.",
                       faces: [g])
        if group == .keeper { l.drill = Lens.drill(["Goalkeeping"], a) }
        var c = FilmClip(kind: .chance, side: g.side.other, scorer: shooter?.grid, star: g.grid, focus: k, pos: t.posLabel(g), len: saveLen, seed: g.id % 997 + 17, key: 0, allGame: true,
                         mark: .star,
                         call: Callout(title: "BIG SAVE", sub: "\(g.short.uppercased()) · \(sv) SAVES TONIGHT", tone: .green, at: 3.5),
                         lesson: l,
                         stops: [ReelStop(anchor: "strike", off: -0.1, marks: ["keeper"], title: "FEET SET", sub: "\(g.short) is still when it's hit. Then he goes.")],
                         rank: 1)
        c.play = g.id % 2 == 0 ? "long" : "solo"
        c.end = "save"
        return c
    }

    static func final(_ t: MatchTape, _ clips: [FilmClip], _ group: Lens.Group, _ a: Answers) -> Lesson {
        var bars: [NumberBar] = []
        var lines: [String] = []
        if let p = t.stats["Ball Possession"] { bars.append(NumberBar(title: "POSSESSION", home: p.home, away: p.away, unit: "%")) }
        if let x = t.stats["expected_goals"] {
            bars.append(NumberBar(title: "xG — HOW GOOD THE CHANCES WERE", home: x.home, away: x.away, unit: ""))
            lines.append("1.0 xG = chances that usually make one goal. " + xgNote(t, x))
        } else if let s = t.stats["Shots on Goal"] {
            bars.append(NumberBar(title: "SHOTS ON TARGET", home: s.home, away: s.away, unit: ""))
        }
        if let insight = TapeInsight.line(t) { lines.insert(insight, at: 0) }
        var faces: [Person] = []
        if let best = t.people.values.filter({ ($0.rating ?? 0) > 0 && $0.minutes >= 30 }).max(by: { ($0.rating ?? 0) < ($1.rating ?? 0) }) {
            lines.append("Best on the pitch: \(best.name), the \(t.role(best)) (\(String(format: "%.1f", best.rating ?? 0))). " + bestLine(t, best))
            faces.append(best)
        }
        let steals = Array(NSOrderedSet(array: clips.compactMap(\.lesson.steal))).compactMap { $0 as? String }
        return Lesson(tag: "FULL TIME", title: "WHAT TO STEAL", text: lines.joined(separator: "\n\n"),
                      steal: steals.prefix(3).map { "• " + $0 }.joined(separator: "\n"),
                      drill: Lens.drill(Lens.skills(group), a), faces: faces, bars: bars, final: true)
    }

    static func shapeNote(_ t: MatchTape) -> String {
        let (fh, fa) = t.formations
        if fh == fa { return "Same shape on both sides — every player has a man to beat, so 1v1s decide it." }
        for s in [Side.home, .away] {
            let n = t.backLine(s)
            if n == 3 { return "\(nick(t.team(s).name)) play 3 at the back: their wing backs cover a whole side alone. Watch the space behind them." }
            if n == 5 { return "\(nick(t.team(s).name)) defend with 5: hard to get behind, so look for space in front of them." }
        }
        return "Both play a back 4 — the gaps open between the full backs and centre backs."
    }

    static func xgNote(_ t: MatchTape, _ x: TeamStat) -> String {
        let h = (g: Double(t.score.0), x: x.home, n: nick(t.home.name)), a = (g: Double(t.score.1), x: x.away, n: nick(t.away.name))
        let pick = abs(h.g - h.x) >= abs(a.g - a.x) ? h : a
        let d = pick.g - pick.x
        if d >= 0.8 { return "\(pick.n) scored \(Int(pick.g)) from \(TapeInsight.fmt(pick.x)) xG — great finishing." }
        if d <= -0.8 { return "\(pick.n) scored \(Int(pick.g)) from \(TapeInsight.fmt(pick.x)) xG — they wasted good chances." }
        return "Both teams scored about what their chances were worth."
    }

    static func bestLine(_ t: MatchTape, _ p: Person) -> String {
        var bits: [String] = []
        func add(_ n: Int, _ one: String, _ many: String) { if n > 0 { bits.append("\(n) \(n == 1 ? one : many)") } }
        add(t.goals(of: p), "goal", "goals")
        add(t.assists(of: p), "assist", "assists")
        if p.pos == "G" { add(Int(p.stats["saves"] ?? 0), "save", "saves") }
        add(Int(p.stats["keyPasses"] ?? 0), "key pass", "key passes")
        add(Int(p.stats["dribbles"] ?? 0), "dribble past a man", "dribbles past a man")
        add(Int(p.stats["tackles"] ?? 0), "tackle", "tackles")
        add(Int(p.stats["onTarget"] ?? 0), "shot on target", "shots on target")
        return bits.prefix(3).joined(separator: " · ")
    }
}

/// One plain sentence the numbers say about the game.
enum TapeInsight {
    static func line(_ t: MatchTape) -> String? {
        let (h, a) = t.score
        guard h != a else {
            if let x = t.stats["expected_goals"] { return "A draw — and on chances it was \(fmt(x.home)) xG to \(fmt(x.away))." }
            return nil
        }
        let w: Side = h > a ? .home : .away
        let win = nick(t.team(w).name)
        func of(_ s: TeamStat?) -> (Double, Double)? { s.map { w == .home ? ($0.home, $0.away) : ($0.away, $0.home) } }
        if let p = of(t.stats["Ball Possession"]), p.0 < p.1 - 5 {
            return "\(win) had \(Int(p.0))% of the ball and still won. Chances beat possession."
        }
        if let x = of(t.stats["expected_goals"]), x.0 < x.1 {
            return "\(win) won with fewer chances (\(fmt(x.0)) xG to \(fmt(x.1))). Finishing won it."
        }
        if let s = of(t.stats["Shots on Goal"]) {
            return "\(win) put \(Int(s.0)) shots on target to \(Int(s.1)). Hit the target, win the game."
        }
        return nil
    }
    static func fmt(_ v: Double) -> String { String(format: "%.1f", v) }
}

// MARK: - the player (the film's clock lives in the 3D; this follows it)

@Observable
@MainActor
final class FilmPlayer {
    let tape: MatchTape
    let clips: [FilmClip]
    var index = 0
    var t = 0.0                      // play time inside the clip
    var stop = -1                    // the freeze being held (its caption is on the picture), ?1 = none
    var auto = false                 // counting down to the next moment
    private var autoTask: Task<Void, Never>?
    var playing = true
    var waiting = false              // stopped after a play so the class can be read
    var finished = false
    var seekId = 0
    var seekT = 0.0
    var point = CGPoint(x: 0.5, y: 0.3)
    var pointOn = false
    var kits = (home: "#F2F2F2", away: "#1B2A4A", homeGk: "#E8B21E", awayGk: "#2B2B2B")

    init(_ tape: MatchTape, _ a: Answers, start: Int = 0) {
        self.tape = tape
        clips = FilmPlan.build(tape, a)
        index = min(max(0, start), clips.count - 1)
    }

    var clip: FilmClip { clips[index] }
    var lesson: Lesson { clip.lesson }
    var reelStop: ReelStop? { clip.stops.indices.contains(stop) ? clip.stops[stop] : nil }
    var called: Bool { clip.call.map { t >= $0.at } ?? false }
    var score: (Int, Int) { t >= (clip.call?.at ?? 0) ? clip.after : clip.before }
    var clock: String {
        if clip.allGame { return "ALL GAME" }
        if index == clips.count - 1 { return "FULL TIME" }
        return minuteText(clip.key)
    }

    var stage: FilmStage {
        FilmStage(home: kits.home, away: kits.away, homeGk: kits.homeGk, awayGk: kits.awayGk,
                  homeGrid: tape.grids(.home), awayGrid: tape.grids(.away), clip: clip.stage, playing: playing,
                  seek: seekT, seekId: seekId)
    }

    func message(_ m: [String: Any]) {
        switch m["type"] as? String {
        case "time":
            if let v = m["t"] as? Double { t = min(clip.len, v) }
            if let x = m["fx"] as? Double, let y = m["fy"] as? Double { point = CGPoint(x: x, y: y) }
            pointOn = (m["fv"] as? Bool) ?? false
            let s = (m["s"] as? Int) ?? -1
            if s != stop {
                stop = s
                if s >= 0 { Haptics.play(.latch) }
            }
        case "end":
            guard (m["id"] as? Int) == clip.id, playing else { return }
            playing = false
            t = clip.len
            stop = -1
            if index == clips.count - 1 {
                finished = true
                PostHogSDK.shared.capture("match_film_completed", properties: [
                    "clip_count": clips.count,
                    "match_length_minutes": tape.length
                ])
                Matchday.shared.watched.insert(tape.id)
            } else {
                waiting = true
                // like a reel: the next moment rolls in on its own unless you stop to read
                auto = true
                autoTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(FilmPlayer.autoWait))
                    guard let self, !Task.isCancelled, self.auto, self.waiting else { return }
                    self.next()
                }
            }
        default: break
        }
    }

    /// Play / pause; after a play it moves on; at the end it starts again. (The gap between moments is a short beat ?
    /// there's no card to read any more.)
    nonisolated static let autoWait = 1.2

    func toggle() {
        if finished { jump(0); return }
        if waiting { next(); return }
        playing.toggle()
        Haptics.play(.latch)
    }
    /// Reading the card stops the countdown; NEXT still moves on.
    func stay() {
        guard auto else { return }
        auto = false
        autoTask?.cancel()
    }
    func next() {
        guard index < clips.count - 1 else { return }
        jump(index + 1)
    }
    /// Every moment is a cut: the 3D rebuilds the clip from its start (never a run-over from the last play).
    func jump(_ i: Int) {
        stay()
        index = min(max(0, i), clips.count - 1)
        t = 0
        stop = -1
        seekT = 0
        seekId += 1
        playing = true
        waiting = false
        finished = false
        Haptics.play(.latch)
    }
    func skip(_ d: Int) {
        if d > 0 { if index < clips.count - 1 { jump(index + 1) } }
        else { jump(t > 1.5 && !waiting ? index : max(0, index - 1)) }
    }
}

func minuteText(_ key: Int) -> String {
    let e = key / 100, x = key % 100
    if e >= 90 && x > 0 { return "90+\(x)'" }
    return "\(max(0, e))'"
}

// MARK: - the screen

/// FULL SCREEN (2026-10-24): the 3D game fills the phone. No class card under it ? the freezes (circle / arrow + a
/// short caption) teach on the picture. Lineups live behind one button on the film; full time gets one small panel.
struct TapePlayer: View {
    let tape: MatchTape
    var start = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    @State private var player: FilmPlayer?
    @State private var opened = Date()

    var body: some View {
        ZStack {
            Color(hex: 0x0B0D0F).ignoresSafeArea()
            if let player { FilmScreen(player: player) { dismiss() } }
        }
        .statusBarHidden()
        .onAppear { opened = Date() }
        // the film room counts as film watched (Stats tab), capped per sitting
        .onDisappear {
            let m = Date().timeIntervalSince(opened) / 60
            store.addFilm(m)
            Team.shared.log(film: tape, minutes: m)
        }
        .task {
            let p = FilmPlayer(tape, store.answers, start: start)
            player = p
            p.kits = await Kits.colours(tape)
        }
    }
}

/// The film, edge to edge: the 3D picture with native chrome on top ? close · score · LINEUPS, the reel bar,
/// the position label, the freeze caption, the callout, the controls.
private struct FilmScreen: View {
    let player: FilmPlayer
    let close: () -> Void
    @State private var lineups = false
    @State private var wasPlaying = false

    var body: some View {
        GeometryReader { g in
            let ins = g.safeAreaInsets
            let size = CGSize(width: g.size.width + ins.leading + ins.trailing, height: g.size.height + ins.top + ins.bottom)
            ZStack {
                Stage3DView(params: .film(player.stage), onMessage: { player.message($0) })
                    .contentShape(Rectangle())
                    .onTapGesture { if !lineups { player.toggle() } }
                // a soft dark fade behind the top chrome, so the score + clock read on bright grass
                VStack {
                    LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: ins.top + 130)
                    Spacer()
                }
                .allowsHitTesting(false)
                if player.called, player.stop < 0, !lineups, let call = player.clip.call {
                    CalloutTag(call: call, point: player.point, on: player.pointOn, size: size, top: ins.top + 150)
                        .id(player.clip.id)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Button(action: close) { Image(systemName: "xmark").font(.system(size: 15, weight: .heavy)) }
                            .buttonStyle(.gameRound(.charcoal, size: 38))
                            .accessibilityLabel("Close")
                        Spacer(minLength: 0)
                        ScoreBug(tape: player.tape, score: player.score, clock: player.clock)
                        Spacer(minLength: 0)
                        ShareButton(item: .film(player.tape), size: 38)
                        Button { showLineups(!lineups) } label: {
                            Image(systemName: lineups ? "xmark" : "person.3.fill").font(.system(size: 14, weight: .heavy))
                        }
                        .buttonStyle(.gameRound(lineups ? .brand : .charcoal, size: 38))
                        .accessibilityLabel(lineups ? "Close lineups" : "Lineups")
                    }
                    .padding(.horizontal, 14)
                    ReelBar(player: player).padding(.horizontal, 14).padding(.top, 10)
                    ZStack(alignment: .top) {
                        if let pos = player.clip.pos {
                            PositionTag(text: pos)
                                .id("pos-\(player.clip.id)")
                                .opacity(player.stop >= 0 || lineups ? 0 : 1)   // the freeze's caption takes this row
                                .transition(.opacity)
                        }
                        if let st = player.reelStop, !lineups {
                            StopCaption(stop: st, n: player.stop + 1, of: player.clip.stops.count)
                                .id("\(player.clip.id)-\(player.stop)")
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 14).padding(.top, 10)
                    if lineups {
                        LineupsPanel(tape: player.tape)
                            .padding(.horizontal, 14).padding(.top, 14)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    Spacer()
                    if player.finished && player.lesson.final && !lineups {
                        FullTimePanel(player: player, close: close)
                            .padding(.horizontal, 14).padding(.bottom, 4)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    FilmControls(player: player)
                }
                .padding(.top, ins.top)
                .padding(.bottom, max(ins.bottom, 8))
            }
            .frame(width: size.width, height: size.height)
            .ignoresSafeArea()
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: player.called)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: player.stop)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: lineups)
            .animation(.easeOut(duration: 0.25), value: player.finished)
        }
    }

    /// Lineups pause the film while they're up, and it plays on when they close.
    private func showLineups(_ on: Bool) {
        if on { wasPlaying = player.playing; if player.playing { player.playing = false } }
        else if wasPlaying && !player.playing && !player.waiting && !player.finished { player.playing = true }
        lineups = on
        Haptics.play(.latch)
    }
}

/// LINEUPS, behind its button on the film: both real XIs on a flat pitch + their formations.
private struct LineupsPanel: View {
    let tape: MatchTape
    var body: some View {
        FormationBoard(tape: tape)
            .frame(height: 330)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(hex: 0x0B0D0F).opacity(0.92)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(C.charInk, lineWidth: 2))
    }
}

/// Full time, on the picture: the numbers, the drill for your position, watch again / done.
private struct FullTimePanel: View {
    let player: FilmPlayer
    let close: () -> Void
    var body: some View {
        let l = player.lesson
        VStack(spacing: 10) {
            ForEach(l.bars, id: \.title) { NumbersView(n: $0, home: player.tape.home, away: player.tape.away) }
            if let d = l.drill { DrillToToday(id: d) }
            HStack(spacing: 10) {
                Button { player.jump(0) } label: { Label("AGAIN", systemImage: "arrow.counterclockwise") }
                    .buttonStyle(.game(.charcoal, height: 52, font: 17))
                Button("DONE", action: close).buttonStyle(.game(.brand, height: 52, font: 18))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(hex: 0x0B0D0F).opacity(0.9)))
    }
}

/// The label that points at the player: title + one line, with a little stem down to his head.
private struct CalloutTag: View {
    let call: Callout
    let point: CGPoint
    let on: Bool
    let size: CGSize
    var top: CGFloat = 74
    var body: some View {
        let tint: Color = call.tone == .gold ? C.gold : call.tone == .green ? C.brandHi : C.creme
        let ink: Color = call.tone == .gold ? C.goldInk : call.tone == .green ? C.brandInk : C.charInk
        let raw = point.x * size.width
        let x = on ? min(max(raw, 110), size.width - 110) : size.width / 2
        let y = on ? min(max(point.y * size.height - 40, top), size.height - 160) : top
        VStack(spacing: 0) {
            VStack(spacing: 1) {
                Text(call.title).font(F.display(22)).foregroundStyle(ink)
                Text(call.sub).font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundStyle(ink.opacity(0.85))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(C.charInk, lineWidth: 2))
            if on {
                Triangle().fill(tint).frame(width: 16, height: 10)
                    .overlay(Triangle().stroke(C.charInk, lineWidth: 2).mask(Rectangle().padding(.top, 2)))
                    .offset(x: min(90, max(-90, raw - x)), y: -1)
            }
        }
        .frame(maxWidth: 220)
        .position(x: x, y: y)
        .animation(.linear(duration: 0.12), value: point)
        .allowsHitTesting(false)
    }
}

private struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY)); p.closeSubpath() }
    }
}

/// WHO this moment is about, by position ? big enough to read at a glance, so a film splits into GOALKEEPER /
/// CENTER MID / STRIKER moments and you can spot your own position's plays.
private struct PositionTag: View {
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.fill").font(.system(size: 11, weight: .heavy))
            Text(text).font(.system(size: 13, weight: .heavy, design: .monospaced))
        }
        .foregroundStyle(C.charInk)
        .padding(.horizontal, 11).padding(.vertical, 5)
        .background(Capsule().fill(C.creme))
        .overlay(Capsule().stroke(C.charInk, lineWidth: 1.5))
        .allowsHitTesting(false)
        .accessibilityLabel("Position: \(text.lowercased())")
    }
}

/// ? ? ?, the scrubber with a marker per play, and the match clock.
private struct FilmControls: View {
    let player: FilmPlayer
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 16) {
                Button { player.skip(-1) } label: { Image(systemName: "backward.end.fill") }
                    .accessibilityLabel("Previous moment")
                Button { player.toggle() } label: {
                    Image(systemName: player.playing ? "pause.fill" : (player.finished ? "arrow.counterclockwise" : "play.fill"))
                        .font(.system(size: 20, weight: .heavy))
                        .frame(width: 26)
                }
                .accessibilityLabel(player.playing ? "Pause" : "Play")
                Button { player.skip(1) } label: { Image(systemName: "forward.end.fill") }
                    .accessibilityLabel("Next moment")
                Spacer()
                Text("\(player.index + 1) / \(player.clips.count)")
                    .font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundStyle(C.creme.opacity(0.8)).monospacedDigit()
                Text(player.clock).font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundStyle(C.brandHi).monospacedDigit()
            }
            .font(.system(size: 15, weight: .heavy))
            .foregroundStyle(C.creme)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.top, 18).padding(.bottom, 10)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom))
    }
}

/// The reel, one segment per moment (like stories): done = full, this one fills with its play, tap one to cut to it.
/// The segment's glyph says what it is ? ball = goal, star = star play; under it, the position it's about (GK, CM?).
private struct ReelBar: View {
    let player: FilmPlayer
    var body: some View {
        HStack(spacing: 4) {
            ForEach(player.clips) { c in
                let fill = c.id < player.index ? 1 : c.id > player.index ? 0 : (player.waiting || player.finished ? 1 : player.t / max(0.1, c.len))
                VStack(spacing: 3) {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.25))
                            Capsule().fill(C.brandHi).frame(width: g.size.width * fill)
                        }
                    }
                    .frame(height: 4)
                    mark(c).frame(height: 12)
                    Text(c.pos.map(FilmClip.short) ?? " ")
                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                        .foregroundStyle(c.id == player.index ? C.creme : C.creme.opacity(0.55))
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                .contentShape(Rectangle())
                .onTapGesture { player.jump(c.id) }
                .accessibilityLabel("Moment \(c.id + 1): \(c.lesson.tag)" + (c.pos.map { ", \($0.lowercased())" } ?? ""))
            }
        }
    }

    @ViewBuilder private func mark(_ c: FilmClip) -> some View {
        let on = c.id == player.index
        switch c.mark {
        case .goal: BallGlyph(size: on ? 12 : 10)
        case .star: Image(systemName: "star.fill").font(.system(size: on ? 11 : 9, weight: .heavy)).foregroundStyle(C.brandHi)
        case .red: RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0xFF5A4E)).frame(width: on ? 8 : 6, height: on ? 11 : 9)
        case .yellow: RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0xFFD21F)).frame(width: on ? 8 : 6, height: on ? 11 : 9)
        case .miss: Image(systemName: "xmark.circle.fill").font(.system(size: on ? 11 : 9, weight: .bold)).foregroundStyle(C.gold)
        case .none: Color.clear.frame(width: 1)
        }
    }
}

/// The freeze's caption, at the top of the picture (over the stands, never over the play): the big word + one plain
/// line. The marks on the pitch say the rest.
private struct StopCaption: View {
    let stop: ReelStop
    let n: Int
    let of: Int
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                HStack(spacing: 6) {
                    if of > 1 {
                        Text("\(n)/\(of)").font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundStyle(C.brandInk)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(C.brandHi))
                    }
                    Text(stop.title).font(F.display(23)).foregroundStyle(C.brandHi)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Text(stop.sub).font(F.round(14, .bold)).foregroundStyle(C.creme)
                    .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .frame(maxWidth: 340)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.black.opacity(0.66)))
        }
        .allowsHitTesting(false)
    }
}

/// The broadcast score bug: crest · score · crest, the clock under it.
struct ScoreBug: View {
    let tape: MatchTape
    let score: (Int, Int)
    let clock: String
    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 8) {
                CrestImage(url: tape.home.logo, size: 26)
                Text(abbr(tape.home.name)).font(F.display(15)).foregroundStyle(C.creme)
                Text("\(score.0) – \(score.1)")
                    .font(F.display(20)).foregroundStyle(C.charInk)
                    .padding(.horizontal, 9).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 6).fill(C.creme))
                    .contentTransition(.numericText())
                    .animation(.spring, value: score.0 + score.1)
                Text(abbr(tape.away.name)).font(F.display(15)).foregroundStyle(C.creme)
                CrestImage(url: tape.away.logo, size: 26)
            }
            Text(clock)
                .font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundStyle(C.brand)
                .monospacedDigit()
        }
    }
}

/// "Borussia Mönchengladbach" ? "Mönchengladbach", "VfB Stuttgart" ? "Stuttgart" (for sentences).
func nick(_ name: String) -> String {
    let skip: Set<String> = ["FC", "CF", "AC", "SC", "AFC", "SSC", "VfB", "VfL", "1.", "Borussia", "Stade", "Club", "RC", "GO", "SV", "TSG"]
    let words = name.split(separator: " ").map(String.init).filter { !skip.contains($0) }
    return words.isEmpty ? name : words.joined(separator: " ")
}

func abbr(_ name: String) -> String {
    let skip: Set<String> = ["FC", "CF", "AC", "SC", "AFC", "SSC", "VfB", "VfL", "1.", "Borussia", "Real", "Stade", "Al", "Club", "de", "RC", "Atletico", "GO"]
    let words = name.replacingOccurrences(of: "-", with: " ").split(separator: " ").map(String.init)
    let main = words.first { !skip.contains($0) && $0.count > 2 } ?? words.first ?? name
    return String(main.prefix(3)).uppercased()
}

/// A club crest: from the crest cache on the first frame when it's been seen before (RemoteImages, Library.swift).
struct CrestImage: View {
    let url: String
    var size: CGFloat
    @State private var loaded: UIImage?
    var body: some View {
        Group {
            if let img = loaded ?? RemoteImages.cached(url) {
                Image(uiImage: img).resizable().scaledToFit()
            } else {
                Circle().fill(C.char700)
            }
        }
        .frame(width: size, height: size)
        .task(id: url) { if RemoteImages.cached(url) == nil { loaded = await RemoteImages.load(url) } }
    }
}

/// Both real starting XIs on a flat pitch from their lineup slots: away defends the top goal, home the bottom.
private struct FormationBoard: View {
    let tape: MatchTape
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let pitch = Path(roundedRect: CGRect(x: 1, y: 1, width: w - 2, height: h - 2), cornerRadius: 10)
            ctx.fill(pitch, with: .color(Color(hex: 0x1F7A3A)))
            let chalk = GraphicsContext.Shading.color(.white.opacity(0.35))
            ctx.stroke(pitch, with: chalk, lineWidth: 1.5)
            ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: h / 2)); $0.addLine(to: CGPoint(x: w, y: h / 2)) }, with: chalk, lineWidth: 1.5)
            ctx.stroke(Path(ellipseIn: CGRect(x: w / 2 - h * 0.12, y: h / 2 - h * 0.12, width: h * 0.24, height: h * 0.24)), with: chalk, lineWidth: 1.5)
            ctx.stroke(Path(CGRect(x: w * 0.3, y: 1, width: w * 0.4, height: h * 0.11)), with: chalk, lineWidth: 1.5)
            ctx.stroke(Path(CGRect(x: w * 0.3, y: h - 1 - h * 0.11, width: w * 0.4, height: h * 0.11)), with: chalk, lineWidth: 1.5)
            for side in [Side.home, .away] {
                let slots = tape.grids(side).compactMap { g -> (Int, Int, String)? in
                    let p = g.split(separator: ":").compactMap { Int($0) }
                    return p.count == 2 ? (p[0], p[1], g) : nil
                }
                let rows = max(2, slots.map(\.0).max() ?? 2)
                let fill = side == .home ? C.creme : Color(hex: 0x1B2A4A)
                let ring = side == .home ? C.charInk : C.creme
                for (r, c, _) in slots {
                    let n = slots.filter { $0.0 == r }.count
                    // row 1 = keeper on his line; the forwards end just short of halfway
                    let depth = r == 1 ? 0.04 : 0.13 + Double(r - 2) / Double(max(1, rows - 2)) * 0.31
                    let fx = n > 1 ? 0.12 + 0.76 * Double(c - 1) / Double(n - 1) : 0.5
                    let x = (side == .home ? fx : 1 - fx) * w
                    let y = side == .away ? depth * h : (1 - depth) * h
                    let d: CGFloat = 14
                    let dot = Path(ellipseIn: CGRect(x: x - d / 2, y: y - d / 2, width: d, height: d))
                    ctx.fill(dot, with: .color(fill))
                    ctx.stroke(dot, with: .color(ring), lineWidth: 2)
                }
            }
        }
        .overlay(alignment: .topLeading) { tag(tape.away, tape.formations.1).padding(6) }
        .overlay(alignment: .bottomLeading) { tag(tape.home, tape.formations.0).padding(6) }
        .accessibilityLabel("\(tape.home.name) \(tape.formations.0) against \(tape.away.name) \(tape.formations.1)")
    }
    private func tag(_ t: Fixture.Team, _ f: String) -> some View {
        HStack(spacing: 4) {
            CrestImage(url: t.logo, size: 16)
            Text(f).font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundStyle(C.creme)
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(Capsule().fill(.black.opacity(0.5)))
    }
}

/// Possession / xG: a tug-of-war bar in the two crests' ends.
struct NumbersView: View {
    let n: NumberBar
    let home: Fixture.Team
    let away: Fixture.Team
    @State private var shown = false
    var body: some View {
        let tot = max(0.01, n.home + n.away)
        VStack(spacing: 8) {
            Text(n.title).font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundStyle(C.muted)
            HStack {
                CrestImage(url: home.logo, size: 30)
                Text(val(n.home)).font(F.display(26)).foregroundStyle(n.home >= n.away ? C.brandHi : C.creme)
                Spacer()
                Text(val(n.away)).font(F.display(26)).foregroundStyle(n.away > n.home ? C.brandHi : C.creme)
                CrestImage(url: away.logo, size: 30)
            }
            GeometryReader { g in
                HStack(spacing: 3) {
                    Capsule().fill(n.home >= n.away ? C.brand : C.char600).frame(width: max(8, (g.size.width - 3) * (shown ? n.home / tot : 0.5)))
                    Capsule().fill(n.away > n.home ? C.brand : C.char600)
                }
            }
            .frame(height: 14)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: 0x15191C)))
        .onAppear { withAnimation(.spring(response: 0.9, dampingFraction: 0.65).delay(0.15)) { shown = true } }
    }
    private func val(_ v: Double) -> String { n.unit == "%" ? "\(Int(v))%" : (v == v.rounded() ? "\(Int(v))" : String(format: "%.2f", v)) }
}

/// One tap puts the drill on today (a raw drill on today's plan); then it says so.
private struct DrillToToday: View {
    let id: String
    @Environment(AppStore.self) private var store
    var body: some View {
        let d = Library.shared.drill(id)
        let today = todayKey()
        let on = store.items(today).contains { $0.drill == d.id }
        Button {
            guard !on else { return }
            store.add(d.id, to: today)
            Haptics.play(.latch)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: on ? "checkmark.circle.fill" : "plus.circle.fill").font(.system(size: 22, weight: .heavy))
                VStack(alignment: .leading, spacing: 1) {
                    Text(on ? "ON TODAY'S PLAN" : "TRAIN IT TODAY").font(.system(size: 11, weight: .heavy, design: .monospaced))
                    Text(d.name).font(F.round(16, .bold)).lineLimit(1)
                }
                Spacer(minLength: 0)
                Text("\(d.min) MIN").font(.system(size: 12, weight: .heavy, design: .monospaced))
            }
            .foregroundStyle(on ? C.brandHi : C.charInk)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14).fill(on ? Color(hex: 0x15191C) : C.brandHi))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(on ? C.brandHi : C.charInk, lineWidth: 2))
        }
        .buttonStyle(.press)
        .accessibilityLabel(on ? "\(d.name) is on today's plan" : "Put \(d.name) on today's plan")
    }
}
