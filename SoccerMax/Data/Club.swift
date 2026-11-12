// Your club (Profile tab). v1 (2026-10-24) searched Apple Maps ? the user: it was "pulling completely irrelevant things
// and calling them soccer teams". v2 (2026-10-25): the list comes from Hat Trick Local, an open directory of US youth
// soccer clubs (https://hattricklocal.com/developers ? no key, any origin, CC BY 4.0, 60 calls/min per phone; 1,757
// clubs on 2026-10-25, deepest in Ohio and Pennsylvania). Every row is a real club. Typing = club name or town; a typo ?
// "Did you mean" from its MCP (/mcp search_clubs candidates, the REST API has none). Missing club ? "Add it as my club".
// 2026-10-26: the auto "Near you" list (location) was removed on request ? search only, no location permission.
import SwiftUI

struct Club: Codable, Hashable, Identifiable {
    var name: String
    var town: String?
    var lat: Double?
    var lon: Double?
    /// Hat Trick Local org_key (nil = typed by the player, or saved by the old Apple Maps picker).
    var key: String? = nil
    var state: String? = nil

    var id: String { key ?? (name.lowercased() + "|" + (town ?? "")) }

    /// "Pittsburgh, PA"
    var place: String { [town, state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ") }

    /// "Lonestar Soccer Club" ? "LSC". Up to three letters for the crest.
    var initials: String {
        let skip: Set<String> = ["the", "of", "and", "de", "la", "el", "&"]
        let words = name.split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { !skip.contains($0.lowercased()) }
        let s = words.prefix(3).compactMap(\.first).map { String($0).uppercased() }.joined()
        return s.isEmpty ? "FC" : s
    }
}

/// One search result.
struct ClubHit: Identifiable, Hashable, Sendable {
    let club: Club
    var id: String { club.id }
    var detail: String { club.place }
}

extension Club: Sendable {}

@MainActor
@Observable
final class ClubFinder {
    var results: [ClubHit] = []
    /// true = nothing matched every word; `results` are similar names.
    var suggested = false
    var searching = false
    var failed = false

    /// A club name or a town: "riverhounds", "boise", "FC Pittsburgh".
    func search(_ text: String) async {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard t.count >= 2 else { results = []; suggested = false; searching = false; return }
        searching = true
        var hits = await HatTrickLocal.clubs(["q": t, "limit": "40"])
        var fuzzy = false
        if hits?.isEmpty == true, let c = await HatTrickLocal.candidates(t), !c.isEmpty { hits = c; fuzzy = true }
        guard !Task.isCancelled else { return }
        failed = hits == nil
        results = hits ?? []
        suggested = fuzzy
        searching = false
    }
}

/// The Hat Trick Local club directory: REST for lists, its MCP for "did you mean".
enum HatTrickLocal {
    static let credit = "Club list: Hat Trick Local (hattricklocal.com), CC BY 4.0"
    private static let api = "https://api.hattricklocal.com/api/public/v1/clubs"
    private static let mcp = URL(string: "https://hattricklocal.com/mcp")!

    private struct Row: Decodable {
        let org_key: String
        let name: String
        let city: String?
        let state: String?
        let latitude: Double?
        let longitude: Double?
    }
    private struct Page: Decodable { let data: [Row] }

    /// nil = the network failed (not the same as "no clubs").
    static func clubs(_ params: [String: String]) async -> [ClubHit]? {
        var c = URLComponents(string: api)!
        c.queryItems = (params.merging(["sport": "soccer"]) { a, _ in a }).sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = c.url, let (data, res) = try? await URLSession.shared.data(from: url),
              (res as? HTTPURLResponse)?.statusCode == 200,
              let list = try? JSONDecoder().decode(Page.self, from: data) else { return nil }
        return list.data.map(hit)
    }

    /// Similar names when nothing matched every word ("pittsbrgh indepndence" ? Pittsburgh Independence FC).
    static func candidates(_ q: String) async -> [ClubHit]? {
        struct Resp: Decodable { struct R: Decodable { struct S: Decodable { let candidates: [Row]? }; let structuredContent: S? }; let result: R? }
        let body: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "tools/call",
                                   "params": ["name": "search_clubs", "arguments": ["query": q, "limit": 10]]]
        var r = URLRequest(url: mcp)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        r.setValue("2025-03-26", forHTTPHeaderField: "MCP-Protocol-Version")
        r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, _) = try? await URLSession.shared.data(for: r),
              let resp = try? JSONDecoder().decode(Resp.self, from: data) else { return nil }
        return (resp.result?.structuredContent?.candidates ?? []).map(hit)
    }

    private static func hit(_ r: Row) -> ClubHit {
        ClubHit(club: Club(name: r.name, town: r.city, lat: r.latitude, lon: r.longitude, key: r.org_key, state: r.state))
    }
}

// MARK: - the crest: a tiny FC shield in a colour picked from the club's name

struct ClubCrest: View {
    let club: Club?
    var size: CGFloat = 40

    private static let looks: [(Color, Color, Color)] = [
        (C.brand, C.brandInk, .white), (C.gold, C.goldInk, C.goldInk), (C.creme, Color(hex: 0x3C362B), C.brandMid),
        (Color(hex: 0x515869), C.charInk, C.creme), (C.char700, C.charInk, C.brand),
    ]

    var body: some View {
        let seed = (club?.name ?? "").unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        let look = Self.looks[club == nil ? 4 : seed % Self.looks.count]
        ZStack {
            Shield().fill(look.0)
            Shield().stroke(look.1, lineWidth: max(1.5, size * 0.06))
            if let club {
                Text(club.initials)
                    .font(F.display(size * (club.initials.count > 2 ? 0.3 : 0.38)))
                    .foregroundStyle(look.2)
                    .offset(y: -size * 0.04)
            } else {
                Image(systemName: "plus").font(.system(size: size * 0.36, weight: .heavy)).foregroundStyle(C.brand)
            }
        }
        .frame(width: size * 300 / 420, height: size)
        .accessibilityHidden(true)
    }
}
