// NUTRITION tab (SOCCER LAB, 2026-11-12). A fuel log: daily targets from the player's own numbers
// (FuelTargets in LabData.swift), quick-add from ~270 common foods (search, recent first), your own entries, water,
// and (2026-11-15) an AI photo scan of a meal (FoodScan.swift). The log stays on the phone. It is about eating
// enough to train and recover: there is no weight-loss mode.
import SwiftUI

struct NutritionTab: View {
    @State private var lab = Lab.shared
    // test builds: `-route tab:nutrition:addfood` / `:scan` open those sheets
    @State private var adding = DebugRoute.parts.contains("addfood")
    @State private var scanning = DebugRoute.parts.contains("scan")
    @State private var editingBody = false
    /// The day being looked at ("Mon"..."Sun" of this week); today when the tab opens.
    @State private var day = todayKey()
    // test builds: `-route tab:nutrition:snacks:bottom` opens on that category
    @State private var planCategory = MealPlan.categories.first { DebugRoute.parts.contains($0.lowercased()) } ?? MealPlan.categories[0]

    private var key: String { dateKey(dateOf(day)) }
    private var isToday: Bool { day == todayKey() }
    private var log: FuelDay { lab.fuel[key] ?? FuelDay() }

    var body: some View {
        let d = log
        let goal = lab.targets
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    TabHeader(title: "Fuel") {
                        Button { editingBody = true } label: {
                            Label(lab.body.isSet ? "Edit goals" : "Set goals", systemImage: "slider.horizontal.3")
                                .font(F.round(14, .bold)).foregroundStyle(C.brandHi)
                                .padding(.horizontal, 14).frame(height: 40)
                                .background(Capsule().fill(C.brand.opacity(0.14)).overlay(Capsule().stroke(C.brand.opacity(0.5), lineWidth: 1)))
                        }
                        .buttonStyle(.plain)
                    }
                    Text("Eat enough to train hard and recover well.")
                        .font(F.round(14, .medium)).foregroundStyle(C.muted).padding(.top, -14).padding(.horizontal, 4)
                    week
                    if !lab.body.isSet { personalise }
                    calories(d, goal)
                    macros(d, goal)
                    NutritionPlanCard()
                    if isToday { tip(d, goal) }
                    water(d, goal)
                    if isToday { FoodScanCard { scanning = true } }
                    meals(d)
                    mealPlans
                    Text("A general guide for active players, not medical advice. If you have a health condition, follow your doctor.")
                        .font(F.round(12, .medium)).foregroundStyle(C.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            // test builds: `-route tab:nutrition:bottom` opens scrolled to the end, for screenshots of the lower half
            .defaultScrollAnchor(DebugRoute.parts.contains("bottom") ? .bottom : .top)
            .tabRoot("Nutrition")
            .page()
        }
        .sheet(isPresented: $adding) { FoodSheet() }
        .sheet(isPresented: $scanning) { FoodScanSheet() }
        .sheet(isPresented: $editingBody) { FuelBodySheet() }
    }

    /// Players from before onboarding asked for height and weight (2026-11-17) still see the general 2,400 kcal.
    private var personalise: some View {
        Button { editingBody = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.checkmark").font(.system(size: 22, weight: .bold)).foregroundStyle(C.gold)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Make these targets yours").font(F.round(16, .bold)).foregroundStyle(C.creme)
                    Text("Add your age, height, weight and goal. Right now you see a general day for an active player.")
                        .font(F.round(13, .semibold)).foregroundStyle(C.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .heavy)).foregroundStyle(C.muted)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(C.gold.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(C.gold.opacity(0.4), lineWidth: 1)))
        }
        .buttonStyle(.plain)
    }

    // MARK: week

    private var week: some View {
        HStack(spacing: 6) {
            ForEach(DAYS, id: \.self) { d in
                let when = dateOf(d)
                let picked = d == day
                let today = d == todayKey()
                let logged = !(lab.fuel[dateKey(when)]?.entries.isEmpty ?? true)
                Button {
                    day = d
                    Haptics.play(.stud)
                } label: {
                    VStack(spacing: 6) {
                        Text(String(d.prefix(1))).font(F.round(12, .bold)).foregroundStyle(picked ? Color.white : C.muted)
                        Text("\(Calendar.current.component(.day, from: when))")
                            .font(F.round(18, .bold)).foregroundStyle(picked ? Color.white : when > Date() ? C.muted : C.creme)
                        Circle().fill(logged ? (picked ? Color.white : C.brand) : (today ? C.brandHi.opacity(0.6) : Color.clear))
                            .frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(picked ? AnyShapeStyle(LinearGradient(colors: [C.brandHi, C.brand], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(C.char800))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(picked ? Color.clear : C.line, lineWidth: 1))
                            .shadow(color: picked ? C.brand.opacity(0.65) : .clear, radius: 12, y: 3)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(FULL_DAY[d]?.capitalized ?? d) \(Calendar.current.component(.day, from: when))\(today ? ", today" : "")\(logged ? ", food logged" : "")")
                .accessibilityAddTraits(picked ? .isSelected : [])
            }
        }
    }

    // MARK: calories

    private func calories(_ d: FuelDay, _ goal: FuelTargets) -> some View {
        let left = goal.kcal - d.kcal
        let pct = goal.kcal > 0 ? Int((Double(d.kcal) / Double(goal.kcal) * 100).rounded()) : 0
        return LabPanel(padding: 18) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(abs(left))")
                        .font(.system(size: 40, weight: .bold)).foregroundStyle(C.creme)
                        .minimumScaleFactor(0.6).lineLimit(1)
                    Text(left >= 0 ? "Calories left" : "Calories over").font(F.round(16, .semibold)).foregroundStyle(C.creme2)
                    LabBar(value: Double(d.kcal), goal: Double(goal.kcal)).padding(.top, 6)
                    HStack {
                        Text("\(d.kcal) eaten").font(F.round(13, .semibold)).foregroundStyle(C.muted)
                        Spacer()
                        Text("\(goal.kcal) kcal goal").font(F.round(13, .semibold)).foregroundStyle(C.muted)
                    }
                }
                LabRing(value: Double(d.kcal), goal: Double(goal.kcal), width: 11) {
                    VStack(spacing: 2) {
                        Image(systemName: "flame.fill").font(.system(size: 20, weight: .bold)).foregroundStyle(C.brandHi)
                        Text("\(pct)%").font(F.round(14, .bold)).foregroundStyle(C.creme)
                    }
                }
                .frame(width: 92, height: 92)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: macros

    private func macros(_ d: FuelDay, _ goal: FuelTargets) -> some View {
        HStack(spacing: 10) {
            macro("Protein", d.protein, goal.protein, "dumbbell.fill", labSkillColor("Stretching"))
            macro("Carbs", d.carbs, goal.carbs, "bolt.fill", C.gold)
            macro("Fat", d.fat, goal.fat, "drop.fill", labSkillColor("Defending"))
        }
    }

    private func macro(_ name: String, _ value: Double, _ goal: Int, _ icon: String, _ tint: Color) -> some View {
        let left = max(0, goal - Int(value.rounded()))
        return VStack(spacing: 8) {
            Text("\(left)g").font(.system(size: 20, weight: .bold)).foregroundStyle(C.creme)
            Text("\(name) left").font(F.round(12, .semibold)).foregroundStyle(C.muted)
            LabRing(value: value, goal: Double(goal), color: tint, width: 6) {
                Image(systemName: icon).font(.system(size: 14, weight: .bold)).foregroundStyle(tint)
            }
            .frame(width: 56, height: 56)
            Text("\(Int(value.rounded())) / \(goal)g").font(F.round(12, .semibold)).foregroundStyle(C.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [tint.opacity(0.10), C.char800], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(C.line, lineWidth: 1))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name): \(Int(value.rounded())) of \(goal) grams")
    }

    // MARK: water

    private func water(_ d: FuelDay, _ goal: FuelTargets) -> some View {
        LabPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Water", systemImage: "drop.fill").font(F.round(16, .bold)).foregroundStyle(C.creme)
                        Text("\(d.water) of \(goal.water) glasses").font(F.round(13, .semibold)).foregroundStyle(C.muted)
                    }
                    Spacer(minLength: 0)
                    if isToday {
                        Button { lab.water(-1); Haptics.play(.stud) } label: {
                            Image(systemName: "minus").font(.system(size: 15, weight: .heavy)).foregroundStyle(d.water == 0 ? C.muted : C.creme)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(C.char700).overlay(Circle().stroke(C.line, lineWidth: 1)))
                        }
                        .buttonStyle(.plain)
                        .disabled(d.water == 0)
                        .accessibilityLabel("One glass less")
                        Button { lab.water(1); Haptics.play(.pop) } label: {
                            Image(systemName: "plus").font(.system(size: 15, weight: .heavy)).foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(LinearGradient(colors: [C.brandHi, C.brand], startPoint: .top, endPoint: .bottom)))
                                .shadow(color: C.brand.opacity(0.6), radius: 8)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add a glass of water")
                    }
                }
                HStack(spacing: 5) {
                    ForEach(0..<goal.water, id: \.self) { i in
                        Capsule().fill(i < d.water ? C.brandHi : C.char700)
                            .frame(height: 22)
                            .shadow(color: i < d.water ? C.brand.opacity(0.6) : .clear, radius: 5)
                    }
                }
                .accessibilityHidden(true)
            }
        }
    }

    // MARK: meals

    private func meals(_ d: FuelDay) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(isToday ? "Today's meals" : "\(FULL_DAY[day]?.capitalized ?? day)'s meals")
                    .font(.system(size: 18, weight: .bold)).foregroundStyle(C.creme)
                Spacer()
                // the add button lives here (2026-11-13): a floating one kept landing on top of other buttons
                if isToday {
                    Button { adding = true } label: {
                        Label("Add food", systemImage: "plus")
                            .font(F.round(14, .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 14).frame(height: 38)
                            .background(Capsule().fill(LinearGradient(colors: [C.brand, C.brandMid], startPoint: .top, endPoint: .bottom)))
                            .shadow(color: C.brand.opacity(0.4), radius: 8, y: 2)
                    }
                    .buttonStyle(.press(.pop))
                }
            }
            if d.entries.isEmpty {
                LabPanel(padding: 22) {
                    VStack(spacing: 10) {
                        Image(systemName: "fork.knife").font(.system(size: 22, weight: .bold)).foregroundStyle(C.brandHi)
                            .frame(width: 60, height: 60)
                            .background(Circle().fill(C.brand.opacity(0.16)))
                            .shadow(color: C.brand.opacity(0.5), radius: 14)
                        Text(isToday ? "No meals logged yet" : "Nothing was logged").font(F.round(17, .bold)).foregroundStyle(C.creme)
                        Text(isToday ? "Add what you eat, or log a meal plan below in one tap." : "Pick today to log food.")
                            .font(F.round(14, .medium)).foregroundStyle(C.muted).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(d.entries.reversed()) { e in
                        HStack(spacing: 12) {
                            Image(systemName: "fork.knife").font(.system(size: 14, weight: .bold)).foregroundStyle(C.brandHi)
                                .frame(width: 38, height: 38).background(Circle().fill(C.brand.opacity(0.16)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.name).font(F.round(16, .bold)).foregroundStyle(C.creme).lineLimit(1)
                                Text("P \(Int(e.protein.rounded()))g  \u{00B7}  C \(Int(e.carbs.rounded()))g  \u{00B7}  F \(Int(e.fat.rounded()))g")
                                    .font(F.round(12, .semibold)).foregroundStyle(C.muted)
                            }
                            Spacer(minLength: 0)
                            Text("\(e.kcal)").font(F.round(16, .bold)).foregroundStyle(C.creme)
                            Text("kcal").font(F.round(12, .semibold)).foregroundStyle(C.muted)
                            if isToday {
                                Button { lab.remove(e) } label: {
                                    Image(systemName: "xmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(C.muted)
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(e.name)")
                            }
                        }
                        .padding(.leading, 12).padding(.trailing, isToday ? 0 : 12).padding(.vertical, isToday ? 2 : 10)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(C.char800)
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(C.line, lineWidth: 1)))
                    }
                }
            }
        }
    }

    // MARK: coach tip

    /// One line of advice from today's numbers: the biggest gap, and food that closes it.
    private func tip(_ d: FuelDay, _ goal: FuelTargets) -> some View {
        let hour = Calendar.current.component(.hour, from: Date())
        let proteinLeft = goal.protein - Int(d.protein.rounded())
        let carbsLeft = goal.carbs - Int(d.carbs.rounded())
        let kcalLeft = goal.kcal - d.kcal
        var text = "You're on track today. Keep the water going."
        var icon = "checkmark.seal.fill"
        if d.entries.isEmpty {
            text = hour < 11 ? "Start with breakfast. Oats, a banana and milk give you energy for the day."
                             : "Nothing logged yet. Add what you've eaten so your targets mean something."
            icon = "sunrise.fill"
        } else if kcalLeft < -200 {
            text = "You're past your target. That's fine on a heavy training day; ease off the snacks tonight."
            icon = "exclamationmark.circle.fill"
        } else if d.water < goal.water / 2 && hour >= 14 {
            text = "You're behind on water. Have two glasses now and one with each meal."
            icon = "drop.fill"
        } else if proteinLeft > 40 {
            text = "You're \(proteinLeft) g short on protein. A chicken breast and a yogurt would cover most of it."
            icon = "dumbbell.fill"
        } else if carbsLeft > 120 && hour < 18 {
            text = "You have \(carbsLeft) g of carbs left. Rice, pasta or bread before training will top you up."
            icon = "bolt.fill"
        }
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 15, weight: .bold)).foregroundStyle(C.brandHi)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(C.brand.opacity(0.18)))
            VStack(alignment: .leading, spacing: 3) {
                Text("COACH TIP").font(F.round(11, .bold)).kerning(1.4).foregroundStyle(C.brandHi)
                Text(text).font(F.round(14, .medium)).foregroundStyle(C.creme)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(C.brand.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(C.brand.opacity(0.35), lineWidth: 1))
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: meal plans

    private var mealPlans: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Meal plans").font(.system(size: 18, weight: .bold)).foregroundStyle(C.creme)
                Text(isToday ? "Pick the moment. One tap logs the whole plan." : "Pick today to log a plan.")
                    .font(F.round(13, .medium)).foregroundStyle(C.muted)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(MealPlan.categories, id: \.self) { c in
                        let on = c == planCategory
                        Button { planCategory = c; Haptics.play(.stud) } label: {
                            Label(c, systemImage: MealPlan.icon(c))
                                .font(F.round(13, .semibold))
                                .foregroundStyle(on ? Color.white : C.creme2)
                                .padding(.horizontal, 14).frame(height: 38)
                                .background(Capsule().fill(on ? C.brand : C.char800).overlay(Capsule().stroke(on ? Color.clear : C.line, lineWidth: 1)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden)
            VStack(spacing: 10) {
                ForEach(MealPlan.all.filter { $0.category == planCategory }) { m in planRow(m) }
            }
        }
    }

    private func planRow(_ m: MealPlan) -> some View {
        let tint = MealPlan.tint(m.category)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: m.icon).font(.system(size: 16, weight: .bold)).foregroundStyle(tint)
                    .frame(width: 42, height: 42)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.16)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(m.name).font(F.round(16, .semibold)).foregroundStyle(C.creme)
                    Text(m.when).font(F.round(12, .semibold)).foregroundStyle(tint)
                }
                Spacer(minLength: 0)
                if m.kcal > 0 {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(m.kcal)").font(.system(size: 16, weight: .bold)).foregroundStyle(C.creme)
                        Text("kcal").font(F.round(11, .semibold)).foregroundStyle(C.muted)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                ForEach(m.lines, id: \.self) { line in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(tint).frame(width: 5, height: 5).padding(.top, 6)
                        Text(line).font(F.round(13, .medium)).foregroundStyle(C.creme2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if m.kcal > 0 {
                HStack(spacing: 14) {
                    Text("P \(Int(m.protein.rounded()))g").foregroundStyle(labSkillColor("Stretching"))
                    Text("C \(Int(m.carbs.rounded()))g").foregroundStyle(C.gold)
                    Text("F \(Int(m.fat.rounded()))g").foregroundStyle(labSkillColor("Defending"))
                    if m.water > 0 { Label("\(m.water)", systemImage: "drop.fill").foregroundStyle(C.brandHi) }
                }
                .font(F.round(12, .bold))
            }
            if isToday {
                Button {
                    lab.eat(plan: m)
                    Haptics.play(.goal)
                } label: {
                    Label(m.kcal > 0 ? "Log this plan" : "Log \(m.water) glass\(m.water == 1 ? "" : "es") of water", systemImage: "plus")
                }
                .buttonStyle(.game(.charcoal, height: 42, font: 20))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [tint.opacity(0.08), C.char800], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(C.line, lineWidth: 1))
        )
    }
}

/// A ready-made plan for one moment of the football week: food from the list (logged together), glasses of water,
/// or both. Hydration plans are water and timing only.
struct MealPlan: Identifiable {
    let id: String
    let category: String
    let name: String
    let when: String
    let icon: String
    /// Names from Foods.all.
    let foods: [String]
    /// Glasses of water (250 ml) the plan adds.
    var water = 0
    /// Extra guidance shown under the foods (timing, what to avoid).
    var notes: [String] = []

    var items: [FoodItem] { foods.compactMap { n in Foods.all.first { $0.name == n } } }
    var kcal: Int { items.reduce(0) { $0 + $1.kcal } }
    var protein: Double { items.reduce(0) { $0 + $1.protein } }
    var carbs: Double { items.reduce(0) { $0 + $1.carbs } }
    var fat: Double { items.reduce(0) { $0 + $1.fat } }
    var lines: [String] { items.map { "\($0.name), \($0.serving)" } + notes }

    static let categories = ["Pre-match", "Recovery", "Training", "Snacks", "Hydration"]
    static func icon(_ c: String) -> String {
        switch c {
        case "Pre-match": return "bolt.fill"
        case "Recovery": return "arrow.triangle.2.circlepath"
        case "Training": return "figure.soccer"
        case "Snacks": return "leaf.fill"
        default: return "drop.fill"
        }
    }
    static func tint(_ c: String) -> Color {
        switch c {
        case "Pre-match": return labSkillColor("Runs")
        case "Recovery": return labSkillColor("Stretching")
        case "Training": return C.gold
        case "Snacks": return labSkillColor("Passing")
        default: return C.brandHi
        }
    }

    static let all: [MealPlan] = [
        MealPlan(id: "pre-main", category: "Pre-match", name: "Match-day plate", when: "3 to 4 hours before kick-off", icon: "bolt.fill",
                 foods: ["Pasta with tomato sauce", "Chicken breast", "Orange juice"], water: 2,
                 notes: ["Mostly carbs, some protein, little fat. Nothing new on match day."]),
        MealPlan(id: "pre-light", category: "Pre-match", name: "Light and early", when: "Morning kick-off", icon: "sunrise.fill",
                 foods: ["Oats", "Banana", "Bread"], water: 2,
                 notes: ["Finish eating at least 2 hours before you play."]),
        MealPlan(id: "pre-top", category: "Pre-match", name: "Top-up", when: "60 minutes before", icon: "timer",
                 foods: ["Banana", "Dates"], water: 1,
                 notes: ["Small and quick to digest. Skip it if your stomach feels full."]),

        MealPlan(id: "rec-meal", category: "Recovery", name: "Recovery meal", when: "Within 1 to 2 hours after", icon: "arrow.triangle.2.circlepath",
                 foods: ["Chicken and rice", "Cooked vegetables", "Chocolate milk"], water: 2,
                 notes: ["Carbs refill your legs, protein repairs them."]),
        MealPlan(id: "rec-fast", category: "Recovery", name: "Straight after", when: "In the first 30 minutes", icon: "clock.fill",
                 foods: ["Chocolate milk", "Banana"], water: 2,
                 notes: ["Easy to get down when you're not hungry yet."]),
        MealPlan(id: "rec-veg", category: "Recovery", name: "No-meat recovery", when: "Within 1 to 2 hours after", icon: "leaf.fill",
                 foods: ["Rice and beans", "Eggs", "Mixed salad"], water: 2),

        MealPlan(id: "tr-breakfast", category: "Training", name: "Training breakfast", when: "Morning of a session", icon: "sunrise.fill",
                 foods: ["Oats", "Eggs", "Orange juice"], water: 1),
        MealPlan(id: "tr-lunch", category: "Training", name: "Training-day lunch", when: "3 hours before training", icon: "fork.knife",
                 foods: ["Chicken wrap", "Apple", "Greek yogurt"], water: 2),
        MealPlan(id: "tr-dinner", category: "Training", name: "Training-day dinner", when: "After an evening session", icon: "moon.fill",
                 foods: ["Salmon", "Potato", "Cooked vegetables"], water: 2),
        MealPlan(id: "tr-rest", category: "Training", name: "Rest-day plate", when: "No training today", icon: "bed.double.fill",
                 foods: ["Omelette", "Mixed salad", "Bread"], water: 1,
                 notes: ["A little lighter on carbs, the same protein."]),

        MealPlan(id: "sn-energy", category: "Snacks", name: "Quick energy", when: "30 to 60 minutes before", icon: "bolt.fill",
                 foods: ["Banana", "Granola bar"]),
        MealPlan(id: "sn-protein", category: "Snacks", name: "Protein snack", when: "Between meals", icon: "dumbbell.fill",
                 foods: ["Greek yogurt", "Mixed nuts"]),
        MealPlan(id: "sn-half", category: "Snacks", name: "Half-time", when: "At the break", icon: "pause.circle.fill",
                 foods: ["Orange", "Dates"], water: 1,
                 notes: ["Small bites and a few sips. Not a meal."]),
        MealPlan(id: "sn-bed", category: "Snacks", name: "Before bed", when: "After a late game", icon: "moon.stars.fill",
                 foods: ["Milk", "Peanut butter toast"]),

        MealPlan(id: "hy-match", category: "Hydration", name: "Match-day water", when: "From waking up to kick-off", icon: "drop.fill",
                 foods: [], water: 4,
                 notes: ["Two glasses with breakfast.", "One glass 2 hours before.", "One glass in the warm-up, in sips."]),
        MealPlan(id: "hy-during", category: "Hydration", name: "During the game", when: "Breaks and half-time", icon: "pause.circle.fill",
                 foods: [], water: 2,
                 notes: ["A few mouthfuls at every break.", "On a hot day, add a sports drink at half-time."]),
        MealPlan(id: "hy-after", category: "Hydration", name: "After the whistle", when: "In the 2 hours after", icon: "arrow.triangle.2.circlepath",
                 foods: [], water: 3,
                 notes: ["Drink steadily, not all at once.", "Pale yellow urine means you've caught up."]),
        MealPlan(id: "hy-daily", category: "Hydration", name: "Everyday habit", when: "Any day", icon: "calendar",
                 foods: [], water: 1,
                 notes: ["A glass when you wake up.", "A glass with every meal.", "Keep a bottle in your bag."]),
    ]
}

// MARK: - add food

struct FoodSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var lab = Lab.shared
    /// "Recent" when the player has logged list foods before, else the first group.
    @State private var group = Lab.shared.recentFoods.isEmpty ? Foods.groups[0] : "Recent"
    @State private var query = ""
    @State private var scanning = false
    @State private var addedNow: [String: Int] = [:]
    @State private var custom = false
    @State private var name = ""
    @State private var kcal = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""

    private var kcalValue: Int? { Int(kcal.trimmingCharacters(in: .whitespaces)) }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (kcalValue ?? 0) > 0 && (kcalValue ?? 0) <= 5000
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Disp("ADD FOOD", size: 30)
                    Spacer()
                    Button("Done") { dismiss() }.font(F.round(16, .bold)).foregroundStyle(C.brandHi)
                }
                .padding(.top, 24)

                FoodScanCard { scanning = true }

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(C.muted)
                    TextField("Search foods: biryani, eggs, banana…", text: $query)
                        .font(F.round(16, .semibold)).foregroundStyle(C.creme)
                        .autocorrectionDisabled()
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(C.muted) }
                            .buttonStyle(.plain).accessibilityLabel("Clear search")
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(C.char950))

                if query.isEmpty { ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach((lab.recentFoods.isEmpty ? [] : ["Recent"]) + Foods.groups + ["My own"], id: \.self) { g in
                            let on = custom ? g == "My own" : g == group
                            Button(g) {
                                if g == "My own" { custom = true } else { custom = false; group = g }
                            }
                            .font(F.round(14, .bold))
                            .foregroundStyle(on ? Color.white : C.creme2)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(Capsule().fill(on ? C.brand : C.char800))
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden) }

                if custom && query.isEmpty { ownEntry } else { list }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .presentationDetents([.large])
        .presentationBackground(C.char900)
        .sheet(isPresented: $scanning) { FoodScanSheet() }
    }

    /// What the list shows: search results (every word must match), the recent foods, or one group.
    private var shown: [FoodItem] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        if !words.isEmpty {
            return Foods.all.filter { f in
                let hay = (f.name + " " + f.group + " " + f.serving).lowercased()
                return words.allSatisfy { hay.contains($0) }
            }
        }
        if group == "Recent" { return lab.recentFoods }
        return Foods.all.filter { $0.group == group }
    }

    private var list: some View {
        VStack(spacing: 8) {
            if shown.isEmpty {
                Text(query.isEmpty ? "Nothing here yet." : "No food called that. Try another word, scan it, or add it under My own.")
                    .font(F.round(14, .semibold)).foregroundStyle(C.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(shown) { f in
                let n = addedNow[f.name] ?? 0
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.name).font(F.round(16, .bold)).foregroundStyle(C.creme)
                        Text("\(f.serving) · \(f.kcal) kcal · \(Int(f.protein)) g protein")
                            .font(F.round(13, .semibold)).foregroundStyle(C.muted)
                    }
                    Spacer(minLength: 0)
                    if n > 0 { Text("+\(n)").font(F.round(14, .bold)).foregroundStyle(C.brandHi) }
                    Button {
                        lab.eat(f)
                        addedNow[f.name] = n + 1
                        Haptics.play(.pop)
                    } label: {
                        Image(systemName: "plus").font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)
                            .frame(width: 44, height: 44).background(Circle().fill(C.brand))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add \(f.name)")
                }
                .padding(.vertical, 8).padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(C.char800))
            }
        }
    }

    private var ownEntry: some View {
        VStack(alignment: .leading, spacing: 12) {
            field("Name", "Grandma's stew", $name, numbers: false)
            field("Calories (kcal)", "450", $kcal, numbers: true)
            HStack(spacing: 10) {
                field("Protein g", "25", $protein, numbers: true)
                field("Carbs g", "50", $carbs, numbers: true)
                field("Fat g", "15", $fat, numbers: true)
            }
            Text("Protein, carbs and fat are optional.").font(F.round(13, .semibold)).foregroundStyle(C.muted)
            Button("ADD IT") {
                lab.eat(custom: String(name.trimmingCharacters(in: .whitespaces).prefix(40)), kcal: kcalValue ?? 0,
                        protein: grams(protein), carbs: grams(carbs), fat: grams(fat))
                Haptics.play(.goal)
                name = ""; kcal = ""; protein = ""; carbs = ""; fat = ""
            }
            .buttonStyle(.game(.brand))
            .disabled(!canSave)
        }
    }

    private func grams(_ s: String) -> Double {
        let v = Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) ?? 0
        return min(500, max(0, v))
    }

    private func field(_ label: String, _ hint: String, _ text: Binding<String>, numbers: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(F.round(13, .bold)).foregroundStyle(C.creme2)
            TextField(hint, text: text)
                .keyboardType(numbers ? .decimalPad : .default)
                .font(F.round(16, .semibold)).foregroundStyle(C.creme)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(C.char950))
        }
    }
}

// MARK: - the numbers the targets come from

struct FuelBodySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    @State private var lab = Lab.shared
    @State private var goal: String? = nil
    @State private var weight = 60.0
    @State private var height = 170.0
    @State private var age = 16
    @State private var days = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Disp("MY DETAILS", size: 30).padding(.top, 24)
            Text("Used only to work out your targets. They stay on this phone.")
                .font(F.round(14, .semibold)).foregroundStyle(C.muted)
            row("Weight", "\(Int(weight)) kg") { Stepper("Weight", value: $weight, in: 30...150, step: 1).labelsHidden() }
            row("Height", "\(Int(height)) cm") { Stepper("Height", value: $height, in: 120...220, step: 1).labelsHidden() }
            row("Age", "\(age)") { Stepper("Age", value: $age, in: 13...60).labelsHidden() }
            row("Training days a week", "\(days)") { Stepper("Training days", value: $days, in: 0...7).labelsHidden() }
            VStack(alignment: .leading, spacing: 8) {
                Text("Food goal").font(F.round(14, .bold)).foregroundStyle(C.creme2)
                Picker("Food goal", selection: $goal) {
                    ForEach(["Build muscle", "Stay lean and fast", "More energy for games", "Just eat better"], id: \.self) { Text($0).tag(Optional($0)) }
                }
                .pickerStyle(.menu).tint(C.brandHi)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(C.char800))
            Spacer()
            Button("SAVE") {
                lab.body = FuelBody(weightKg: weight, heightCm: height, age: age, trainingDays: days,
                                    goal: goal, position: lab.body.position ?? store.answers.position)
                Haptics.play(.goal)
                dismiss()
            }
            .buttonStyle(.gameLarge(.brand, feel: .kick))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .presentationDetents([.large])
        .presentationBackground(C.char900)
        .onAppear {
            let b = lab.body
            if b.isSet { weight = b.weightKg; height = b.heightCm; age = b.age }
            days = b.trainingDays
            goal = b.goal ?? store.answers.fuelGoal ?? "Just eat better"
        }
    }

    private func row<S: View>(_ label: String, _ value: String, @ViewBuilder stepper: () -> S) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(F.round(14, .bold)).foregroundStyle(C.creme2)
                Text(value).font(F.round(20, .bold)).foregroundStyle(C.creme)
            }
            Spacer()
            stepper()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(C.char800))
    }
}
