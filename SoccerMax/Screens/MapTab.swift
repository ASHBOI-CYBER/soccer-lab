// MAP TAB (2026-11-08): "add one more tab, 'map' using apple maps ? create a dot where a session was played. The
// darker the dot, the longer the session. Then when clicked on it should show the user (ability to go to profile),
// their session duration, and what they did for their session."
//
// Apple Maps (muted, light so the green dots read) filling the screen, a floating MAP title + a SHORT ? LONG legend.
// Dots = my sessions (on this phone) + my teammates' sessions (team feed posts with a spot). Spots are rounded to
// ~100 m (SessionSpot.swift); sessions at the same spot fan out a little so each can be tapped.
// Tap a dot ? a sheet: who (? their profile), how long, when, what they did, and any others at that spot.
import CoreLocation
import MapKit
import SwiftUI

/// One session on the map.
struct MapDot: Identifiable, Hashable {
    let id: String
    let user: String
    let name: String
    let isMe: Bool
    let date: Date
    let minutes: Int
    let title: String
    let area: String?
    /// (drill name, dose) ? what they did.
    let drills: [Pair]
    let media: [String]
    let lat: Double
    let lng: Double

    struct Pair: Hashable { let name: String; let dose: String }

    /// Same rounded spot = same place.
    var spotKey: String { "\(lat),\(lng)" }

    /// Where the dot is drawn: the spot, nudged a few metres by the id so stacked sessions don't hide each other.
    var coordinate: CLLocationCoordinate2D {
        let h = id.stableSeed
        let a = Double(h % 360) * .pi / 180, r = 0.00008 + Double(h / 360 % 100) / 100 * 0.00018
        return CLLocationCoordinate2D(latitude: lat + r * sin(a), longitude: lng + r * cos(a) / max(0.2, cos(lat * .pi / 180)))
    }

    /// 0 = a few minutes, 1 = 90+ minutes.
    var depth: Double { min(1, max(0, (Double(minutes) - 5) / 85)).squareRoot() }
    /// Light mint for a short session ? deep pitch green for a long one.
    var color: Color { Self.shade(depth) }

    static func shade(_ t: Double) -> Color {
        let a = (0.74, 0.95, 0.80), b = (0.03, 0.27, 0.12)
        return Color(red: a.0 + (b.0 - a.0) * t, green: a.1 + (b.1 - a.1) * t, blue: a.2 + (b.2 - a.2) * t)
    }
}

extension MapDot {
    @MainActor static func all(store: AppStore, team: Team) -> [MapDot] {
        let me = team.me
        let myName = store.answers.firstName
        let showMine = SessionSpot.shared.onMap
        var out: [MapDot] = store.completions.compactMap { c in
            guard showMine, let lat = c.lat, let lng = c.lng else { return nil }
            let a = TrainingArea.of(c.area)
            return MapDot(id: "c\(c.date.timeIntervalSince1970)", user: me ?? "me", name: myName, isMe: true, date: c.date,
                          minutes: c.minutes, title: a?.name ?? c.name, area: c.area,
                          drills: (c.drills ?? []).map { Pair(name: $0.name, dose: $0.dose) }, media: c.media ?? [],
                          lat: lat, lng: lng)
        }
        let mine = out
        for p in team.mapPosts {
            guard let m = p.meta, let lat = m.lat, let lng = m.lng else { continue }
            let isMe = p.user_id == me
            if isMe && !showMine { continue }
            // my own posts are already here from the phone (unless this is a fresh install)
            if isMe, mine.contains(where: { abs($0.date.timeIntervalSince(p.date)) < 600 && $0.minutes == (m.minutes ?? 0) }) { continue }
            let drills = (m.items ?? []).compactMap { i -> Pair? in
                guard let id = i.first else { return nil }
                let sets = i.count > 1 ? i[1] : "1"
                return Pair(name: Library.shared.drill(id).name, dose: "\(sets) set\(sets == "1" ? "" : "s")")
            }
            out.append(MapDot(id: "p\(p.id)", user: p.user_id, name: isMe ? myName : (team.member(p.user_id)?.name ?? "Teammate"),
                              isMe: isMe, date: p.date, minutes: m.minutes ?? 0,
                              title: TrainingArea.of(m.area)?.name ?? m.title ?? "Session", area: m.area,
                              drills: drills, media: [], lat: lat, lng: lng))
        }
        // light first, so the long (dark) sessions sit on top
        return out.sorted { $0.minutes < $1.minutes }
    }
}

/// Who's on the map (2026-11-08 v2): everyone, me, one of my teams, or one player (from the strip).
enum MapFilter: Hashable { case everyone, me, team(String), player(String) }

/// A team that set where it plays (rounded to ~1 km on the server, `set_team_location`). `map_teams` RPC.
struct TeamPin: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let color: Int
    let place: String?
    let members: Int
    let lat: Double
    let lng: Double
    let mine: Bool
    var requested: Bool
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
}

/// Team pins near me + every located team I'm on. Fails quietly (no pins) if the server has no team places yet.
@Observable
@MainActor
final class MapTeams {
    static let shared = MapTeams()
    private(set) var pins: [TeamPin] = []

    func load(near c: CLLocationCoordinate2D?) async {
        if DebugRoute.parts.contains("demo") { pins = Self.demo; return }
        let team = Team.shared
        guard team.signedIn, team.api.hasAccount else { return }
        let at = c ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        if let rows: [TeamPin] = try? await team.api.rpc("map_teams", ["p_lat": at.latitude, "p_lng": at.longitude, "p_km": 50]) {
            pins = rows
        }
    }

    /// ASK TO JOIN / cancel, same server calls as TEAMS NEAR YOU.
    func ask(_ p: TeamPin) async {
        let on = !p.requested
        if DebugRoute.parts.contains("demo") { set(p.id, on); return }
        do {
            let _: EmptyReply = try await Team.shared.api.rpc(on ? "request_join" : "cancel_request", ["p_team": p.id])
            set(p.id, on)
        } catch {}
    }
    private func set(_ id: String, _ on: Bool) { if let i = pins.firstIndex(where: { $0.id == id }) { pins[i].requested = on } }

    private static let demo = [
        TeamPin(id: "demo", name: "Hackney Hawks", color: 0, place: "Hackney Downs", members: 6, lat: 51.55, lng: -0.06, mine: true, requested: false),
        TeamPin(id: "x1", name: "Clapton Lions", color: 3, place: "Millfields Park", members: 11, lat: 51.56, lng: -0.05, mine: false, requested: false),
    ]
}

struct MapTab: View {
    @Environment(AppStore.self) private var store
    @State private var team = Team.shared
    @State private var spot = SessionSpot.shared
    @State private var teams = MapTeams.shared
    @State private var camera: MapCameraPosition = .automatic
    @State private var picked: MapDot?
    @State private var pin: TeamPin?
    @State private var filter: MapFilter = .everyone
    /// The camera jumped to me once already (auto-zoom on open).
    @State private var homed = false
    /// The team the player strip is showing (picked from the filter menu; stays while one of its players is picked).
    @State private var scopeTeam: String?

    var body: some View {
        let all = MapDot.all(store: store, team: team)
        let dots = shown(all)
        ZStack(alignment: .top) {
            Map(position: $camera) {
                if spot.allowed { UserAnnotation() }
                ForEach(teams.pins) { p in
                    Annotation(p.name, coordinate: p.coordinate, anchor: .bottom) {
                        Button { Haptics.play(.press); pin = p } label: { TeamPinMark(pin: p) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Team \(p.name)")
                    }
                    .annotationTitles(.hidden)
                }
                ForEach(dots) { d in
                    Annotation(d.title, coordinate: d.coordinate, anchor: .center) {
                        Button { Haptics.play(.press); picked = d } label: { DotMark(dot: d, on: picked?.id == d.id) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(d.isMe ? "You" : d.name), \(d.title), \(d.minutes) minutes")
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .including([.park, .stadium, .school])))
            .mapControls { MapCompass(); MapScaleView() }
            .environment(\.colorScheme, .light)
            .ignoresSafeArea(edges: .top)

            // a soft dark scrim so the status bar reads on the light map
            LinearGradient(colors: [C.char900.opacity(0.75), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 120).ignoresSafeArea(edges: .top).allowsHitTesting(false)

            // the legend sits up top, so Apple's Maps mark + Legal link stay clear at the bottom
            VStack(spacing: 8) {
                header
                legend
                players(all)
                Spacer()
            }
            .padding(.horizontal, 16)
        }
        .background(C.char900)
        .onAppear {
            spot.refresh()
            goHome(animated: false)
            Task {
                await team.pullSpots()
                await teams.load(near: here)
            }
        }
        // auto-zoom to me the first time my spot is known
        .onChange(of: spot.here) { _, _ in
            if !homed { goHome(animated: true) }
            Task { await teams.load(near: here) }
        }
        .onChange(of: filter) { _, f in
            switch f {
            case .team(let id): scopeTeam = id
            case .player: break
            default: scopeTeam = nil
            }
            if case .everyone = f { goHome(animated: true) } else { fit(shown(all)) }
        }
        .sheet(item: $picked) { d in
            SpotSheet(dot: d, here: dots.filter { $0.spotKey == d.spotKey && $0.id != d.id }.sorted { $0.date > $1.date },
                      pick: { picked = $0 })
                .environment(store)
        }
        .sheet(item: $pin) { p in
            TeamPinSheet(pin: p, show: { filter = .team(p.id) })
        }
    }

    private var here: CLLocationCoordinate2D? { spot.here.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) } }

    private func shown(_ all: [MapDot]) -> [MapDot] {
        switch filter {
        case .everyone: return all
        case .me: return all.filter(\.isMe)
        case .team(let id):
            let ids = Set(team.members(of: id).map(\.id))
            return all.filter { ids.contains($0.user) || ($0.isMe && ids.contains(team.me ?? "")) }
        case .player(let id): return all.filter { $0.user == id }
        }
    }

    // MARK: camera

    /// About 5 km around me ? close enough to see the parks, wide enough for the team's dots.
    private func goHome(animated: Bool) {
        guard let c = here else { return }
        homed = true
        let r = MKCoordinateRegion(center: c, latitudinalMeters: 5000, longitudinalMeters: 5000)
        if animated { withAnimation(.snappy) { camera = .region(r) } } else { camera = .region(r) }
    }

    /// Frame a set of dots (a player, a team, just me).
    private func fit(_ ds: [MapDot]) {
        guard !ds.isEmpty else { goHome(animated: true); return }
        let lats = ds.map(\.lat), lngs = ds.map(\.lng)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lngs.min()! + lngs.max()!) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max(0.012, (lats.max()! - lats.min()!) * 1.8),
                                    longitudeDelta: max(0.012, (lngs.max()! - lngs.min()!) * 1.8))
        withAnimation(.snappy) { camera = .region(MKCoordinateRegion(center: center, span: span)) }
    }

    // MARK: overlays

    private var filterName: String {
        switch filter {
        case .everyone: return "All sessions"
        case .me: return "Your sessions"
        case .team(let id): return team.team(id)?.name ?? "Team"
        case .player(let id):
            if id == team.me { return "Your sessions" }
            return "\(team.member(id)?.name.split(separator: " ").first.map(String.init) ?? "Their") sessions"
        }
    }
    private var filterIcon: String {
        switch filter {
        case .everyone: return "person.3.fill"
        case .me, .player: return "person.fill"
        case .team: return "shield.fill"
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Disp("MAP", size: 34)
            Spacer()
            Menu {
                Picker("Show", selection: $filter) {
                    Label("Everyone", systemImage: "person.3.fill").tag(MapFilter.everyone)
                    Label("Just me", systemImage: "person.fill").tag(MapFilter.me)
                }
                if !team.teams.isEmpty {
                    Section("Your teams") {
                        Picker("Teams", selection: $filter) {
                            ForEach(team.ordered) { t in
                                Label(t.name, systemImage: "shield.fill").tag(MapFilter.team(t.id))
                            }
                        }
                    }
                }
                Section {
                    Toggle(isOn: Binding(get: { spot.onMap }, set: { spot.onMap = $0 })) {
                        Label("My sessions on the map", systemImage: "mappin.and.ellipse")
                    }
                }
            } label: {
                Image(systemName: filterIcon)
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(C.creme)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark))
            }
            .accessibilityLabel("Who's on the map")
            Button {
                Haptics.play(.press)
                if spot.allowed { goHome(animated: true) } else { spot.refresh() }
            } label: {
                Image(systemName: "location.fill")
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(C.creme)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark))
            }
            .accessibilityLabel("Show where I am")
        }
        .padding(.leading, 18).padding(.trailing, 6).padding(.vertical, 6)
        .background(Capsule().fill(C.char900.opacity(0.92)))
        .padding(.top, 6)
    }

    /// SHORT ????? LONG ? the shade = how long the session was.
    private var legend: some View {
        HStack(spacing: 10) {
            Text("SHORT").font(F.round(12, .heavy)).kerning(1.2).foregroundStyle(C.muted)
            HStack(spacing: 6) {
                ForEach(0..<5) { i in
                    Circle().fill(MapDot.shade(Double(i) / 4)).frame(width: 14, height: 14)
                }
            }
            Text("LONG").font(F.round(12, .heavy)).kerning(1.2).foregroundStyle(C.muted)
            Spacer(minLength: 0)
            Text(filterName).font(F.round(13, .bold)).foregroundStyle(C.creme2).lineLimit(1)
        }
        .padding(.horizontal, 16).frame(height: 44)
        .background(Capsule().fill(C.char900.opacity(0.92)))
    }

    /// Everyone with dots (in the picked team, or all my teams), side by side. Tap = only their dots; tap again = back.
    @ViewBuilder private func players(_ all: [MapDot]) -> some View {
        // the strip lists the picked team's players (kept while one of them is picked), else everyone
        let scope: [MapDot] = {
            guard let id = scopeTeam else { return all }
            let ids = Set(team.members(of: id).map(\.id))
            return all.filter { ids.contains($0.user) }
        }()
        let people = Dictionary(grouping: scope, by: \.user).map { (id: $0.key, dots: $0.value) }
            .sorted { a, b in
                let am = a.dots.first?.isMe == true, bm = b.dots.first?.isMe == true
                if am != bm { return am }
                return a.dots.reduce(0) { $0 + $1.minutes } > b.dots.reduce(0) { $0 + $1.minutes }
            }
        if people.contains(where: { $0.dots.first?.isMe == false }) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(people, id: \.id) { p in
                        let d = p.dots[0]
                        let on = filter == .player(p.id)
                        Button {
                            Haptics.play(.press)
                            withAnimation(.snappy) { filter = on ? (scopeTeam.map { .team($0) } ?? .everyone) : .player(p.id) }
                        } label: {
                            HStack(spacing: 8) {
                                PlayerPic(id: p.id, name: d.name, size: 34)
                                    .overlay(Circle().stroke(on ? C.brand : .clear, lineWidth: 3).padding(-3))
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(d.isMe ? "You" : String(d.name.split(separator: " ").first ?? "")).font(F.round(14, .bold))
                                        .foregroundStyle(on ? C.brand : C.creme).lineLimit(1)
                                    Text("\(p.dots.count) · \(minText(Double(p.dots.reduce(0) { $0 + $1.minutes })))")
                                        .font(F.round(12, .semibold)).foregroundStyle(C.muted).lineLimit(1)
                                }
                            }
                            .padding(.leading, 6).padding(.trailing, 14).padding(.vertical, 6)
                            .background(Capsule().fill(C.char900.opacity(0.92)))
                        }
                        .buttonStyle(.press(.stud))
                        .accessibilityLabel("Show \(d.isMe ? "your" : d.name + "'s") sessions")
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -16)
        }
    }
}

/// A team's home on the map: a person-group badge (green = mine) with the name under it.
private struct TeamPinMark: View {
    let pin: TeamPin
    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Circle().fill(pin.mine ? C.brand : C.char900))
                .overlay(Circle().stroke(.white, lineWidth: 2.5))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1.5)
            Text(pin.name).font(F.round(11, .heavy)).foregroundStyle(C.creme).lineLimit(1)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(C.char900.opacity(0.9)))
        }
        .frame(maxWidth: 140)
    }
}

/// Tap a team pin: who they are + see their sessions (my team) or ASK TO JOIN (a team near me).
private struct TeamPinSheet: View {
    let pin: TeamPin
    let show: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var teams = MapTeams.shared
    @State private var busy = false

    var body: some View {
        let p = teams.pins.first { $0.id == pin.id } ?? pin
        VStack(spacing: 14) {
            TeamCrest(name: p.name, color: p.color, size: 72).padding(.top, 30)
            Disp(p.name.uppercased(), size: 26).multilineTextAlignment(.center)
            Text([p.place, "\(p.members) player\(p.members == 1 ? "" : "s")"].compactMap { $0 }.joined(separator: " · "))
                .font(F.round(15, .semibold)).foregroundStyle(C.muted)
            Spacer(minLength: 8)
            if p.mine {
                Button { dismiss(); show() } label: { cta("SEE THEIR SESSIONS", on: true) }.buttonStyle(.press(.kick))
            } else {
                Button {
                    busy = true
                    Task { await teams.ask(p); busy = false }
                } label: { cta(p.requested ? "REQUESTED · TAP TO CANCEL" : "ASK TO JOIN", on: !p.requested) }
                .buttonStyle(.press(.kick))
                .disabled(busy)
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 16)
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.visible)
        .presentationBackground(C.char900)
    }

    private func cta(_ t: String, on: Bool) -> some View {
        Text(t).font(F.round(16, .heavy)).kerning(0.6).foregroundStyle(on ? C.brandInk : C.creme)
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(Capsule().fill(on ? C.brand : C.char800))
    }
}

/// The dot: the session's shade with a white rim so it reads on any map; bigger when picked.
private struct DotMark: View {
    let dot: MapDot
    let on: Bool
    var body: some View {
        let s: CGFloat = 18 + 8 * dot.depth
        Circle()
            .fill(dot.color)
            .frame(width: s, height: s)
            .overlay(Circle().stroke(.white, lineWidth: dot.isMe ? 3.5 : 2.5))
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1.5)
            .scaleEffect(on ? 1.45 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: on)
            .frame(width: 44, height: 44)   // tap target
            .contentShape(Circle())
    }
}

// MARK: - the sheet

/// Who · how long · when · what they did. Same clean, borderless look as the Sessions tab.
private struct SpotSheet: View {
    let dot: MapDot
    let here: [MapDot]
    let pick: (MapDot) -> Void
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var team = Team.shared
    @State private var profile: MemberRow?
    @State private var viewing: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                who
                time
                what
                if !dot.media.filter(SessionMedia.exists).isEmpty { photos }
                if let a = TrainingArea.of(dot.area) { trainIt(a) }
                if !here.isEmpty { more }
            }
            .padding(.horizontal, 20)
            .padding(.top, 26)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(C.char900)
        .sheet(item: $profile) { PlayerSheet(member: $0).environment(store) }
        .fullScreenCover(item: Binding(get: { viewing.map(MediaName.init) }, set: { viewing = $0?.id })) { MediaViewer(name: $0.id) }
    }

    private var who: some View {
        HStack(spacing: 14) {
            PlayerPic(id: dot.user, name: dot.name, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(dot.isMe ? "You" : dot.name).font(F.round(20, .bold)).foregroundStyle(dot.isMe ? C.brand : C.creme).lineLimit(1)
                if let p = team.member(dot.user)?.position {
                    Text(Library.shared.positions[p] ?? p).font(F.round(14, .semibold)).foregroundStyle(C.muted)
                }
            }
            Spacer(minLength: 4)
            if dot.isMe || team.member(dot.user) != nil {
            Button { openProfile() } label: {
                Text(dot.isMe ? "MY PROFILE" : "PROFILE")
                    .font(F.round(13, .heavy)).kerning(0.6).foregroundStyle(C.creme)
                    .padding(.horizontal, 14).frame(height: 36)
                    .background(Capsule().fill(C.char800))
            }
            .buttonStyle(.press(.stud))
            .accessibilityLabel(dot.isMe ? "Open my profile" : "Open \(dot.name)'s profile")
            }
        }
    }

    private var time: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(minText(Double(dot.minutes)).uppercased())
                    .font(.system(size: 40, weight: .heavy, design: .rounded)).monospacedDigit()
                    .foregroundStyle(C.creme)
                Text("SESSION").font(F.round(12, .bold)).kerning(1.4).foregroundStyle(C.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(when(dot.date))
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(C.creme).lineLimit(1).minimumScaleFactor(0.6)
                Text(dot.date.formatted(.dateTime.hour().minute()).uppercased()).font(F.round(12, .bold)).kerning(1.4).foregroundStyle(C.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var what: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WHAT \(dot.isMe ? "YOU" : "THEY") DID").font(F.round(13, .heavy)).kerning(1.6).foregroundStyle(C.creme2)
            HStack(spacing: 14) {
                if let a = TrainingArea.of(dot.area) { AreaIcon(area: a, size: 46) }
                else {
                    Image(systemName: "figure.soccer").font(.system(size: 19, weight: .bold)).foregroundStyle(C.brandHi)
                        .frame(width: 46, height: 46).background(Circle().fill(C.brand.opacity(0.22)))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(dot.title).font(F.round(17, .bold)).foregroundStyle(C.creme).lineLimit(1)
                    Text(dot.drills.isEmpty ? "Free session" : "\(dot.drills.count) drill\(dot.drills.count == 1 ? "" : "s")")
                        .font(F.round(14, .semibold)).foregroundStyle(C.muted)
                }
                Spacer(minLength: 0)
            }
            if !dot.drills.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(dot.drills.enumerated()), id: \.offset) { i, d in
                        HStack {
                            Text(d.name).font(F.round(15, .semibold)).foregroundStyle(C.creme).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(d.dose).font(F.round(14, .semibold)).foregroundStyle(C.muted)
                        }
                        .padding(.vertical, 11)
                        if i < dot.drills.count - 1 { Rectangle().fill(C.char800).frame(height: 1) }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(C.char850))
            }
        }
    }

    private var photos: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(dot.media.filter(SessionMedia.exists), id: \.self) { m in
                Button { viewing = m } label: { MediaTile(name: m) }.buttonStyle(.press(.stud))
            }
        }
    }

    private func trainIt(_ a: TrainingArea) -> some View {
        Button {
            dismiss()
            FreeStart.shared.open(a)
        } label: {
            Text(dot.isMe ? "START AGAIN" : "TRAIN \(a.name.uppercased()) TOO")
                .font(F.round(16, .heavy)).kerning(0.6).foregroundStyle(C.brandInk)
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(Capsule().fill(C.brand))
        }
        .buttonStyle(.press(.kick))
    }

    private var more: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ALSO HERE").font(F.round(13, .heavy)).kerning(1.6).foregroundStyle(C.creme2)
            VStack(spacing: 8) {
                ForEach(here.prefix(10)) { d in
                    Button { pick(d) } label: {
                        HStack(spacing: 12) {
                            Circle().fill(d.color).frame(width: 14, height: 14).overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1.5))
                            PlayerPic(id: d.user, name: d.name, size: 34)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(d.isMe ? "You" : d.name).font(F.round(15, .bold)).foregroundStyle(d.isMe ? C.brand : C.creme).lineLimit(1)
                                Text("\(d.title) · \(when(d.date))").font(F.round(13)).foregroundStyle(C.muted).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            Text(minText(Double(d.minutes))).font(F.round(15, .bold)).foregroundStyle(C.creme2)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(C.char850))
                    }
                    .buttonStyle(.press(.stud))
                }
            }
        }
    }

    private func openProfile() {
        Haptics.play(.press)
        if dot.isMe {
            dismiss()
            Nav.shared.tab = .profile
        } else if let m = team.member(dot.user) {
            profile = m
        }
    }

    private func when(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: Date())).day ?? 0
        return days < 7 ? d.formatted(.dateTime.weekday(.wide)) : d.formatted(.dateTime.month(.abbreviated).day())
    }
}
