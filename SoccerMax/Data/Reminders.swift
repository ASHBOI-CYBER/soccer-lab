// Streak reminders (2026-11-08): local notifications Mon/Wed/Fri 5 PM, so one lands before the 10-min-every-3-days
// streak goes out. Asked for in onboarding (NotifyStep) and switched on/off in Settings ? REMINDERS.
// Social picks in onboarding ("Join my team"?) get the team-streak wording.
import UIKit
import UserNotifications

enum Reminders {
    private static let ids = (0..<7).map { "train-\($0)" }

    /// Title + body, worded for what the player wants most.
    static func note(_ a: Answers) -> (String, String) {
        TEAMS_ON && Wants.social(a.wants ?? [])
            ? ("Your team is counting on you", "\(a.firstName), 10 minutes today keeps the team streak alive.")
            : ("Keep your streak alive", "\(a.firstName), 10 minutes today keeps your fire going.")
    }

    /// Asks iOS (only shows the system prompt the first time) and schedules. false = not allowed.
    static func turnOn(_ a: Answers) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let ok = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard ok else { return false }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        let n = note(a)
        let weekday = ["Sun": 1, "Mon": 2, "Tue": 3, "Wed": 4, "Thu": 5, "Fri": 6, "Sat": 7]
        let days = a.days.isEmpty ? ["Mon", "Wed", "Fri"] : a.days
        for (i, d) in days.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = n.0
            content.body = n.1
            content.sound = .default
            var when = DateComponents()
            when.weekday = weekday[d]
            when.hour = 17
            try? await center.add(UNNotificationRequest(identifier: "train-\(i)", content: content,
                                                        trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true)))
        }
        return true
    }

    static func turnOff() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// iOS said no earlier ? only the Settings app can change it.
    static func denied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }
}
