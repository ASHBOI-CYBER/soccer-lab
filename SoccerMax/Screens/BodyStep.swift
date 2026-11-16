// ONBOARDING: age, height and weight (2026-11-17). Three scroll wheels side by side, metric or imperial. Saved in the
// onboarding answers; at the end of onboarding they become the player's fuel targets (Lab.setBody, LabData.swift),
// so nobody gets the same 2,400 kcal. Stays on the phone.
import SwiftUI

struct BodyStep: View {
    let ctx: OBContext
    @Environment(AppStore.self) private var store
    @State private var age = 16
    @State private var cm = 170
    @State private var kg = 60
    @State private var metric = Locale.current.measurementSystem != .us

    var body: some View {
        OBShell(ctx: ctx, title: "Your age, height and weight",
                sub: Text("We use these to work out your daily calories and protein. They stay on your phone."),
                onNext: save, scrolls: false) {
            VStack(spacing: 16) {
                Picker("Units", selection: $metric) {
                    Text("cm · kg").tag(true)
                    Text("ft · lb").tag(false)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 30)

                HStack(spacing: 8) {
                    wheel("AGE") {
                        Picker("Age", selection: $age) { ForEach(8...60, id: \.self) { Text("\($0)").tag($0) } }
                    }
                    wheel("HEIGHT") {
                        Picker("Height", selection: $cm) {
                            ForEach(120...215, id: \.self) { c in Text(metric ? "\(c) cm" : feet(c)).tag(c) }
                        }
                    }
                    wheel("WEIGHT") {
                        Picker("Weight", selection: $kg) {
                            ForEach(25...150, id: \.self) { k in Text(metric ? "\(k) kg" : "\(Int((Double(k) * 2.20462).rounded())) lb").tag(k) }
                        }
                    }
                }
            }
            .onAppear(perform: load)
        }
    }

    private func wheel<P: View>(_ label: String, @ViewBuilder _ picker: () -> P) -> some View {
        VStack(spacing: 4) {
            Text(label).font(F.round(12, .heavy)).kerning(1).foregroundStyle(C.muted)
            picker()
                .pickerStyle(.wheel)
                .frame(height: 170)
                .clipped()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(C.char800.opacity(0.85)))
    }

    private func feet(_ cm: Int) -> String {
        let inches = Int((Double(cm) / 2.54).rounded())
        return "\(inches / 12)′ \(inches % 12)″"
    }

    private func load() {
        let a = store.answers
        if let s = a.age, let n = Int(s) { age = n }
        if let h = a.heightCm { cm = Int(h.rounded()) }
        if let w = a.weightKg { kg = Int(w.rounded()) }
    }

    private func save() {
        store.answers.age = "\(age)"
        store.answers.heightCm = Double(cm)
        store.answers.weightKg = Double(kg)
        ctx.next()
    }
}
