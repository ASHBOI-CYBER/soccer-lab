// BACKUP (2026-10-29): delete the app, sign back in with Apple ? everything is still there.
// CHEAP ON PURPOSE (user: Caffeine Mog's photos made server costs bigger than the profits):
//   ? ONE row per player in Supabase `backups` (native/supabase/2026-10-29-backups.sql), ONE small JSON blob of what the
//     app already keeps in UserDefaults (answers, sessions, set log, minutes, streak days, settings ? usually 5?40 KB).
//   ? ONE profile picture, 240 px JPEG (~15 KB), sent only when it changes. No Storage bucket, no videos, no files.
//   ? Written only when the app goes to the background AND something changed (a hash of the blob). Read once per sign-in.
// SAFETY: a phone never uploads before it has checked the cloud once (`checked`), so a fresh install can't wipe a backup.
// A phone that already has training on it MERGES with the cloud (max minutes per day, union of days/sessions) ? nothing lost.
import CryptoKit
import Foundation
import Observation
import UIKit

@MainActor @Observable
final class Backup {
    static let shared = Backup()

    /// nil = not looked yet this sign-in; true / false = the cloud had a saved player or not.
    private(set) var found: Bool?
    private(set) var busy = false

    /// UserDefaults keys holding JSON (AppStore + Matchday). Everything a player built or earned.
    private let dataKeys = ["sm.answers.v1", "sm.plan.v1", "sm.sessions.v1", "sm.moves.v1", "sm.log.v1", "sm.finished.v1",
                            "sm.trained.v1", "sm.film.v1", "sm.completions.v1", "sm.club.v1", "sm.md.watched.v1"]
    /// Plain values: dates kept, level picked, settings, the one-free-week flag, the gift code.
    private let plainKeys = ["sm.since", "sm.seenlevel", "sm.level.v1", "sm.remind", "sm.haptics", "sm.units",
                             ShownTeam.key, "sm.fireHint", "sm.trial.used", "sm.gift.code", "sm.fitness.v1"]
    private let checkedKey = "sm.backup.checked", sentKey = "sm.backup.sent", picKey = "sm.backup.pic"
    private var ud: UserDefaults { .standard }
    private var api: SupabaseREST { Team.shared.api }

    /// Forget this phone's backup state (sign out ? another account may sign in next).
    func reset() {
        found = nil
        for k in [checkedKey, sentKey, picKey] { ud.removeObject(forKey: k) }
    }

    // MARK: pull (once per sign-in)

    /// Read the cloud copy and bring it onto the phone. Returns true when there was a saved player.
    @discardableResult
    func pull(_ store: AppStore) async -> Bool {
        guard api.hasAccount, !busy, let uid = try? await api.userId() else { return false }
        busy = true; defer { busy = false }
        guard let raw = try? await api.raw("backups?select=data,photo&user_id=eq.\(uid)"),
              let rows = try? JSONSerialization.jsonObject(with: raw) as? [[String: Any]] else {
            found = false       // offline, or the table isn't there yet: carry on, and look again before any upload
            return false        // (never marked checked, so nothing is ever sent over a backup this phone hasn't seen)
        }
        ud.set(true, forKey: checkedKey)
        guard let row = rows.first, let blob = row["data"] as? [String: Any] else { found = false; return false }
        let fresh = !store.onboarded || (store.trained.isEmpty && store.completions.isEmpty)
        apply(blob, replace: fresh)
        store.reload()
        if store.avatar == nil, let b64 = row["photo"] as? String, let d = Data(base64Encoded: b64), let img = UIImage(data: d) {
            store.setAvatar(img)
        }
        ud.removeObject(forKey: sentKey)    // a merge may have added to it: send the merged copy next time
        found = true
        return true
    }

    private func apply(_ blob: [String: Any], replace: Bool) {
        let data = blob["data"] as? [String: Any] ?? [:]
        let plain = blob["plain"] as? [String: Any] ?? [:]
        for (k, remote) in data where dataKeys.contains(k) {
            let local = ud.data(forKey: k).flatMap { try? JSONSerialization.jsonObject(with: $0, options: .fragmentsAllowed) }
            let out = (replace || local == nil) ? remote : merge(k, local!, remote)
            if let d = try? JSONSerialization.data(withJSONObject: out, options: .fragmentsAllowed) { ud.set(d, forKey: k) }
        }
        for (k, remote) in plain where plainKeys.contains(k) {
            let local = ud.object(forKey: k)
            if replace || local == nil { ud.set(remote, forKey: k); continue }
            if k == "sm.since", let a = local as? String, let b = remote as? String { ud.set(min(a, b), forKey: k) }
            if k == "sm.trial.used", (remote as? Bool) == true { ud.set(true, forKey: k) }   // one free week per account
        }
    }

    /// Both phones trained: keep the most of everything, never less.
    private func merge(_ key: String, _ local: Any, _ remote: Any) -> Any {
        switch key {
        case "sm.trained.v1", "sm.film.v1":           // date ? minutes
            guard var l = local as? [String: Double], let r = remote as? [String: Double] else { return local }
            for (d, v) in r { l[d] = max(l[d] ?? 0, v) }
            return l
        case "sm.log.v1":                              // date ? drill ? sets
            guard var l = local as? [String: [String: Int]], let r = remote as? [String: [String: Int]] else { return local }
            for (d, drills) in r { for (id, n) in drills { l[d, default: [:]][id] = max(l[d]?[id] ?? 0, n) } }
            return l
        case "sm.finished.v1", "sm.moves.v1", "sm.md.watched.v1":   // sets kept as arrays
            guard let l = local as? [AnyHashable], let r = remote as? [AnyHashable] else { return local }
            return Array(Set(l).union(r))
        case "sm.completions.v1":                      // finished sessions, one per moment
            guard let l = local as? [[String: Any]], let r = remote as? [[String: Any]] else { return local }
            let seen = Set(l.compactMap { $0["date"] as? Double })
            return (l + r.filter { !seen.contains($0["date"] as? Double ?? -1) })
                .sorted { ($0["date"] as? Double ?? 0) < ($1["date"] as? Double ?? 0) }
        case "sm.sessions.v1":                         // my sessions: this phone's, plus any only the cloud has
            guard let l = local as? [[String: Any]], let r = remote as? [[String: Any]] else { return local }
            let ids = Set(l.compactMap { $0["id"] as? String })
            return l + r.filter { !ids.contains($0["id"] as? String ?? "") }
        default:
            return local
        }
    }

    // MARK: push (going to the background, only when something changed)

    func push(_ store: AppStore) async {
        guard api.hasAccount, store.onboarded, !busy, !store.isDemo else { return }
        if !ud.bool(forKey: checkedKey) {
            await pull(store)                           // never overwrite a backup this phone hasn't seen
            guard ud.bool(forKey: checkedKey) else { return }
        }
        let snap = snapshot()
        guard let body = try? JSONSerialization.data(withJSONObject: snap, options: [.sortedKeys]),
              body.count < 280_000, let uid = try? await api.userId() else { return }
        let sig = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
        let pic = Self.photo(store.avatar)
        let picSig = pic.map { "\($0.count)-\($0.stableSeed)" } ?? "none"
        let dataChanged = ud.string(forKey: sentKey) != sig, picChanged = ud.string(forKey: picKey) != picSig
        guard dataChanged || picChanged else { return }

        var row: [String: Any] = ["user_id": uid, "data": snap, "updated_at": Post.isoPlain.string(from: Date())]
        if picChanged { row["photo"] = pic ?? NSNull() }
        // finish the upload even if the player swipes the app away
        let bg = UIApplication.shared.beginBackgroundTask(withName: "backup")
        defer { UIApplication.shared.endBackgroundTask(bg) }
        do {
            try await api.send("POST", "backups?on_conflict=user_id", row, prefer: "resolution=merge-duplicates,return=minimal")
            ud.set(sig, forKey: sentKey)
            if picChanged { ud.set(picSig, forKey: picKey) }
        } catch {}                                       // offline: the next background tries again
    }

    private func snapshot() -> [String: Any] {
        var data: [String: Any] = [:], plain: [String: Any] = [:]
        for k in dataKeys {
            if let d = ud.data(forKey: k), let j = try? JSONSerialization.jsonObject(with: d, options: .fragmentsAllowed) { data[k] = j }
        }
        for k in plainKeys {
            if let v = ud.object(forKey: k), v is String || v is NSNumber { plain[k] = v }
        }
        return ["v": 1, "data": data, "plain": plain]
    }

    /// 240 px square JPEG, base64 (~15 KB) ? the whole backed-up picture.
    static func photo(_ img: UIImage?) -> String? {
        guard let img else { return nil }
        let side = min(img.size.width, img.size.height), out: CGFloat = 240
        let f = UIGraphicsImageRendererFormat(); f.scale = 1
        let square = UIGraphicsImageRenderer(size: CGSize(width: out, height: out), format: f).image { _ in
            let k = out / side
            img.draw(in: CGRect(x: -(img.size.width - side) / 2 * k, y: -(img.size.height - side) / 2 * k,
                                width: img.size.width * k, height: img.size.height * k))
        }
        for q in [0.72, 0.5, 0.3] {
            if let s = square.jpegData(compressionQuality: q)?.base64EncodedString(), s.count < 39_000 { return s }
        }
        return nil
    }
}
