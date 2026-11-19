// LOCAL TEAMS + JOIN REQUESTS + CONTACTS (2026-11-08, notes/26 top). User: "Location should be for finding local teams,
// allow the option for teams to select a location when being created or after being created so local players can see
// them and request to join. Only the creator of the group should be able to alter these settings and accept requests."
// Server: supabase/2026-11-08-local-teams.sql (teams.place/lat/lng rounded to ~1 km + join_requests, owner-only RPCs).
// Until that SQL is on the server every call here fails quietly and `ready` stays false ? the app shows nothing new.
// Contacts never leave the phone: they're only listed so you can text a friend your team's invite link.
import CoreLocation
import Observation
import UIKit

struct NearbyTeam: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let logo: String?
    let color: Int
    let place: String?
    let members: Int
    let km: Double
    var requested: Bool
}

struct JoinRequest: Decodable, Identifiable, Equatable {
    let user_id: String
    let name: String
    let position: String?
    let level: Int?
    var id: String { user_id }
}

@Observable
@MainActor
final class LocalTeams {
    static let shared = LocalTeams()

    struct Place: Decodable, Equatable { let id: String; let place: String?; let lat: Double?; let lng: Double? }

    /// The server has the local-teams SQL (the last call worked).
    private(set) var ready = false
    /// Where each of my teams plays (only teams that set one).
    private(set) var places: [String: Place] = [:]
    private(set) var nearby: [NearbyTeam] = []
    /// Open requests per team I own.
    private(set) var requests: [String: [JoinRequest]] = [:]
    var error: String?

    private var api: SupabaseREST { Team.shared.api }
    private var signedIn: Bool { Team.shared.signedIn && api.hasAccount }

    // MARK: my teams

    func refreshMine() async {
        guard signedIn else { return }
        // does the server have the local-teams SQL yet? (an owner-only call on a made-up team just returns [])
        if !ready, let _: [JoinRequest] = try? await api.rpc("team_requests", ["p_team": "00000000-0000-0000-0000-000000000000"]) {
            ready = true
        }
        guard ready, !Team.shared.teams.isEmpty else { return }
        let ids = Team.shared.teams.map(\.id).joined(separator: ",")
        if let rows: [Place] = try? await api.get("teams?select=id,place,lat,lng&id=in.(\(ids))") {
            ready = true
            places = Dictionary(uniqueKeysWithValues: rows.filter { $0.lat != nil }.map { ($0.id, $0) })
        }
        for t in Team.shared.teams where t.owner == Team.shared.me { await loadRequests(t.id) }
    }

    /// Owner only (the server checks too). nil place/coords = hide the team from nearby players.
    @discardableResult
    func setLocation(team: String, place: String?, at spot: CLLocationCoordinate2D?) async -> Bool {
        do {
            let _: EmptyReply = try await api.rpc("set_team_location", [
                "p_team": team, "p_place": place ?? NSNull(),
                "p_lat": spot?.latitude ?? NSNull(), "p_lng": spot?.longitude ?? NSNull(),
            ])
            ready = true
            await refreshMine()
            if spot == nil { places[team] = nil }
            return true
        } catch { self.error = Team.say(error); return false }
    }

    // MARK: finding a team

    func findNearby() async {
        guard signedIn, let here = Locator.shared.coordinate else { return }
        if let rows: [NearbyTeam] = try? await api.rpc("nearby_teams", ["p_lat": here.latitude, "p_lng": here.longitude, "p_km": 30]) {
            ready = true
            nearby = rows
        }
    }

    func ask(_ t: NearbyTeam) async {
        let on = !t.requested
        do {
            let _: EmptyReply = try await api.rpc(on ? "request_join" : "cancel_request", ["p_team": t.id])
            if let i = nearby.firstIndex(where: { $0.id == t.id }) { nearby[i].requested = on }
            if on { Haptics.play(.goal) }
        } catch { self.error = Team.say(error) }
    }

    // MARK: answering (owner)

    func loadRequests(_ team: String) async {
        if let rows: [JoinRequest] = try? await api.rpc("team_requests", ["p_team": team]) {
            ready = true
            requests[team] = rows
        }
    }

    func answer(_ r: JoinRequest, team: String, accept: Bool, store: AppStore) async {
        do {
            let _: EmptyReply = try await api.rpc("answer_request", ["p_team": team, "p_user": r.user_id, "p_accept": accept])
            requests[team]?.removeAll { $0.user_id == r.user_id }
            if accept { Haptics.play(.goal); await Team.shared.refresh(store) }
        } catch { self.error = Team.say(error) }
    }
}

// MARK: - location (one fix + the town name)

/// Where the player is right now, for local teams. Uses the Map tab's location manager (same "while using" permission).
@MainActor
enum Locator {
    static let shared = Probe()

    @Observable
    @MainActor
    final class Probe {
        var spot: SessionSpot { SessionSpot.shared }
        var allowed: Bool { spot.allowed }
        var denied: Bool { spot.status == .denied || spot.status == .restricted }
        var asked: Bool { spot.status != .notDetermined }
        var coordinate: CLLocationCoordinate2D? { spot.here.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) } }
        /// Shows the system prompt the first time; after that just takes a fix.
        func ask() { spot.refresh() }

        /// "Hackney, London" ? the town for a team's place, from the current fix.
        func townName() async -> String? {
            guard let c = coordinate else { return nil }
            let marks = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: c.latitude, longitude: c.longitude))
            guard let m = marks?.first else { return nil }
            return [m.subLocality ?? m.locality, m.locality == m.subLocality ? nil : m.locality].compactMap { $0 }.prefix(2).joined(separator: ", ")
        }
    }
}

// MARK: - contacts (stay on the phone)

@Observable
@MainActor
final class FriendsBook {
    static let shared = FriendsBook()

    struct Friend: Identifiable, Hashable { let id: String; let name: String; let phone: String }

    // Soccer Lab 2.0 (2026-11-19): the app never reads contacts (teams are off), so the Contacts framework is gone
    // from the build. Apple requires a contacts purpose string for any app that links it (ITMS-90683).
    private(set) var friends: [Friend] = []
    var skipped: Bool {
        get { UserDefaults.standard.bool(forKey: "sm.contacts.skipped") }
        set { UserDefaults.standard.set(newValue, forKey: "sm.contacts.skipped") }
    }
    var cardClosed: Bool {
        get { UserDefaults.standard.bool(forKey: "sm.contacts.card.closed") }
        set { UserDefaults.standard.set(newValue, forKey: "sm.contacts.card.closed") }
    }
    var allowed: Bool { false }
    var denied: Bool { false }
    var undecided: Bool { false }
    func recheck() {}
    func ask() async {}
    func load() async {}

    /// The text a friend gets: your team's invite link, or the app if you're not on a team yet.
    func inviteText(team: TeamRow?) -> String {
        if let t = team { return "Come train with \(t.name) on Soccer Lab! Tap to join: \(ShareLinks.invite(t.code).absoluteString)" }
        return "Train with me on Soccer Lab! \(ShareLinks.site)"
    }
}
