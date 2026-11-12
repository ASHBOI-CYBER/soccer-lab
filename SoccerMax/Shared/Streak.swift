// Shared by the app AND the home-screen widgets (SoccerMaxWidgets): day keys and the streak maths, so a widget
// counts the fire exactly like the Stats tab does (notes/19 "Stats tab", notes/34 widgets).
import Foundation

/// "2026-10-23" ? the key the set log and finished days are saved under.
func dateKey(_ d: Date) -> String {
    let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
    return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
}

/// "2026-10-23" ? that day's start.
func keyDate(_ k: String) -> Date? {
    let p = k.split(separator: "-").compactMap { Int($0) }
    guard p.count == 3 else { return nil }
    return Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
}

func addDays(_ d: Date, _ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: n, to: d)! }
func daysBetween(_ a: Date, _ b: Date) -> Int {
    Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: a), to: Calendar.current.startOfDay(for: b)).day ?? 0
}

// MARK: - the streak: 10 min at least once every 3 days keeps the fire lit

struct AirStreak {
    static let keep = 10.0       // minutes in a day that count
    static let window = 3        // at least once every 3 days (was 4 until 2026-10-27)

    var days = 0                 // calendar days the streak has been alive (0 = out)
    var best = 0
    var deadline: Date?          // the moment the fire goes out
    var today = 0.0              // minutes trained today
    var alive: Bool { days > 0 }
    var keptToday: Bool { today >= Self.keep }

    /// 1 = full fire, 0 = out. A full window is 3 days; training today tops it up.
    func air(_ now: Date = Date()) -> Double {
        guard let deadline, alive else { return 0 }
        return max(0, min(1, deadline.timeIntervalSince(now) / Double(Self.window * 86_400)))
    }

    /// The streak from the day log (`trained`: day key ? minutes), as it stands at `now`.
    static func compute(_ trained: [String: Double], now: Date = Date()) -> AirStreak {
        var s = AirStreak()
        s.today = trained[dateKey(now)] ?? 0
        let kept = trained.filter { $0.value >= keep }.keys.compactMap(keyDate).filter { $0 <= now }.sorted()
        guard !kept.isEmpty else { return s }
        // Chains: two kept days at most 3 apart stay one streak.
        var start = kept[0], best = 1
        for i in kept.indices.dropFirst() {
            if daysBetween(kept[i - 1], kept[i]) > window { start = kept[i] }
            best = max(best, daysBetween(start, kept[i]) + 1)
        }
        let deadline = addDays(kept.last!, window + 1)          // goes out at midnight, 3 days after the last kept day
        if now < deadline {
            s.days = daysBetween(start, now) + 1
            s.deadline = deadline
        }
        s.best = max(best, s.days)
        return s
    }
}
