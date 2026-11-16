// AI NUTRITION PLAN (2026-11-17; supabase/functions/nutrition-plan). The Fuel tab's targets come from the player's own
// numbers (FuelTargets in LabData.swift); this card asks the AI to turn them into a personal plan: why these targets,
// a training day of meals that adds up to them, match-day timing and habits. Made when the player asks, kept on the
// phone, and offered again when their numbers change. Needs sign-in and the AI yes (AIVision.swift).
import SwiftUI

struct AIPlan: Codable, Hashable {
    struct Meal: Codable, Hashable { var when: String; var name: String; var foods: [String]; var kcal: Int; var protein: Int }
    var summary: String
    var meals: [Meal]
    var matchday: [String]
    var habits: [String]
    var made = Date()
    /// The targets it was made for: when they change, the card offers a new plan.
    var kcal = 0
}

@MainActor @Observable
final class NutritionPlanStore {
    static let shared = NutritionPlanStore()
    private(set) var plan: AIPlan? = UserDefaults.standard.data(forKey: "ai.plan.v1").flatMap { try? JSONDecoder().decode(AIPlan.self, from: $0) }
    private(set) var busy = false
    var error: String?

    func make(_ store: AppStore) async {
        busy = true
        error = nil
        defer { busy = false }
        struct Reply: Decodable { let plan: AIPlan.Wire }
        do {
            let r = try await AICall.post("nutrition-plan", ["context": Self.context(store)], kind: "plan", as: Reply.self)
            var p = r.plan.plan
            p.kcal = Lab.shared.targets.kcal
            plan = p
            UserDefaults.standard.set(try? JSONEncoder().encode(p), forKey: "ai.plan.v1")
            Haptics.play(.goal)
        } catch let e as AICall.Failure {
            error = e.message
        } catch {
            self.error = "Something went wrong. Try again."
        }
    }

    /// What the AI gets: the player's numbers and targets, and what they usually eat (for the kind of food). No name.
    static func context(_ store: AppStore) -> String {
        let a = store.answers, lab = Lab.shared, b = lab.body, t = lab.targets
        var l: [String] = []
        l.append("Age \(b.age), \(a.gender ?? "gender not said"), \(Int(b.heightCm)) cm, \(Int(b.weightKg)) kg")
        l.append("Position: \(a.positionName). Level: \(a.level ?? "not said"). Trains \(b.trainingDays) days a week.")
        l.append("Main goal: \(a.goal ?? "not said"). Food goal: \(b.goal ?? a.fuelGoal ?? "Just eat better").")
        l.append("Daily targets (keep these): \(t.kcal) kcal, \(t.protein) g protein, \(t.carbs) g carbs, \(t.fat) g fat, \(t.water) glasses of water.")
        let eaten = lab.fuel.values.flatMap(\.entries).map(\.name)
        var seen = Set<String>(), recent: [String] = []
        for n in eaten.reversed() where seen.insert(n.lowercased()).inserted { recent.append(n); if recent.count == 15 { break } }
        if !recent.isEmpty { l.append("Foods they log (cuisine hints): " + recent.joined(separator: ", ")) }
        if let region = Locale.current.region?.identifier { l.append("Country: \(region)") }
        return l.joined(separator: "\n")
    }
}

extension AIPlan {
    /// The server's shape (no `made` / `kcal`).
    struct Wire: Decodable {
        let summary: String; let meals: [Meal]; let matchday: [String]; let habits: [String]
        var plan: AIPlan { AIPlan(summary: summary, meals: meals, matchday: matchday, habits: habits) }
    }
}

/// The Fuel tab card: make the plan, or open it.
struct NutritionPlanCard: View {
    @Environment(AppStore.self) private var store
    @State private var plans = NutritionPlanStore.shared
    @State private var lab = Lab.shared
    @State private var open = false

    var body: some View {
        let stale = plans.plan.map { $0.kcal != lab.targets.kcal } ?? false
        Button { open = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(LinearGradient(colors: [Color(hex: 0x2BB673), Color(hex: 0x1E8F5A)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Your AI nutrition plan").font(F.round(17, .bold)).foregroundStyle(C.creme)
                        Text("AI").font(F.round(11, .heavy)).foregroundStyle(C.brandInk)
                            .padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(C.brandHi))
                    }
                    Text(plans.plan == nil ? "Meals and timing built around your \(lab.targets.kcal) kcal."
                         : stale ? "Your numbers changed. Tap to update your plan." : "\(plans.plan!.meals.count) meals for a training day, match-day timing and habits.")
                        .font(F.round(13, .semibold)).foregroundStyle(stale ? C.gold : C.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .heavy)).foregroundStyle(C.muted)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(C.char800)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color(hex: 0x2BB673).opacity(0.45), lineWidth: 1)))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $open) { NutritionPlanSheet() }
    }
}

struct NutritionPlanSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    @State private var plans = NutritionPlanStore.shared
    @State private var lab = Lab.shared
    @State private var editing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Disp("YOUR PLAN", size: 30)
                    Spacer()
                    Button("Done") { dismiss() }.font(F.round(16, .bold)).foregroundStyle(C.brandHi)
                }
                .padding(.top, 24)

                targets

                if !lab.body.isSet {
                    Text("Add your age, height, weight and food goal first, so the plan is built for you.")
                        .font(F.round(15, .semibold)).foregroundStyle(C.creme2)
                    Button("ADD MY DETAILS") { editing = true }.buttonStyle(.game(.brand))
                } else if let p = plans.plan, p.kcal == lab.targets.kcal {
                    planView(p)
                    Button(plans.busy ? "Making…" : "Make a new plan") { Task { await plans.make(store) } }
                        .font(F.round(15, .bold)).foregroundStyle(C.brandHi).frame(maxWidth: .infinity)
                        .disabled(plans.busy)
                } else {
                    if plans.plan != nil {
                        Text("Your numbers changed since your last plan, so here's a fresh one.")
                            .font(F.round(14, .semibold)).foregroundStyle(C.gold)
                    }
                    AIGate(what: "nutrition plans", onNo: { dismiss() }) {
                        Button { Task { await plans.make(store) } } label: {
                            HStack { if plans.busy { ProgressView().tint(.white) }; Text(plans.busy ? "MAKING YOUR PLAN…" : "MAKE MY PLAN") }
                        }
                        .buttonStyle(.gameLarge(.brand, feel: .goal))
                        .disabled(plans.busy)
                    }
                }
                if let e = plans.error {
                    Label(e, systemImage: "exclamationmark.triangle.fill").font(F.round(14, .semibold)).foregroundStyle(C.gold)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("A guide for active players, not medical advice. If you have a health condition, follow your doctor.")
                    .font(F.round(12, .medium)).foregroundStyle(C.muted).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .presentationDetents([.large])
        .presentationBackground(C.char900)
        .sheet(isPresented: $editing) { FuelBodySheet() }
    }

    private var targets: some View {
        let t = lab.targets
        return VStack(alignment: .leading, spacing: 10) {
            LabKicker("YOUR DAILY TARGETS")
            HStack(spacing: 8) {
                chip("\(t.kcal)", "kcal", C.gold)
                chip("\(t.protein)g", "protein", Color(hex: 0x2BB673))
                chip("\(t.carbs)g", "carbs", C.brandHi)
                chip("\(t.fat)g", "fat", Color(hex: 0xA78BFA))
            }
            if lab.body.isSet {
                Text("From your \(Int(lab.body.weightKg)) kg, \(Int(lab.body.heightCm)) cm, age \(lab.body.age), \(lab.body.trainingDays) training days a week\(lab.body.goal.map { " and your goal: \($0.lowercased())" } ?? "").")
                    .font(F.round(13, .semibold)).foregroundStyle(C.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func chip(_ v: String, _ label: String, _ c: Color) -> some View {
        VStack(spacing: 2) {
            Text(v).font(F.round(18, .heavy)).foregroundStyle(c).monospacedDigit()
            Text(label).font(F.round(11, .bold)).foregroundStyle(C.muted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(C.char800))
    }

    private func planView(_ p: AIPlan) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(p.summary).font(F.round(16, .semibold)).foregroundStyle(C.creme2).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 10) {
                LabKicker("A TRAINING DAY")
                ForEach(Array(p.meals.enumerated()), id: \.offset) { _, m in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(m.when.uppercased()).font(F.round(11, .heavy)).foregroundStyle(C.brandHi)
                                Text(m.name).font(F.round(16, .bold)).foregroundStyle(C.creme)
                            }
                            Spacer()
                            Text("\(m.kcal) kcal · \(m.protein)g P").font(F.round(12, .bold)).foregroundStyle(C.muted).monospacedDigit()
                        }
                        ForEach(m.foods, id: \.self) { f in
                            Label(f, systemImage: "circle.fill").labelStyle(DotLabel()).font(F.round(14, .semibold)).foregroundStyle(C.creme2)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(C.char800))
                }
            }
            if !p.matchday.isEmpty { bullets("MATCH DAY", p.matchday, "sportscourt.fill") }
            if !p.habits.isEmpty { bullets("HABITS", p.habits, "checkmark.circle.fill") }
        }
    }

    private func bullets(_ title: String, _ items: [String], _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LabKicker(title)
            ForEach(items, id: \.self) { t in
                Label { Text(t).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: icon).foregroundStyle(C.brand) }
                    .font(F.round(15, .semibold)).foregroundStyle(C.creme)
            }
        }
    }
}

/// A small dot in front of a food line.
private struct DotLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon.font(.system(size: 5)).foregroundStyle(C.muted)
            configuration.title
        }
    }
}
