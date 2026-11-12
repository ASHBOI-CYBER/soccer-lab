// The Live Activity for a running session (2026-10-28, notes/19 "SESSION PLAYER"): lock screen + Dynamic Island
// show the drill, "drill 2 of 5", a segmented bar and the drill timer. Shared by the app (starts/updates it) and
// the widget extension (draws it).
import ActivityKit
import Foundation

struct SessionActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var drill: String
        var dose: String
        /// 0-based drill index and how many drills the session has.
        var index: Int
        var count: Int
        /// While running: when the drill's timer would have read 0:00 (now ? elapsed), so the system counts it up.
        var startedAt: Date
        /// Seconds on the clock when paused (nil = running).
        var paused: Int?
    }
    var session: String
}

/// "4:07", "1:02:09"
func clock(_ seconds: Int) -> String {
    let s = max(0, seconds)
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
}
