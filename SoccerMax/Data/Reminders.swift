// REMINDERS (v2, 2026-11-19). Local notifications only: nothing is sent from a server, and nothing leaves the phone.
// Asked for once in onboarding (NotifyStep) and switched on/off in Settings → Streak reminders.
//   1. TRAINING DAYS  5 PM on each of the player's training days for the next two weeks (never on a recovery day,
//                     LabPlan.restDays), named after that day's session: "Today: Passing & First Touch".
//   2. STREAK         the evening before the streak goes out (AirStreak.deadline), if today hasn't counted yet.
//   3. FREE TRIAL     a day before an Apple free trial turns into the first payment.
// The list is rebuilt every time the app opens or closes (`refresh`), so it always matches the plan and the streak.
// iOS keeps at most 64 pending notifications per app; this schedules at most 16.
import UIKit
import UserNotifications

enum Reminders {
    private static let dayCount = 14
    private static var ids: [String] {
        (0..<dayCount).map { "train-\($0)" } + ["streak-end", "trial-end"]
    }

    /// Asks iOS (the system prompt only ever shows once) and schedules. false = not allowed.
    @MainActor
    static func turnOn(_ store: AppStore) async -> Bool {
        let ok = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard ok else { return false }
        store.answers.notify = true
        await refresh(store)
        return true
    }

    static func turnOff() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// iOS said no earlier: only the Settings app can change it.
    static func denied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    /// Rebuilds every pending reminder from the plan, the streak and the subscription. Does nothing unless the player
    /// switched reminders on and iOS still allows them.
    @MainActor
    static func refresh(_ store: AppStore) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        guard store.answers.notify == true,
              await center.notificationSettings().authorizationStatus == .authorized else { return }
        let a = store.answers
        let cal = Calendar.current
        let now = Date()

        // 1. training days, 5 PM
        for i in 0..<dayCount {
            guard let day = cal.date(byAdding: .day, value: i, to: cal.startOfDay(for: now)),
                  let at = cal.date(bySettingHour: 17, minute: 0, second: 0, of: day), at > now else { continue }
            if LabPlan.restDays(training: a.trainingDaysPerWeek).contains(todayKey(day)) { continue }
            // today's is skipped once training has started (they don't need telling)
            if i == 0, !(Lab.shared.done[Lab.shared.today] ?? []).isEmpty { continue }
            let drills = LabPlan.today(position: a.position, date: day)
            let minutes = drills.reduce(0) { $0 + $1.min }
            await add("train-\(i)", at: at,
                      title: "Today: \(LabPlan.title(position: a.position, date: day))",
                      body: "\(a.firstName), your \(minutes)-minute session is ready. \(drills.count) drills.")
        }

        // 2. the streak is about to go out
        let air = store.air
        if air.alive, !air.keptToday, let end = air.deadline {
            let warn = end.addingTimeInterval(-5 * 3600)
            if warn > now {
                await add("streak-end", at: warn, title: "Your \(air.days)-day streak ends tonight",
                          body: "10 minutes of training keeps it alive.")
            }
        }

        // 3. the free trial is about to become a paid plan
        if let e = Purchases.shared.entitlement, e.isActive, e.periodType == .trial, e.willRenew, let end = e.expirationDate {
            let warn = end.addingTimeInterval(-24 * 3600)
            if warn > now {
                await add("trial-end", at: warn, title: "Your free trial ends tomorrow",
                          body: "Your Soccer Lab plan starts then. You can manage it in Settings, under your name, Subscriptions.")
            }
        }
    }

    private static func add(_ id: String, at date: Date, title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content,
                                  trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
    }
}
