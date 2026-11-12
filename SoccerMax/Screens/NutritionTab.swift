// NUTRITION tab (SOCCER LAB, 2026-11-12). A manual fuel log: daily targets from the player's own numbers
// (FuelTargets in LabData.swift), quick-add from a list of common foods, your own entries, and water. Everything
// stays on the phone. It is about eating enough to train and recover: there is no weight-loss mode.
import SwiftUI

struct NutritionTab: View {
    @State private var lab = Lab.shared
    @State private var adding = false
    @State private var editingBody = false
    /// The day being looked at ("Mon"..."Sun" of this week); today when the tab opens.
    @State private var day = todayKey()

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
                    calories(d, goal)
                    macros(d, goal)
                    water(d, goal)
                    meals(d)
                    if isToday { quickMeals }
                    Text("A general guide for active players, not medical advice. If you have a health condition, follow your doctor.")
                        .font(F.round(12, .medium)).foregroundStyle(C.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 110)
            }
            .scrollIndicators(.hidden)
            .tabRoot("Nutrition")
            .page()
            .overlay(alignment: .bottomTrailing) {
                if isToday {
                    Button { adding = true } label: {
                        Image(systemName: "plus").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 54, height: 54)
                            .background(Circle().fill(LinearGradient(colors: [C.brand, C.brandMid], startPoint: .top, endPoint: .bottom)))
                            .shadow(color: C.brand.opacity(0.45), radius: 12, y: 3)
                    }
                    .buttonStyle(.press(.pop))
                    .padding(.trailing, 20).padding(.bottom, 16)
                    .accessibilityLabel("Add food")
                }
            }
        }
        .sheet(isPresented: $adding) { FoodSheet() }
        .sheet(isPresented: $editingBody) { FuelBodySheet() }
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
            Text(isToday ? "Today's meals" : "\(FULL_DAY[day]?.capitalized ?? day)'s meals")
                .font(.system(size: 20, weight: .heavy)).foregroundStyle(C.creme)
            if d.entries.isEmpty {
                LabPanel(padding: 22) {
                    VStack(spacing: 10) {
                        Image(systemName: "fork.knife").font(.system(size: 22, weight: .bold)).foregroundStyle(C.brandHi)
                            .frame(width: 60, height: 60)
                            .background(Circle().fill(C.brand.opacity(0.16)))
                            .shadow(color: C.brand.opacity(0.5), radius: 14)
                        Text(isToday ? "No meals logged yet" : "Nothing was logged").font(F.round(17, .bold)).foregroundStyle(C.creme)
                        Text(isToday ? "Add what you eat, or log a ready-made meal in one tap." : "Pick today to log food.")
                            .font(F.round(14, .medium)).foregroundStyle(C.muted).multilineTextAlignment(.center)
                        if isToday {
                            Button { adding = true } label: { Label("Add food", systemImage: "plus") }
                                .buttonStyle(.game(.brand, height: 46, font: 22, block: false))
                                .padding(.top, 4)
                        }
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

    // MARK: quick meals

    private var quickMeals: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Quick meals").font(.system(size: 20, weight: .heavy)).foregroundStyle(C.creme)
                Text("Built for training days. One tap logs the whole meal.").font(F.round(13, .medium)).foregroundStyle(C.muted)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(QuickMeal.all) { m in
                        Button {
                            lab.eat(meal: m)
                            Haptics.play(.goal)
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                Image(systemName: m.icon).font(.system(size: 17, weight: .bold)).foregroundStyle(m.tint)
                                    .frame(width: 42, height: 42)
                                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(m.tint.opacity(0.16)))
                                Text(m.name).font(F.round(16, .bold)).foregroundStyle(C.creme)
                                Text(m.when).font(F.round(12, .semibold)).foregroundStyle(m.tint)
                                Text(m.foods.joined(separator: ", ")).font(F.round(12, .medium)).foregroundStyle(C.muted)
                                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                HStack {
                                    Text("\(m.kcal) kcal").font(F.round(13, .bold)).foregroundStyle(C.creme2)
                                    Spacer()
                                    Image(systemName: "plus.circle.fill").font(.system(size: 22, weight: .bold)).foregroundStyle(C.brand)
                                }
                            }
                            .padding(14)
                            .frame(width: 190, height: 214, alignment: .topLeading)
                            .background(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(LinearGradient(colors: [m.tint.opacity(0.10), C.char800], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(C.line, lineWidth: 1))
                            )
                        }
                        .buttonStyle(.press(.stud))
                        .accessibilityLabel("Log \(m.name): \(m.foods.joined(separator: ", ")), \(m.kcal) calories")
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}

/// A ready-made meal: a few items from the food list, logged together.
struct QuickMeal: Identifiable {
    let id: String
    let name: String
    let when: String
    let icon: String
    let tint: Color
    let foods: [String]

    var items: [FoodItem] { foods.compactMap { n in Foods.all.first { $0.name == n } } }
    var kcal: Int { items.reduce(0) { $0 + $1.kcal } }

    static let all: [QuickMeal] = [
        QuickMeal(id: "breakfast", name: "Training breakfast", when: "Morning of a session", icon: "sunrise.fill", tint: C.gold,
                  foods: ["Oats", "Banana", "Milk"]),
        QuickMeal(id: "pre", name: "Pre-match plate", when: "3 hours before kick-off", icon: "bolt.fill", tint: labSkillColor("Runs"),
                  foods: ["Pasta with tomato sauce", "Chicken breast", "Orange juice"]),
        QuickMeal(id: "post", name: "Recovery meal", when: "Within an hour after", icon: "arrow.triangle.2.circlepath", tint: labSkillColor("Stretching"),
                  foods: ["Chicken and rice", "Chocolate milk"]),
        QuickMeal(id: "snack", name: "Half-time style snack", when: "Quick energy", icon: "leaf.fill", tint: labSkillColor("Passing"),
                  foods: ["Banana", "Granola bar"]),
        QuickMeal(id: "rest", name: "Rest day dinner", when: "Lighter on carbs", icon: "moon.fill", tint: labSkillColor("Defending"),
                  foods: ["Salmon", "Potato", "Cooked vegetables"]),
    ]
}

// MARK: - add food

struct FoodSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var lab = Lab.shared
    @State private var group = Foods.groups[0]
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

                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Foods.groups + ["My own"], id: \.self) { g in
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
                .scrollIndicators(.hidden)

                if custom { ownEntry } else { list }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .presentationDetents([.large])
        .presentationBackground(C.char900)
    }

    private var list: some View {
        VStack(spacing: 8) {
            ForEach(Foods.all.filter { $0.group == group }) { f in
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
    @State private var lab = Lab.shared
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
            Spacer()
            Button("SAVE") {
                lab.body = FuelBody(weightKg: weight, heightCm: height, age: age, trainingDays: days)
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
