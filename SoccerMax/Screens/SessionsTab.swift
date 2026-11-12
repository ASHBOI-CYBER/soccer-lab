// SESSIONS TAB v2 (2026-11-08): "sessions should start as a blank canvas. A start session button should be there?
// upgrade the UI of the page, use the same fonts as the rest of the app, remove the borders, remove the extra text,
// let the train icons be presets not the main sessions starters, make it look beautiful (upgrade the icons)."
//
// The page is two things: one big glossy START button (? a blank live session, FreeSession.swift ? the category icons
// live INSIDE the session as presets) and RECENT (each with START AGAIN). No cards, no outlines, no helper text.
import SwiftUI

struct TrainTab: View {
    @Environment(AppStore.self) private var store

    /// Past live sessions, newest first.
    private var recent: [Completion] { store.completions.filter { $0.area != nil }.sorted { $0.date > $1.date } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    TabHeader("SESSIONS")
                    StartHero()
                        .frame(maxWidth: .infinity)
                    if !recent.isEmpty { history }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .tabRoot("Sessions")
            // a session tapped on Profile's graph opens here
            .navigationDestination(item: Binding(get: { Nav.shared.log }, set: { Nav.shared.log = $0 })) { LoggedDetail(c: $0) }
            .page()
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .lastTextBaseline) {
                Disp("RECENT", size: 24)
                Spacer()
                NavigationLink { LoggedPage() } label: {
                    Text("See all").font(F.round(16, .bold)).foregroundStyle(C.brand)
                }
            }
            VStack(spacing: 20) {
                ForEach(recent.prefix(12), id: \.self) { c in RecentRow(c: c) }
            }
        }
    }
}

/// The big glossy start button: a lit green ball with a slow breathing glow.
private struct StartHero: View {
    @State private var breathe = false
    var body: some View {
        Button { FreeStart.shared.open(nil) } label: {
            VStack(spacing: 22) {
                ZStack {
                    Circle().fill(C.brand.opacity(0.16))
                        .frame(width: 236, height: 236)
                        .scaleEffect(breathe ? 1.06 : 0.94)
                        .blur(radius: 10)
                    Circle()
                        .fill(RadialGradient(colors: [C.brandHi, C.brand, C.brandMid, C.brandLip],
                                             center: UnitPoint(x: 0.4, y: 0.25), startRadius: 4, endRadius: 140))
                        .frame(width: 184, height: 184)
                        .overlay(alignment: .top) {
                            Ellipse()
                                .fill(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                                .frame(width: 120, height: 62)
                                .padding(.top, 12)
                        }
                        .shadow(color: C.brand.opacity(0.45), radius: 30, y: 12)
                    Image(systemName: "play.fill")
                        .font(.system(size: 66, weight: .heavy))
                        .foregroundStyle(.white)
                        .shadow(color: C.brandInk.opacity(0.4), radius: 3, y: 2)
                        .offset(x: 6)
                }
                Disp("START SESSION", size: 32)
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.press(.kick))
        .accessibilityLabel("Start a session")
        .onAppear { withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { breathe = true } }
    }
}

/// A category's icon: a glossy green tile with a lit top edge (dim = a quiet charcoal tile with a green symbol).
struct AreaIcon: View {
    let area: TrainingArea
    var size: CGFloat = 46
    var dim = false
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
        Image(systemName: area.icon)
            .font(.system(size: size * 0.44, weight: .bold))
            .foregroundStyle(dim ? C.brand : .white)
            .shadow(color: dim ? .clear : C.brandInk.opacity(0.35), radius: 1, y: 1)
            .frame(width: size, height: size)
            .background {
                if dim {
                    shape.fill(LinearGradient(colors: [C.char700, C.char800], startPoint: .top, endPoint: .bottom))
                } else {
                    shape.fill(LinearGradient(colors: [C.brandHi, C.brand, C.brandMid], startPoint: .top, endPoint: .bottom))
                        .overlay(alignment: .top) {
                            shape.fill(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0)], startPoint: .top, endPoint: .center))
                                .frame(height: size * 0.55)
                                .padding(size * 0.06)
                        }
                        .shadow(color: C.brand.opacity(0.35), radius: size * 0.18, y: size * 0.06)
                }
            }
    }
}

enum Ago {
    static func text(_ d: Date) -> String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: Date())).day ?? 0
        return days == 0 ? "Today" : days == 1 ? "Yesterday" : "\(days)d ago"
    }
}

/// A past session: icon(s), name, when + how long, START AGAIN. Tap = its log page. No card behind it.
private struct RecentRow: View {
    let c: Completion
    var body: some View {
        let first = c.parts?.first.map { TrainingArea(id: $0.area, name: $0.name, icon: $0.icon) }
            ?? TrainingArea.of(c.area) ?? TrainingArea.all[0]
        HStack(spacing: 14) {
            NavigationLink { LoggedDetail(c: c) } label: {
                HStack(spacing: 14) {
                    AreaIcon(area: first, size: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(c.name).font(F.round(18, .bold)).foregroundStyle(C.creme).lineLimit(1)
                        Text("\(Ago.text(c.date)) · \(minText(Double(c.minutes)))")
                            .font(F.round(14, .semibold)).foregroundStyle(C.muted).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.press(.stud))

            Button { FreeStart.shared.open(first) } label: {
                Text("START AGAIN")
                    .font(F.display(14))
                    .foregroundStyle(C.brandInk)
                    .padding(.horizontal, 14).frame(height: 36)
                    .background(Capsule().fill(LinearGradient(colors: [C.brandHi, C.brand], startPoint: .top, endPoint: .bottom)))
            }
            .buttonStyle(.press(.kick))
            .accessibilityLabel("Start \(first.name) again")
        }
    }
}
