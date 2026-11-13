// DRILL LIBRARY (SOCCER LAB, 2026-11-13). Every drill in the app in one place: search, filter by skill, tap a drill
// to open its page. Opens from the Training tab.
import SwiftUI

enum LabRoute: Hashable { case drills }

struct LabDrillLibrary: View {
    @State private var query = ""
    @State private var skill = "All"
    private let lib = Library.shared

    /// Skills that have at least one drill, in the library's own order.
    private var skills: [String] {
        let have = Set(lib.drills.map(\.skill))
        let known = lib.categories.filter { have.contains($0) }
        return known + have.subtracting(known).sorted()
    }

    var body: some View {
        let pool = skill == "All" ? lib.drills : lib.drills.filter { $0.skill == skill }
        let list = lib.search(query, in: pool)
        let groups = Dictionary(grouping: list, by: \.skill)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Drill library").font(.system(size: 28, weight: .bold)).foregroundStyle(C.creme)
                    Text("\(lib.drills.count) drills. Tap one to see how to do it.")
                        .font(F.round(14, .medium)).foregroundStyle(C.muted)
                }
                SearchField(text: $query, prompt: "Search drills")
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(["All"] + skills, id: \.self) { s in
                            let on = s == skill
                            Button { skill = s; Haptics.play(.stud) } label: {
                                Text(s).font(F.round(14, .semibold))
                                    .foregroundStyle(on ? Color.white : C.creme2)
                                    .padding(.horizontal, 14).frame(height: 36)
                                    .background(Capsule().fill(on ? C.brand : C.char800))
                                    .overlay(Capsule().stroke(on ? Color.clear : C.line, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                }
                .scrollIndicators(.hidden)

                if list.isEmpty {
                    Text(query.isEmpty ? "No drills here yet." : "Nothing found for \"\(query)\".")
                        .font(F.round(15, .semibold)).foregroundStyle(C.muted)
                        .frame(maxWidth: .infinity).padding(.vertical, 30)
                }
                ForEach(skills.filter { groups[$0] != nil }, id: \.self) { s in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            LabKicker(s.uppercased())
                            Spacer()
                            Text("\(groups[s]?.count ?? 0)").font(F.round(13, .bold)).foregroundStyle(C.muted)
                        }
                        ForEach(groups[s] ?? []) { d in
                            LabDrillRow(drill: d, note: "\(d.levelName) \u{00B7} \(d.who) \u{00B7} \(d.min) min", canTick: false)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("Drills")
        .navigationBarTitleDisplayMode(.inline)
        .page()
    }
}
