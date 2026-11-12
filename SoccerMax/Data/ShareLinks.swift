// SHARE LINKS (2026-10-29, user: "turn every single sharing image into a link? every sharing thing should use the
// clickable image thing"). Every share out of the app is a soccermax.app link with a picture card: the app draws the
// card (1200×630), uploads it once (site/worker.js, POST /api/share), and shares the URL ? Messages, WhatsApp,
// Instagram? show it as a big tappable picture. The page opens the app (universal link / soccermax://) or sends people
// to the App Store; invites go to soccermax.app/join/<code> and the code is pasted on the first screen (notes/19).
import PostHog
import SwiftUI
import UIKit

enum ShareLinks {
    static let site = "https://soccermax.app"
    private static let key = "sm-share-1"
    @MainActor private static var made: [String: URL] = [:]
    /// What each made link is (gift · invite · session · film), so the Share sheet can report it.
    @MainActor private static var kinds: [URL: String] = [:]

    struct Card {
        var kind: String            // gift · invite · session · film
        var title: String
        var sub: String
        var code: String? = nil
        var open: String? = nil     // soccermax:// link the app follows when the page is opened in it
        var data: [String: Any]? = nil
    }

    /// Draw the card, upload it, return its link. Offline / server trouble ? `fallback` (still a real page).
    @MainActor static func link<V: View>(_ c: Card, art: V, fallback: URL) async -> URL {
        let memo = [c.kind, c.title, c.sub, c.code ?? "", "\(c.data?.description.hashValue ?? 0)"].joined(separator: "|")
        if let u = made[memo] { return u }
        let r = ImageRenderer(content: art.frame(width: 1200, height: 630))
        r.scale = 1
        guard let img = r.uiImage, let jpg = img.jpegData(compressionQuality: 0.78) else { return fallback }
        var body: [String: Any] = ["kind": c.kind, "title": c.title, "sub": c.sub, "img": jpg.base64EncodedString()]
        if let v = c.code { body["code"] = v }
        if let v = c.open { body["open"] = v }
        if let v = c.data { body["data"] = v }
        var req = URLRequest(url: URL(string: "\(site)/api/share")!, timeoutInterval: 12)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "X-SM-Key")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (d, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200,
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let s = o["url"] as? String,
              let u = URL(string: s) else { return fallback }
        made[memo] = u
        kinds[u] = c.kind
        return u
    }

    /// The system Share sheet with just the link (that's what makes the picture card), over whatever is on screen.
    @MainActor static func present(_ url: URL) {
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        // Analytics (notes/38): which thing was shared and which app it went to.
        let kind = kinds[url] ?? (url.path.hasPrefix("/join/") ? "invite" : "other")
        PostHogSDK.shared.capture("share_opened", properties: ["kind": kind])
        vc.completionWithItemsHandler = { type, done, _, _ in
            if done {
                PostHogSDK.shared.capture("share_completed", properties: [
                    "kind": kind, "destination": destination(type), "destination_id": type?.rawValue ?? "unknown",
                ])
            } else {
                PostHogSDK.shared.capture("share_cancelled", properties: ["kind": kind])
            }
        }
        guard var top = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first?.rootViewController else { return }
        while let p = top.presentedViewController, !p.isBeingDismissed { top = p }
        vc.popoverPresentationController?.sourceView = top.view
        top.present(vc, animated: true)
    }

    /// Share-sheet activity ? a plain app name for the dashboard.
    static func destination(_ t: UIActivity.ActivityType?) -> String {
        guard let id = t?.rawValue else { return "Unknown" }
        let known: [(String, String)] = [
            ("activity.Message", "Messages"), ("activity.Mail", "Mail"), ("AirDrop", "AirDrop"),
            ("CopyToPasteboard", "Copy link"), ("whatsapp", "WhatsApp"), ("instagram", "Instagram"),
            ("musically", "TikTok"), ("tiktok", "TikTok"), ("picaboo", "Snapchat"), ("snapchat", "Snapchat"),
            ("Messenger", "Messenger"), ("facebook.Facebook", "Facebook"), ("Tweetie", "X"), ("twitter", "X"),
            ("discord", "Discord"), ("telegra", "Telegram"), ("reddit", "Reddit"), ("youtube", "YouTube"),
            ("PostToFacebook", "Facebook"), ("SaveToFiles", "Files"), ("Notes", "Notes"), ("Reminders", "Reminders"),
        ]
        return known.first { id.localizedCaseInsensitiveContains($0.0) }?.1 ?? id
    }

    static func invite(_ code: String) -> URL { URL(string: "\(site)/join/\(code)")! }

    // MARK: opening a link in the app

    struct Shared: Decodable {
        let kind: String
        let title: String?
        let open: String?
        let data: PostMeta?
    }

    /// soccermax://s/<id> or https://soccermax.app/s/<id>
    static func id(from url: URL) -> String? {
        let parts = ([url.scheme == "soccermax" ? url.host ?? "" : ""] + url.pathComponents).filter { $0 != "/" && !$0.isEmpty }
        guard url.scheme == "soccermax" || url.host?.hasSuffix("soccermax.app") == true,
              parts.first == "s", let id = parts[safe: 1], id.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        return id
    }

    static func fetch(_ id: String) async -> Shared? {
        guard let u = URL(string: "\(site)/api/share/\(id)"),
              let (d, r) = try? await URLSession.shared.data(from: u), (r as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(Shared.self, from: d)
    }
}

/// A share button that makes the link first (a spinner for the second it takes), then opens the Share sheet.
struct LinkShareButton<Label: View>: View {
    let make: @MainActor () async -> URL
    @ViewBuilder var label: Label
    @State private var busy = false
    var body: some View {
        Button {
            guard !busy else { return }
            busy = true
            Haptics.play(.press)
            Task { let u = await make(); busy = false; ShareLinks.present(u) }
        } label: {
            if busy { ProgressView().tint(C.creme) } else { label }
        }
    }
}

// MARK: - the picture cards (1200×630, the size every app's link preview uses)

struct ShareCardArt<Visual: View>: View {
    let eyebrow: String
    let title: String
    let sub: String
    var code: String? = nil
    @ViewBuilder var visual: Visual

    var body: some View {
        HStack(spacing: 60) {
            visual.frame(width: 440, height: 440)
            VStack(alignment: .leading, spacing: 14) {
                Text(eyebrow.uppercased()).font(F.round(30, .bold)).foregroundStyle(C.brand).kerning(2)
                Text(title.uppercased()).font(F.display(code == nil ? 80 : 68)).foregroundStyle(C.creme)
                    .lineLimit(2).minimumScaleFactor(0.5)
                Text(sub).font(F.round(34, .semibold)).foregroundStyle(C.creme2).lineLimit(2).minimumScaleFactor(0.7)
                if let code {
                    HStack(spacing: 10) {
                        ForEach(Array(code.enumerated()), id: \.offset) { _, ch in
                            Text(String(ch)).font(.system(size: 50, weight: .heavy, design: .monospaced)).foregroundStyle(C.creme)
                                .frame(width: 66, height: 84)
                                .background(RoundedRectangle(cornerRadius: 16).fill(C.brand.opacity(0.22))
                                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(C.brand, lineWidth: 3)))
                        }
                    }
                    .padding(.top, 6)
                }
                Spacer(minLength: 0)
                HStack(spacing: 12) {
                    Image(systemName: "soccerball").font(.system(size: 34, weight: .bold)).foregroundStyle(C.brand)
                    Text("SOCCER LAB").font(F.display(40)).foregroundStyle(C.creme)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.vertical, 20)
        }
        .padding(.horizontal, 70).padding(.vertical, 75)
        .frame(width: 1200, height: 630)
        .background(
            ZStack {
                C.char900
                RadialGradient(colors: [C.brand.opacity(0.28), .clear], center: UnitPoint(x: 0.22, y: 0.5), startRadius: 0, endRadius: 520)
            }
        )
    }
}

/// The card + link for each thing a player shares.
@MainActor
enum ShareCards {
    /// A free week for a friend: your gift code on a card ? soccermax.app/join/<code> (the same code box as teams).
    static func gift(_ store: AppStore) async -> URL {
        guard let code = await Team.shared.myGiftCode() else { return URL(string: ShareLinks.site)! }
        let first = store.answers.firstName
        let art = ShareCardArt(eyebrow: first.isEmpty ? "A free week for you" : "A free week from \(first)", title: "7 days free",
                               sub: "No card · train like the pros", code: code) {
            RoundedRectangle(cornerRadius: 56, style: .continuous).fill(C.brand)
                .overlay(Image(systemName: "gift.fill").font(.system(size: 230, weight: .bold)).foregroundStyle(C.brandInk))
                .overlay(RoundedRectangle(cornerRadius: 56, style: .continuous).stroke(C.charInk, lineWidth: 8))
        }
        let c = ShareLinks.Card(kind: "gift", title: first.isEmpty ? "A friend" : first, sub: "7 days free, no card", code: code)
        return await ShareLinks.link(c, art: art, fallback: ShareLinks.invite(code))
    }

    static func invite(_ t: TeamRow) async -> URL {
        let art = ShareCardArt(eyebrow: "Join my team", title: t.name, sub: "7 days free · no card", code: t.code) {
            TeamCrest(name: t.name, logo: t.logo, color: t.color, size: 380)
        }
        let c = ShareLinks.Card(kind: "invite", title: t.name, sub: "7 days free, no card", code: t.code)
        return await ShareLinks.link(c, art: art, fallback: ShareLinks.invite(t.code))
    }

    static func item(_ item: Shareable) async -> URL {
        let fallback = URL(string: ShareLinks.site)!
        switch item {
        case .session, .pro:
            let p = item.post()
            var photo: UIImage?
            if case .pro(let pro, _) = item { photo = pro.image(tile: true) }
            let art = ShareCardArt(eyebrow: "Try my session", title: item.title, sub: item.subtitle) {
                if let photo {
                    Image(uiImage: photo).resizable().scaledToFill().frame(width: 440, height: 440)
                        .clipShape(RoundedRectangle(cornerRadius: 48, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 48, style: .continuous).stroke(C.brand, lineWidth: 5))
                } else {
                    RoundedRectangle(cornerRadius: 48, style: .continuous).fill(C.brandLip)
                        .overlay(Image(systemName: "figure.soccer").font(.system(size: 230, weight: .bold)).foregroundStyle(C.brandHi))
                }
            }
            var data: [String: Any] = ["title": item.title, "items": p.meta.items ?? []]
            if let m = p.meta.minutes { data["minutes"] = m }
            if let pro = p.meta.pro { data["pro"] = pro }
            let c = ShareLinks.Card(kind: "session", title: item.title, sub: item.subtitle, data: data)
            return await ShareLinks.link(c, art: art, fallback: fallback)
        case .film(let t):
            async let h = RemoteImages.load(t.home.logo)
            async let a = RemoteImages.load(t.away.logo)
            let (hi, ai) = await (h, a)
            let title = "\(t.home.name) v \(t.away.name)"
            let art = ShareCardArt(eyebrow: "Watch it in 3D", title: title, sub: "\(t.fx.league.name) · Matchday film") {
                VStack(spacing: 18) {
                    crest(hi)
                    Text("V").font(F.display(54)).foregroundStyle(C.muted)
                    crest(ai)
                }
            }
            let c = ShareLinks.Card(kind: "film", title: title, sub: "\(t.fx.league.name) · broken down in 3D", open: "soccermax://match/\(t.id)")
            return await ShareLinks.link(c, art: art, fallback: fallback)
        }
    }

    @ViewBuilder private static func crest(_ img: UIImage?) -> some View {
        if let img { Image(uiImage: img).resizable().scaledToFit().frame(width: 150, height: 150) }
        else { Circle().fill(C.char700).frame(width: 150, height: 150) }
    }
}
