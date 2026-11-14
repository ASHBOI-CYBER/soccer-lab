// What the home-screen widgets show (notes/34): the app writes this small file into the shared App Group after
// training or a Matchday pull; the widgets only read it. Crests are saved next to it as PNGs (widgets can't download).
import Foundation

struct WidgetSnapshot: Codable {
    /// The match of the day: the newest night's best film you haven't watched.
    struct Match: Codable {
        var id: Int
        var home: String
        var away: String
        var homeGoals: Int
        var awayGoals: Int
        var league: String
        var date: Date
        var minutes: Int        // film length
        var watched: Bool
    }

    var trained: [String: Double] = [:]     // day key ? minutes (last ~6 months)
    var match: Match?
    var updated = Date()

    static let group = "group.com.skillerai.ios"
    static var folder: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) }
    static var file: URL? { folder?.appendingPathComponent("widget.json") }
    static func crest(_ side: String) -> URL? { folder?.appendingPathComponent("crest-\(side).png") }

    static func load() -> WidgetSnapshot? {
        guard let f = file, let d = try? Data(contentsOf: f) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: d)
    }

    func save() {
        guard let f = Self.file, let d = try? JSONEncoder().encode(self) else { return }
        try? d.write(to: f, options: .atomic)
    }

    /// The widget gallery / first install: a believable run so the previews aren't empty.
    static var sample: WidgetSnapshot {
        var s = WidgetSnapshot()
        let today = Calendar.current.startOfDay(for: Date())
        for back in 0..<120 {
            let r = (back * 37 + 11) % 10
            if back < 12 ? r < 7 : r < 4 { s.trained[dateKey(addDays(today, -back))] = back == 0 ? 6 : Double(10 + r * 3) }
        }
        s.trained[dateKey(addDays(today, -1))] = 24
        s.match = Match(id: 0, home: "Arsenal", away: "Chelsea", homeGoals: 2, awayGoals: 1, league: "Premier League",
                        date: addDays(today, -1), minutes: 6, watched: false)
        return s
    }
}
