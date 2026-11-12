// Premade sessions (notes/23). v2, 2026-10-24 ? the user: "all the most popular apps have real players in their
// training sessions? Find real player images and make real player premade sessions with their position, duration,
// and name and that's it, no more clutter. Create real player premade sessions and also create certain technique/
// skill sessions without real players. Allow the user to easily have an unsave button."
// On the Sessions tab's TRAIN side: SKILLS = the players (photo · name · position · minutes) and the technique sessions
// (the 3D guy mid-move · name · minutes); FITNESS = real-player fitness sessions ("Mbappé Speed", no ball). Every one
// is rebuilt for the training level (LevelViews.swift). A page = the picture, the name, position · minutes, the
// drills, the photo's licence line; dock = save/unsave + START.
import SwiftUI

// MARK: - the shelves

struct PremadeShelves: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let level = store.trainingLevel
        let levelName = Library.shared.levels[safe: level]?.name ?? ""
        let lib = Library.shared
        VStack(alignment: .leading, spacing: 0) {
            // SKILLS and FITNESS on one page, kept apart (2026-10-24)
            SideMark(title: "Skills", icon: "soccerball", line: "Ball work")
                .id("shelves")
            VStack(alignment: .leading, spacing: 26) {
                Shelf(title: "Train like the pros", note: "\(levelName) level") {
                    ForEach(lib.pros(for: store.answers.position)) { p in poster(p, level) }
                }
                Shelf(title: "Technique", note: nil) {
                    ForEach(lib.technique) { p in tile(p, level) }
                }
            }
            .padding(.top, 16)

            SideMark(title: "Fitness", icon: "figure.run", line: "No ball · sprints, jumps, core")
                .padding(.top, 38)
                .id("fitness")
            VStack(alignment: .leading, spacing: 26) {
                Shelf(title: "Get fit like the pros", note: "\(levelName) level") {
                    ForEach(lib.fitness(for: store.answers.position)) { p in poster(p, level) }
                }
                Shelf(title: "Workouts", note: nil) {
                    ForEach(lib.workouts) { p in tile(p, level) }
                }
            }
            .padding(.top, 16)

            // 2026-10-27: SOCCER + FITNESS ? a run, then the ball, then a run?
            SideMark(title: "Soccer + Fitness", icon: "bolt.fill", line: "Ball work and runs, back to back")
                .padding(.top, 38)
                .id("hybrid")
            Shelf(title: "Both in one", note: "\(levelName) level") {
                ForEach(lib.hybrid) { p in tile(p, level) }
            }
            .padding(.top, 16)
        }
    }

    private func tile(_ p: ProSession, _ level: Int) -> some View {
        NavigationLink(value: SessionRoute.pro(p.id)) {
            TechniqueTile(pro: p, minutes: p.minutes(level), saved: store.saved(pro: p.id) != nil).frame(width: 150)
        }
        .buttonStyle(LipPress(radius: 22))
    }

    private func poster(_ p: ProSession, _ level: Int) -> some View {
        NavigationLink(value: SessionRoute.pro(p.id)) {
            PlayerPoster(pro: p, minutes: p.minutes(level), saved: store.saved(pro: p.id) != nil).frame(width: 172)
        }
        .buttonStyle(LipPress(radius: 22))
    }
}

/// A titled row of cards that snap.
private struct Shelf<Content: View>: View {
    let title: String
    let note: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(F.round(20, .bold)).foregroundStyle(C.creme)
                Spacer()
                if let note { Text(note).font(F.round(14, .semibold)).foregroundStyle(C.brand).contentTransition(.opacity) }
            }
            .padding(.horizontal, 4)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) { content }
                    .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .padding(.horizontal, -16)
            .scrollIndicators(.hidden)
        }
    }
}

/// A real player's session: the photo, the name, position · minutes. Nothing else.
struct PlayerPoster: View {
    let pro: ProSession
    let minutes: Int
    var saved = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        Color.clear
            .aspectRatio(0.74, contentMode: .fit)
            .overlay { PremadeArt(pro: pro) }
            .overlay {
                LinearGradient(stops: [.init(color: .clear, location: 0.4), .init(color: C.char950.opacity(0.82), location: 0.72),
                                       .init(color: C.char950, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 3) {
                    Disp(pro.title.uppercased(), size: 21)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                    HStack(spacing: 5) {
                        Text(pro.position ?? "").foregroundStyle(C.brand)
                        Text("·").foregroundStyle(C.muted)
                        Text("\(minutes) min").foregroundStyle(C.creme2).contentTransition(.numericText())
                    }
                    .font(F.round(14, .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }
                .padding(13)
            }
            .overlay(alignment: .topTrailing) { if saved { SavedMark().padding(10) } }
            .clipShape(shape)
            .overlay(shape.stroke(C.line, lineWidth: 1))
            .contentShape(shape)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(pro.title), \(pro.position ?? ""), \(minutes) minutes\(saved ? ", saved" : "")")
    }
}

/// A technique session: the 3D guy mid-move, the name, the minutes.
struct TechniqueTile: View {
    let pro: ProSession
    let minutes: Int
    var saved = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            PremadeArt(pro: pro)
                .frame(height: 132)
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [C.char850.opacity(0), C.char850], startPoint: .top, endPoint: .bottom).frame(height: 34)
                }
            VStack(alignment: .leading, spacing: 2) {
                Disp(pro.title.uppercased(), size: 19)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text("\(minutes) min").font(F.round(14, .bold)).foregroundStyle(C.muted).contentTransition(.numericText())
            }
            .padding(.horizontal, 12)
            .padding(.top, 2)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(C.char850)
        .overlay(alignment: .topTrailing) { if saved { SavedMark().padding(10) } }
        .clipShape(shape)
        .stitched(22, opacity: 0.12)
        .overlay(shape.stroke(C.line, lineWidth: 1))
        .contentShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(pro.title), \(minutes) minutes\(saved ? ", saved" : "")")
    }
}

/// "In My sessions" ? a small green bookmark on a card.
struct SavedMark: View {
    var body: some View {
        Image(systemName: "bookmark.fill")
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(C.brandInk)
            .frame(width: 28, height: 28)
            .background(Circle().fill(C.brand).overlay(Circle().stroke(C.brandInk, lineWidth: 2)))
    }
}

// MARK: - a premade session

struct ProSessionDetail: View {
    let pro: ProSession
    @Binding var path: NavigationPath
    @Environment(AppStore.self) private var store
    @State private var toast: String?

    var body: some View {
        let level = store.trainingLevel
        let items = pro.items(level)
        let saved = store.saved(pro: pro.id)
        // stretches at the start are the warm-up, at the end the cool-down
        let isStretch = { (it: PlanItem) in Library.shared.drill(it.drill).skill == "Stretching" }
        let warm = items.prefix(while: isStretch).count
        let cool = items.dropFirst(warm).reversed().prefix(while: isStretch).count
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ProHero(pro: pro, minutes: pro.minutes(level), level: Library.shared.levels[safe: level]?.name ?? "")

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(items.enumerated()), id: \.element.drill) { i, it in
                        if i == 0, warm > 0 { RailHeading("WARM-UP") }
                        if i == warm { RailHeading("THE WORK").padding(.top, warm > 0 ? 10 : 0) }
                        if i == items.count - cool, cool > 0 { RailHeading("COOL-DOWN").padding(.top, 10) }
                        SessionRow(day: todayKey(), index: i, item: it, full: false, track: false,
                                   up: i == 0 ? nil : false, down: i == items.count - 1 ? nil : false) {
                            path.append(Library.shared.drill(it.drill))
                        }
                    }
                    if let photo = pro.photo { PhotoCredit(photo: photo).padding(.top, 20) }
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .top) {
            // the hero runs under the status bar, so the usual TopScrim can't ? this keeps scrolled rows out from under it
            LinearGradient(colors: [C.char900, C.char900.opacity(0.85), C.char900.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 30)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        }
        .page()
        .screenTitle("")
        .dock {
            HStack(spacing: 12) {
                Button {
                    if saved != nil {
                        unsave()
                    } else {
                        store.save(pro)
                        Haptics.play(.goal)
                        show("Saved to My sessions")
                    }
                } label: {
                    Image(systemName: saved == nil ? "bookmark" : "bookmark.fill").font(.system(size: 22, weight: .heavy))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.gameRound(saved == nil ? .charcoal : .brand, size: 64))
                .accessibilityLabel(saved == nil ? "Save to My sessions" : "Remove from My sessions")

                ShareButton(item: .pro(pro, level: level), size: 64)

                Button { ActiveRun.shared.start(RunRequest(items: pro.items(store.trainingLevel), name: pro.title, session: store.saved(pro: pro.id)?.id, pro: pro.id)) } label: { Label("START", systemImage: "play.fill") }
                    .buttonStyle(.gameLarge)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(F.round(15, .semibold)).foregroundStyle(C.creme)
                    .padding(.horizontal, 16).frame(height: 44)
                    .background(Capsule().fill(C.char700).overlay(Capsule().stroke(C.charInk, lineWidth: 2)))
                    .padding(.bottom, 104)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func unsave() {
        store.unsave(pro: pro.id)
        Haptics.play(.unlatch)
        show("Removed from My sessions")
    }

    private func show(_ text: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation(.easeOut(duration: 0.3)) { if toast == text { toast = nil } } }
    }
}

/// The page's one hero: the picture full-bleed under the status bar, the name, position · minutes, the level.
struct ProHero: View {
    let pro: ProSession
    let minutes: Int
    let level: String

    var body: some View {
        Color.clear
            .frame(height: pro.isPlayer ? 500 : 430)
            .frame(maxWidth: .infinity)
            .overlay { PremadeArt(pro: pro, tile: false) }
            .overlay {
                LinearGradient(stops: [.init(color: .black.opacity(0.5), location: 0), .init(color: .clear, location: 0.22),
                                       .init(color: .clear, location: 0.5), .init(color: C.char900.opacity(0.9), location: 0.82),
                                       .init(color: C.char900, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 8) {
                    Disp(pro.title.uppercased(), size: 44)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    HStack(spacing: 8) {
                        Text((pro.position ?? (pro.kind == "hybrid" ? "Soccer + Fitness" : pro.kind == "workout" ? "Fitness" : "Technique")).uppercased()).foregroundStyle(C.brand)
                        Text("·").foregroundStyle(C.muted)
                        Text("\(minutes) MIN").foregroundStyle(C.creme)
                        Text(level.uppercased())
                            .font(F.round(12, .bold)).kerning(1.1)
                            .foregroundStyle(C.creme2)
                            .padding(.horizontal, 9).frame(height: 24)
                            .background(Capsule().fill(C.char700).overlay(Capsule().stroke(C.charInk, lineWidth: 2)))
                    }
                    .font(F.round(16, .bold)).kerning(1.2)
                }
                .padding(.horizontal, 18)
            }
            .clipped()
    }
}

/// A small heading inside the session rail.
struct RailHeading: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(F.round(13, .bold)).kerning(1.4).foregroundStyle(C.muted).padding(.leading, 4)
    }
}

/// The photo's licence line (Wikimedia Commons: author, licence, source ? all linked).
struct PhotoCredit: View {
    let photo: PlayerPhoto
    var body: some View {
        let by = photo.by.filter { !"[]()*_`".contains($0) }
        let lic = photo.licenseURL.map { "[\(photo.license)](\($0))" } ?? photo.license
        Text(.init("Photo: \(by) · \(lic) · [Wikimedia Commons](\(photo.page))"))
            .font(F.round(13, .medium))
            .foregroundStyle(C.muted)
            .tint(C.creme2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

/// A saved premade session on My sessions: its picture as a little card in place of the drill covers.
struct ProTile: View {
    let pro: ProSession
    var body: some View {
        PremadeArt(pro: pro)
            .frame(width: 46, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(C.charInk, lineWidth: 2))
            .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
            .rotationEffect(.degrees(5), anchor: .bottom)
            .padding(.trailing, 14)
            .padding(.vertical, 2)
    }
}
