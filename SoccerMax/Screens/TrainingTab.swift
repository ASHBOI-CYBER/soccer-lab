// TRAINING tab (SOCCER LAB, 2026-11-12). Today's session is built from onboarding: a warm-up, ball work every
// player does, and drills for the player's position (LabPlan). Under it: the Fix List (drills the Film tab added),
// the ready-made sessions from the library, and the free session logger that used to be the Sessions tab.
import SwiftUI

struct TrainingTab: View {
    @Environment(AppStore.self) private var store
    @State private var lab = Lab.shared

    private var plan: [Drill] { LabPlan.today(position: store.answers.position) }
    private var fixes: [Drill] { lab.fixList.filter { Library.shared.has($0) }.map { Library.shared.drill($0) } }
    private var sessions: [ProSession] { Library.shared.technique + Library.shared.hybrid + Library.shared.workouts }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    TabHeader("TRAINING")
                    today
                    if !fixes.isEmpty { fixList }
                    readyMade
                    free
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .tabRoot("Training")
            .navigationDestination(for: Drill.self) { DrillDetail(drill: $0) }
            .navigationDestination(for: ProSession.self) { LabSessionPage(session: $0) }
            // a session tapped on Profile's graph opens here
            .navigationDestination(item: Binding(get: { Nav.shared.log }, set: { Nav.shared.log = $0 })) { LoggedDetail(c: $0) }
            .page()
        }
    }

    // MARK: today

    private var today: some View {
        let list = plan
        let doneCount = list.filter { lab.isDone($0.id) }.count
        let minutes = list.reduce(0) { $0 + $1.min }
        return VStack(alignment: .leading, spacing: 12) {
            LabKicker("TODAY'S SESSION")
            LabPanel {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Disp("\(LabPlan.group(store.answers.position).uppercased()) SESSION", size: 24)
                        Text("Built for a \(store.answers.positionName.lowercased()) · about \(minutes) min")
                            .font(F.round(14, .semibold)).foregroundStyle(C.muted)
                    }
                    HStack(spacing: 10) {
                        LabBar(value: Double(doneCount), goal: Double(max(1, list.count)))
                        Text("\(doneCount) of \(list.count)").font(F.round(13, .bold)).foregroundStyle(C.creme2)
                    }
                    VStack(spacing: 10) {
                        ForEach(list) { d in LabDrillRow(drill: d) }
                    }
                    if doneCount == list.count, !list.isEmpty {
                        Label("Session done. Nice work.", systemImage: "checkmark.seal.fill")
                            .font(F.round(15, .bold)).foregroundStyle(C.gold)
                    }
                }
            }
        }
    }

    // MARK: fix list

    private var fixList: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabKicker("FIX LIST · FROM YOUR FILM")
            LabPanel {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Do each one \(Lab.fixGoal) times and it leaves the list.")
                        .font(F.round(14, .semibold)).foregroundStyle(C.muted)
                    ForEach(fixes) { d in
                        LabDrillRow(drill: d, note: "\(lab.fixCount[d.id] ?? 0) of \(Lab.fixGoal) done")
                    }
                }
            }
        }
    }

    // MARK: ready-made sessions

    private var readyMade: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabKicker("READY-MADE SESSIONS")
            VStack(spacing: 10) {
                ForEach(sessions) { s in
                    NavigationLink(value: s) {
                        HStack(spacing: 12) {
                            Image(systemName: s.kind == "workout" ? "bolt.fill" : s.kind == "hybrid" ? "flame.fill" : "soccerball")
                                .font(.system(size: 18, weight: .bold)).foregroundStyle(C.brandInk)
                                .frame(width: 42, height: 42)
                                .background(Circle().fill(C.brand))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.title).font(F.round(17, .bold)).foregroundStyle(C.creme)
                                Text(s.kind == "workout" ? "Fitness" : s.kind == "hybrid" ? "Soccer and fitness" : "Technique")
                                    .font(F.round(13, .semibold)).foregroundStyle(C.muted)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .heavy)).foregroundStyle(C.muted)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(C.char800)
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(C.charInk, lineWidth: 2.5)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: free session

    private var free: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabKicker("TRAINED ON YOUR OWN?")
            Button { FreeStart.shared.request = FreeRequest(area: nil) } label: {
                Label("LOG A FREE SESSION", systemImage: "play.fill")
            }
            .buttonStyle(.game(.charcoal))
        }
    }
}

/// One drill: a tick button on the left (marks it done for today), the rest opens the drill page.
struct LabDrillRow: View {
    let drill: Drill
    var note: String? = nil
    @Environment(AppStore.self) private var store
    @State private var lab = Lab.shared

    var body: some View {
        let done = lab.isDone(drill.id)
        HStack(spacing: 12) {
            Button {
                lab.complete(drill, store: store)
                Haptics.play(.goal)
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(done ? C.brand : C.char600)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(done)
            .accessibilityLabel(done ? "\(drill.name), done" : "Mark \(drill.name) done")

            NavigationLink(value: drill) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(drill.name).font(F.round(16, .bold)).foregroundStyle(done ? C.muted : C.creme)
                            .strikethrough(done, color: C.muted)
                        Text(note ?? "\(drill.skill) · \(drill.reps) · \(drill.min) min")
                            .font(F.round(13, .semibold)).foregroundStyle(C.muted).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .heavy)).foregroundStyle(C.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4).padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(C.char850))
    }
}

/// A ready-made session: pick a level, then tick its drills off.
struct LabSessionPage: View {
    let session: ProSession
    @State private var level = "Club"

    private var names: [String] { Library.shared.levels.map(\.name) }
    private var index: Int { names.firstIndex(of: level) ?? 0 }
    private var rows: [ProDrill] { session.levels[safe: index] ?? session.levels.last ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Disp(session.title.uppercased(), size: 32)
                Text(Library.shared.levels[safe: index]?.line ?? "")
                    .font(F.round(15, .semibold)).foregroundStyle(C.muted)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(names, id: \.self) { n in
                            Button(n) { level = n }
                                .font(F.round(14, .bold))
                                .foregroundStyle(n == level ? Color.white : C.creme2)
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .background(Capsule().fill(n == level ? C.brand : C.char800))
                                .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                VStack(spacing: 10) {
                    ForEach(rows, id: \.id) { r in
                        let d = Library.shared.drill(r.id)
                        LabDrillRow(drill: d, note: "\(r.sets ?? 3) sets · \(d.reps) · \(d.min) min")
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .page()
    }
}
