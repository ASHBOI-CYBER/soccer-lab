// The drill + move library, read from library.json (exported from src/data by scripts/export-native.mjs,
// so the web scenes and the native app always describe the same drills).
import Foundation
import ImageIO
import SwiftUI
import UIKit

/// One piece of equipment: the 3D icon (Resources/Gear/<item>.png, nil = words only) and its label ("5 cones").
struct GearPiece: Codable, Hashable {
    let item: String?
    let label: String

    var image: UIImage? { item.flatMap { ImageCache.load($0, ext: "png", dir: "Gear") } }
}

/// Bundled stills, decoded once ? off the main thread at launch (`warm`), so pages open with their pictures already
/// there (2026-10-28, user: "make every page quick and snappy"). `maxPixel` decodes straight to a smaller size: a tile
/// never pays for a full 1200×1538 photo.
enum ImageCache {
    private static let cache = NSCache<NSString, UIImage>()
    /// Tiles (shelf posters, technique tiles, My sessions cards) ? ~3× their biggest on-screen size.
    static let tile = 800
    static func load(_ name: String, ext: String, dir: String, maxPixel: Int? = nil) -> UIImage? {
        let key = "\(dir)/\(name).\(ext)@\(maxPixel ?? 0)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: dir) else { return nil }
        let img: UIImage?
        if let maxPixel, let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [
               kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maxPixel,
               kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) {
            img = UIImage(cgImage: cg)
        } else {
            img = UIImage(contentsOfFile: url.path)?.preparingForDisplay()
        }
        guard let img else { return nil }
        cache.setObject(img, forKey: key)
        return img
    }

    /// Decode everything the first screens show, in the background, right after launch.
    static func warm() {
        Task.detached(priority: .utility) {
            _ = load("mascot", ext: "png", dir: "Mascot")
            for i in 1...5 { _ = load("level-\(i)", ext: "webp", dir: "Stadiums", maxPixel: 1200) }
            _ = load("pledge-poster", ext: "webp", dir: "Stadiums", maxPixel: 1400)   // the pledge's instant first frame
            let lib = Library.shared
            for p in lib.pros + lib.technique + lib.fitness + lib.workouts + lib.hybrid { _ = p.image(tile: true) }
            for d in lib.drills { for g in d.kit { _ = g.image } }
        }
    }
}

/// Web pictures (club crests) kept in memory and on disk: after the first download they show on the first frame ?
/// AsyncImage re-downloaded them every time a row appeared, so every list opened on grey circles.
enum RemoteImages {
    private static let memory = NSCache<NSString, UIImage>()
    private static let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("crests", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    private static func name(_ url: String) -> String {
        String(url.map { $0.isLetter || $0.isNumber || $0 == "." ? $0 : "_" })
    }
    /// Already decoded (no disk, no network) ? safe to call from a view body.
    static func cached(_ url: String) -> UIImage? { memory.object(forKey: name(url) as NSString) }

    static func load(_ url: String) async -> UIImage? {
        if let hit = cached(url) { return hit }
        let file = dir.appendingPathComponent(name(url))
        if let d = try? Data(contentsOf: file), let img = await UIImage(data: d)?.byPreparingForDisplay() {
            memory.setObject(img, forKey: name(url) as NSString)
            return img
        }
        guard let u = URL(string: url), let (d, _) = try? await URLSession.shared.data(from: u), let raw = UIImage(data: d) else { return nil }
        try? d.write(to: file)
        let img = await raw.byPreparingForDisplay() ?? raw
        memory.setObject(img, forKey: name(url) as NSString)
        return img
    }

    /// Every crest saved on disk ? memory, in the background at launch.
    static func warm() {
        Task.detached(priority: .utility) {
            guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
            for f in files where memory.object(forKey: f.lastPathComponent as NSString) == nil {
                if let img = UIImage(contentsOfFile: f.path)?.preparingForDisplay() {
                    memory.setObject(img, forKey: f.lastPathComponent as NSString)
                }
            }
        }
    }
}

/// A drill is TEXT plus a still 3D picture of its setup (notes/21): no animation.
struct Drill: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let skill: String
    let level: Int
    let who: String
    let min: Int
    let space: String
    let gear: [String]
    let kit: [GearPiece]
    let needs: [String]
    let setup: String
    /// How to do it, 3?5 plain steps.
    let how: [String]
    let reps: String
    let points: [String]
    let progression: String?
    let stats: [String]
    let fixes: [String]
    let fears: [String]?
    let tags: [String]?
    let sources: [String]?
    /// The 3D guy plays this drill (notes/22); false = text + the still setup (simple taps, runs with no ball).
    let video: Bool?
    /// No video ? the flat top-down coach's board (UI/DrillBoard.swift, 2026-10-27).
    let board: Board?

    var hasVideo: Bool { video ?? false }
    /// Ball work = Skills; no ball (runs, core, agility, stretches) = Fitness (2026-10-24).
    var usesBall: Bool { needs.contains("Ball") }
    var levelName: String { Library.shared.levelNames[safe: level] ?? "" }
    var gearLine: String { gear.isEmpty ? "nothing" : gear.map { $0.lowercased() }.joined(separator: ", ") }
    /// The setup picture (a 3D still rendered by scripts/render-setups.mjs), cached: the list redraws rows a lot.
    var cover: UIImage? { ImageCache.load(id, ext: "jpg", dir: "Covers") }
}

struct MoveStep: Codable, Hashable { let text: String; let k: Int }

struct Move: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let level: Int
    let use: String
    let famous: String?
    let scene: String
    let steps: [MoveStep]
    let dur: Double
    let keyTimes: [Double]

    /// Which step the loop is on at time t (?1 = still running in).
    func step(at t: Double) -> Int {
        let tt = (t.truncatingRemainder(dividingBy: dur) + dur).truncatingRemainder(dividingBy: dur)
        var s = -1
        for (i, st) in steps.enumerated() where tt >= keyTimes[st.k] - 0.12 { s = i }
        return s
    }
}

struct Template: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let sub: String
    let days: [String]
    let tint: String
    let perDay: Int
    let drills: [String]
}

/// A training level ? one ground on the Sessions tab's stadium carousel (notes/23). Premade sessions are rebuilt for
/// each one by the export: more drills, harder drills, more sets, longer.
struct TrainingLevel: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    /// About how long a premade session runs at this level.
    let minutes: Int
    let line: String
}

/// A real player's photo from Wikimedia Commons (free licence), bundled as Resources/Players/<pro id>.jpg and credited
/// on the session page with its licence.
struct PlayerPhoto: Codable, Hashable {
    let by: String
    let license: String
    let licenseURL: String?
    let page: String
    /// Where the face is (0?1 across, 0?1 down): every crop keeps it in frame.
    let focus: [Double]

    var focusPoint: CGPoint { CGPoint(x: focus[safe: 0] ?? 0.5, y: focus[safe: 1] ?? 0.3) }
}

struct ProDrill: Codable, Hashable { let id: String; let sets: Int? }

/// A premade session (notes/23): a real player's (photo, position) or a technique one (no player). Solo drills only:
/// warm-up stretch(es), the work, cool-down stretch(es) ? one list per training level.
struct ProSession: Codable, Identifiable, Hashable {
    let id: String
    /// The player's name, or the technique ("First Touch").
    let title: String
    let player: String?
    /// The name on small tiles ("DE BRUYNE").
    let short: String?
    let position: String?
    /// Onboarding position codes this session is built for; the first one is its main spot (players only).
    let positions: [String]?
    let photo: PlayerPhoto?
    /// A fitness session's one word ("Speed", "Engine") ? nil for skills sessions.
    let quality: String?
    /// "workout" / "hybrid" for the no-player sessions drawn as a 3D kit scene (2026-10-27).
    let kind: String?
    let levels: [[ProDrill]]

    var isPlayer: Bool { player != nil }
    func items(_ level: Int) -> [PlanItem] { (levels[safe: level] ?? levels.last ?? []).map { PlanItem($0.id, sets: $0.sets) } }
    func minutes(_ level: Int) -> Int { items(level).reduce(0) { $0 + $1.min } }
    /// The picture: a player's photo (Resources/Players) or the 3D guy mid-move (Resources/Technique).
    var image: UIImage? { image(tile: false) }
    /// `tile` = decoded at tile size (shelves, small cards); the full photo is only for the session page's hero.
    func image(tile: Bool) -> UIImage? {
        ImageCache.load(id, ext: "jpg", dir: isPlayer ? "Players" : "Technique", maxPixel: tile ? ImageCache.tile : nil)
    }
    var focus: CGPoint { photo?.focusPoint ?? CGPoint(x: 0.5, y: kind == nil ? 0.45 : 0.62) }  // kit scenes: the kit sits low
}

struct Axis: Codable, Hashable { let key: String; let label: String; let builds: String }

struct SamplePlayer: Codable { let name: String; let level: Int; let xp: Int; let xpMax: Int; let streak: Int; let position: String; let foot: String }

final class Library: Decodable {
    static let shared: Library = {
        let url = Bundle.main.url(forResource: "library", withExtension: "json")!
        return try! JSONDecoder().decode(Library.self, from: Data(contentsOf: url))
    }()

    let categories: [String]
    let levelNames: [String]
    let drills: [Drill]
    let ladders: [String: [String]]
    /// Cut drills ? their replacement (a saved plan keeps working).
    let removed: [String: String]
    let moves: [Move]
    let moveLevels: [String: String]
    let templates: [Template]
    let axes: [Axis]
    let start: [String: Int]
    let now: [String: Int]
    let player: SamplePlayer
    let positions: [String: String]
    let skills: [String]
    /// The five training levels, Park ? World Class (src/data/pros.json).
    let levels: [TrainingLevel]
    /// Real-player sessions in shelf order, then the technique sessions (src/data/pros.json).
    let pros: [ProSession]
    let technique: [ProSession]
    /// Real-player FITNESS sessions ? no ball: "Mbappé Speed", "Kanté Engine"? (2026-10-24, src/data/pros.json).
    let fitness: [ProSession]
    /// FITNESS workouts with no player ? a 3D kit scene, no ball ("Sprint Speed", "Core Strength"; 2026-10-27).
    let workouts: [ProSession]
    /// SOCCER + FITNESS ? ball drills and runs, one after the other ("Sprint & Shoot"; 2026-10-27).
    let hybrid: [ProSession]

    func pro(_ id: String) -> ProSession? {
        pros.first { $0.id == id } ?? technique.first { $0.id == id } ?? fitness.first { $0.id == id }
            ?? workouts.first { $0.id == id } ?? hybrid.first { $0.id == id }
    }
    /// A premade FITNESS session (its saved copy lives under Fitness in My sessions). Soccer + fitness has the ball ? Skills.
    func isFitness(pro id: String) -> Bool { fitness.contains { $0.id == id } || workouts.contains { $0.id == id } }
    /// The Pro Session built for a position: its main spot first, then any that list it.
    func pro(for position: String, in list: [ProSession]? = nil) -> ProSession? {
        let list = list ?? pros
        return list.first { $0.positions?.first == position } ?? list.first { $0.positions?.contains(position) == true }
    }
    /// The shelf: the player's own position first, then the rest.
    func pros(for position: String) -> [ProSession] { mineFirst(pros, position) }
    func fitness(for position: String) -> [ProSession] { mineFirst(fitness, position) }
    private func mineFirst(_ list: [ProSession], _ position: String) -> [ProSession] {
        guard let mine = pro(for: position, in: list) else { return list }
        return [mine] + list.filter { $0.id != mine.id }
    }

    private lazy var byId: [String: Drill] = Dictionary(uniqueKeysWithValues: drills.map { ($0.id, $0) })

    func drill(_ id: String) -> Drill { byId[id] ?? removed[id].flatMap { byId[$0] } ?? drills[0] }
    func has(_ id: String) -> Bool { byId[id] != nil || removed[id].map { byId[$0] != nil } == true }
    func move(_ id: String) -> Move { moves.first { $0.id == id } ?? moves[0] }

    func ladder(_ category: String) -> [Drill] { (ladders[category] ?? []).compactMap { byId[$0] } }

    /// The next rung up the drill's ladder.
    func next(after d: Drill) -> Drill? {
        let l = ladder(d.skill)
        guard let i = l.firstIndex(of: d), i + 1 < l.count else { return nil }
        return l[i + 1]
    }

    /// Text search over name, skill, who, gear, steps, keys, tags and what it fixes. Every word must match somewhere.
    func search(_ q: String, in list: [Drill]? = nil) -> [Drill] {
        let words = q.lowercased().split(whereSeparator: { $0 == " " }).map(String.init)
        let pool = list ?? drills
        guard !words.isEmpty else { return pool }
        return pool.filter { d in
            let hay = haystack(d)
            return words.allSatisfy { hay.contains($0) }
        }
    }

    private lazy var hay: [String: String] = Dictionary(uniqueKeysWithValues: drills.map { d in
        (d.id, ([d.name, d.skill, d.who, d.levelName, d.setup] + d.gear + d.how + d.points + (d.tags ?? []) + d.fixes)
            .joined(separator: " ").lowercased())
    })
    private func haystack(_ d: Drill) -> String { hay[d.id] ?? d.name.lowercased() }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

let DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
let FULL_DAY = ["Mon": "MONDAY", "Tue": "TUESDAY", "Wed": "WEDNESDAY", "Thu": "THURSDAY", "Fri": "FRIDAY", "Sat": "SATURDAY", "Sun": "SUNDAY"]

func todayKey(_ date: Date = Date()) -> String {
    ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][Calendar.current.component(.weekday, from: date) - 1]
}

/// The date of a weekday in this Mon?Sun week.
func dateOf(_ day: String, now: Date = Date()) -> Date {
    let cal = Calendar.current
    let today = (cal.component(.weekday, from: now) + 5) % 7  // Mon = 0
    return cal.date(byAdding: .day, value: (DAYS.firstIndex(of: day) ?? 0) - today, to: cal.startOfDay(for: now))!
}

// dateKey(_:) lives in Shared/Streak.swift (the widgets use it too).

private let monthFormat: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US")
    f.dateFormat = "MMM"
    return f
}()

/// "OCT 23"
func shortDate(_ day: String) -> String {
    let d = dateOf(day)
    return "\(monthFormat.string(from: d).uppercased()) \(Calendar.current.component(.day, from: d))"
}

func dayNumber(_ day: String) -> Int { Calendar.current.component(.day, from: dateOf(day)) }

/// "OCT 19 ? 25", or "SEP 28 ? OCT 4" across a month.
func weekRange() -> String {
    let a = shortDate("Mon"), b = shortDate("Sun")
    return a.prefix(3) == b.prefix(3) ? "\(a)–\(dayNumber("Sun"))" : "\(a) – \(b)"
}
