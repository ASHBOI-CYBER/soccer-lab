// NUTRITION tab (SOCCER LAB, 2026-11-12). A manual fuel log: daily targets from the player's own numbers
// (FuelTargets in LabData.swift), quick-add from a list of common foods, your own entries, and water. Everything
// stays on the phone. It is about eating enough to train and recover: there is no weight-loss mode.
import SwiftUI

struct NutritionTab: View {
    @State private var lab = Lab.shared
    @State private var adding = false
    @State private var editingBody = false

    var body: some View {
        let day = lab.fuelToday
        let goal = lab.targets
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    TabHeader("Nutrition")
                    energy(day, goal)
                    water(day, goal)
                    Button { adding = true } label: { Label("ADD FOOD", systemImage: "plus") }
                        .buttonStyle(.game(.brand))
                    log(day)
                    details
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .tabRoot("Nutrition")
            .page()
        }
        .sheet(isPresented: $adding) { FoodSheet() }
        .sheet(isPresented: $editingBody) { FuelBodySheet() }
    }

    private func energy(_ day: FuelDay, _ goal: FuelTargets) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LabKicker("TODAY'S FUEL")
            LabPanel {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 16) {
                        LabRing(value: Double(day.kcal), goal: Double(goal.kcal), width: 12) {
                            VStack(spacing: 0) {
                                Disp("\(day.kcal)", size: 26)
                                Text("kcal").font(F.round(12, .bold)).foregroundStyle(C.muted)
                            }
                        }
                        .frame(width: 112, height: 112)
                        VStack(alignment: .leading, spacing: 6) {
                            let left = goal.kcal - day.kcal
                            Text(left > 0 ? "\(left) kcal to go" : "Target reached")
                                .font(F.round(19, .bold)).foregroundStyle(C.creme)
                            Text("Today's target is \(goal.kcal) kcal")
                                .font(F.round(14, .semibold)).foregroundStyle(C.muted)
                            Label(day.entries.isEmpty ? "Nothing logged yet" : "\(day.entries.count) logged today", systemImage: "fork.knife")
                                .font(F.round(13, .bold)).foregroundStyle(C.brandHi)
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                    macro("Protein", day.protein, goal.protein, labSkillColor("Shooting"))
                    macro("Carbs", day.carbs, goal.carbs, C.gold)
                    macro("Fat", day.fat, goal.fat, labSkillColor("Passing"))
                }
            }
        }
    }

    private func macro(_ name: String, _ value: Double, _ goal: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(name).font(F.round(15, .bold)).foregroundStyle(C.creme)
                Spacer()
                Text("\(Int(value.rounded())) of \(goal) g").font(F.round(14, .semibold)).foregroundStyle(C.muted)
            }
            LabBar(value: value, goal: Double(goal), color: color)
        }
        .accessibilityElement(children: .combine)
    }

    private func water(_ day: FuelDay, _ goal: FuelTargets) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LabKicker("WATER")
            LabPanel {
                HStack(spacing: 14) {
                    Image(systemName: "drop.fill").font(.system(size: 24, weight: .bold)).foregroundStyle(C.brandHi)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(day.water) of \(goal.water) glasses").font(F.round(16, .bold)).foregroundStyle(C.creme)
                        LabBar(value: Double(day.water), goal: Double(goal.water), color: C.brandHi)
                    }
                    Button { lab.water(-1); Haptics.play(.stud) } label: {
                        Image(systemName: "minus").font(.system(size: 16, weight: .heavy)).foregroundStyle(C.creme)
                            .frame(width: 44, height: 44).background(Circle().fill(C.char700))
                    }
                    .buttonStyle(.plain)
                    .disabled(day.water == 0)
                    .accessibilityLabel("One glass less")
                    Button { lab.water(1); Haptics.play(.pop) } label: {
                        Image(systemName: "plus").font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)
                            .frame(width: 44, height: 44).background(Circle().fill(C.brand))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add a glass of water")
                }
            }
        }
    }

    private func log(_ day: FuelDay) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LabKicker("EATEN TODAY")
            if day.entries.isEmpty {
                Text("Nothing logged yet. Add your first meal.")
                    .font(F.round(15, .semibold)).foregroundStyle(C.muted)
            } else {
                VStack(spacing: 8) {
                    ForEach(day.entries.reversed()) { e in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.name).font(F.round(16, .bold)).foregroundStyle(C.creme).lineLimit(1)
                                Text("\(e.kcal) kcal · P \(Int(e.protein.rounded())) · C \(Int(e.carbs.rounded())) · F \(Int(e.fat.rounded()))")
                                    .font(F.round(13, .semibold)).foregroundStyle(C.muted)
                            }
                            Spacer(minLength: 0)
                            Button { lab.remove(e) } label: {
                                Image(systemName: "xmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(C.muted)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(e.name)")
                        }
                        .padding(.leading, 12)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(C.char800))
                    }
                }
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabKicker("YOUR TARGETS")
            Text(lab.body.isSet
                 ? "Worked out from your weight, height, age and training days."
                 : "These are typical targets. Add your details to get your own.")
                .font(F.round(14, .semibold)).foregroundStyle(C.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button(lab.body.isSet ? "CHANGE MY DETAILS" : "ADD MY DETAILS") { editingBody = true }
                .buttonStyle(.game(.charcoal, height: 50, font: 19))
            Text("A general guide for active players, not medical advice. If you have a health condition, follow your doctor.")
                .font(F.round(12, .semibold)).foregroundStyle(C.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
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
