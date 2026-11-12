// Feeds the home-screen widgets (notes/34): after training, a Matchday pull or a watched film, write the shared
// snapshot (day log + match of the day + its two crests) and ask WidgetKit to redraw. Debounced: one write per burst.
import SwiftUI
import UIKit
import WidgetKit

@MainActor
enum WidgetSync {
    static weak var store: AppStore?
    private static var pending: Task<Void, Never>?

    static func push() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await write()
        }
    }

    /// The newest night's best film you haven't watched (else the night's best).
    static func matchOfTheDay(_ md: Matchday) -> MatchTape? {
        guard let day = md.latestDay else { return nil }
        let night = md.tapes.filter { $0.dayKey == day }
        return night.first { !md.watched.contains($0.id) } ?? night.first
    }

    private static func write() async {
        var snap = WidgetSnapshot()
        if let store {
            let cutoff = dateKey(addDays(Date(), -190))
            snap.trained = store.trained.filter { $0.key >= cutoff }
        }
        let md = Matchday.shared
        if let t = matchOfTheDay(md) {
            snap.match = .init(id: t.id, home: t.home.name, away: t.away.name, homeGoals: t.score.0, awayGoals: t.score.1,
                               league: t.fx.league.name, date: t.date,
                               minutes: store.map { FilmPlan.minutes(t, $0.answers) } ?? 5,
                               watched: md.watched.contains(t.id))
            // crests: only re-saved when the match changes
            if UserDefaults.standard.integer(forKey: "sm.widget.crests") != t.id {
                let h = await saveCrest(t.home.logo, "home"), a = await saveCrest(t.away.logo, "away")
                if h && a { UserDefaults.standard.set(t.id, forKey: "sm.widget.crests") }
            }
        }
        snap.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func saveCrest(_ url: String, _ side: String) async -> Bool {
        guard let img = await RemoteImages.load(url), let to = WidgetSnapshot.crest(side) else { return false }
        // small and square: widgets have a tight memory budget
        let px: CGFloat = 120
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let small = UIGraphicsImageRenderer(size: CGSize(width: px, height: px), format: fmt).image { _ in
            let s = img.size, k = min(px / s.width, px / s.height)
            img.draw(in: CGRect(x: (px - s.width * k) / 2, y: (px - s.height * k) / 2, width: s.width * k, height: s.height * k))
        }
        guard let png = small.pngData() else { return false }
        return (try? png.write(to: to, options: .atomic)) != nil
    }
}
