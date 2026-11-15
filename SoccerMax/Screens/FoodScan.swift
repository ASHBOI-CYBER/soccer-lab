// FOOD PHOTO SCAN (2026-11-15). Take or pick a photo of a meal; the photo (made small) goes to
// supabase/functions/food-scan (Claude), which names each food with a portion and its calories, protein, carbs and fat.
// The player checks the list - untick what's wrong, change portions - and only then is anything logged.
// Needs sign-in and the AI yes (AIVision.swift); a daily allowance. The photo isn't kept anywhere.
import PhotosUI
import SwiftUI

struct FoodScanSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var lab = Lab.shared

    private enum Stage { case pick, scanning, review }
    @State private var stage: Stage = .pick
    @State private var camera = false
    @State private var item: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var note = ""
    @State private var error: String?
    @State private var scan: FoodScanResult?
    /// Per food (by index): logged or not, and how many portions.
    @State private var keep: [Int: Bool] = [:]
    @State private var amount: [Int: Double] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Disp("SCAN FOOD", size: 30)
                    Spacer()
                    Button("Close") { dismiss() }.font(F.round(16, .bold)).foregroundStyle(C.muted)
                }
                .padding(.top, 24)

                if let photo {
                    Image(uiImage: photo).resizable().scaledToFill()
                        .frame(height: 200).frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .accessibilityLabel("Your meal photo")
                }

                switch stage {
                case .pick: pick
                case .scanning: scanning
                case .review: review
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .presentationDetents([.large])
        .presentationBackground(C.char900)
        .interactiveDismissDisabled(stage == .scanning)
        .onAppear {
            #if DEBUG
            if DebugRoute.parts.contains("scan"), scan == nil { scan = .demo; stage = .review }   // screenshots only
            #endif
        }
        .fullScreenCover(isPresented: $camera) {
            CameraPicker { img in
                camera = false
                if let img { use(img) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: item) { _, new in
            guard let new else { return }
            Task {
                if let d = try? await new.loadTransferable(type: Data.self), let img = UIImage(data: d) { use(img) } else {
                    error = "That photo couldn't be opened. Try another one."
                }
                item = nil
            }
        }
    }

    // 1. the photo

    private var pick: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Take a photo of your plate. The AI names each food and counts the calories, protein, carbs and fat. You check it before anything is added.")
                .font(F.round(15, .semibold)).foregroundStyle(C.creme2)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                LabKicker("ANYTHING TO ADD? (OPTIONAL)")
                TextField("I only ate half", text: $note)
                    .font(F.round(16, .semibold)).foregroundStyle(C.creme)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(C.char950))
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(F.round(14, .semibold)).foregroundStyle(C.gold)
                    .fixedSize(horizontal: false, vertical: true)
            }
            AIGate(what: "food scans", onNo: { dismiss() }) {
                VStack(spacing: 10) {
                    Button { camera = true } label: { Label("TAKE A PHOTO", systemImage: "camera.fill") }
                        .buttonStyle(.gameLarge(.brand, feel: .kick))
                    PhotosPicker(selection: $item, matching: .images) {
                        Label("Choose from Photos", systemImage: "photo.on.rectangle")
                            .font(F.round(16, .bold)).foregroundStyle(C.brandHi)
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(C.char800))
                    }
                    Text(AIUsage.shared.line("food")).font(F.round(13, .semibold)).foregroundStyle(C.muted)
                }
            }
        }
    }

    // 2. working

    private var scanning: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large).tint(C.brandHi)
            Text("Looking at your meal…").font(F.round(16, .bold)).foregroundStyle(C.creme)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    // 3. check and log

    private var review: some View {
        let items = scan?.items ?? []
        let chosen = items.indices.filter { keep[$0] ?? true }
        let kcal = chosen.reduce(0.0) { $0 + Double(items[$1].kcal) * (amount[$1] ?? 1) }
        let protein = chosen.reduce(0.0) { $0 + items[$1].protein * (amount[$1] ?? 1) }
        return VStack(alignment: .leading, spacing: 14) {
            if let s = scan, !s.message.isEmpty {
                Label(s.message, systemImage: s.is_food ? "sparkles" : "questionmark.circle.fill")
                    .font(F.round(15, .semibold)).foregroundStyle(s.is_food ? C.creme2 : C.gold)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if items.isEmpty {
                Button("TRY ANOTHER PHOTO") { reset() }.buttonStyle(.game(.brand))
            } else {
                LabKicker("CHECK IT, THEN ADD")
                ForEach(items.indices, id: \.self) { i in row(items[i], i) }
                HStack {
                    Text("Total").font(F.round(15, .bold)).foregroundStyle(C.creme2)
                    Spacer()
                    Text("\(Int(kcal.rounded())) kcal · \(Int(protein.rounded())) g protein")
                        .font(F.round(15, .bold)).foregroundStyle(C.creme).monospacedDigit()
                }
                Button("ADD TO TODAY") { log(items) }
                    .buttonStyle(.gameLarge(.brand, feel: .goal))
                    .disabled(chosen.isEmpty)
                Button("Scan again") { reset() }
                    .font(F.round(15, .bold)).foregroundStyle(C.muted).frame(maxWidth: .infinity)
                Text("Numbers are estimates from the photo. Change the portions if they look wrong.")
                    .font(F.round(12, .medium)).foregroundStyle(C.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(_ f: FoodScanItem, _ i: Int) -> some View {
        let on = keep[i] ?? true
        let x = amount[i] ?? 1
        return HStack(spacing: 10) {
            Button {
                keep[i] = !on
                Haptics.play(.stud)
            } label: {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24, weight: .bold)).foregroundStyle(on ? C.brand : C.char600)
                    .frame(width: 36, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(on ? "Remove \(f.name)" : "Keep \(f.name)")
            VStack(alignment: .leading, spacing: 2) {
                Text(f.name).font(F.round(16, .bold)).foregroundStyle(on ? C.creme : C.muted)
                Text("\(portionText(x, f.portion)) · \(Int((Double(f.kcal) * x).rounded())) kcal · \(Int((f.protein * x).rounded())) g protein")
                    .font(F.round(13, .semibold)).foregroundStyle(C.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Menu {
                ForEach([0.5, 1, 1.5, 2, 3], id: \.self) { v in
                    Button(v == 1 ? "As shown" : "× \(v.formatted())") { amount[i] = v }
                }
            } label: {
                Text("×\(x.formatted())").font(F.round(14, .bold)).foregroundStyle(C.brandHi)
                    .padding(.horizontal, 10).frame(height: 34)
                    .background(Capsule().fill(C.brand.opacity(0.14)))
            }
            .disabled(!on)
        }
        .padding(.vertical, 6).padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(C.char800))
    }

    private func portionText(_ x: Double, _ portion: String) -> String {
        x == 1 ? portion : "\(x.formatted())× \(portion)"
    }

    private func use(_ img: UIImage) {
        photo = img
        error = nil
        guard let jpg = PhotoPrep.jpeg(img) else {
            error = "That photo couldn't be read. Try another one."
            return
        }
        withAnimation(.snappy) { stage = .scanning }
        Task {
            do {
                struct Reply: Decodable { let scan: FoodScanResult }
                var body: [String: Any] = ["photo": jpg.base64EncodedString()]
                let n = note.trimmingCharacters(in: .whitespacesAndNewlines)
                if !n.isEmpty { body["note"] = String(n.prefix(200)) }
                let r = try await AICall.post("food-scan", body, kind: "food", as: Reply.self)
                scan = r.scan
                keep = [:]
                amount = [:]
                Haptics.play(.pop)
                withAnimation(.snappy) { stage = .review }
            } catch let e as AICall.Failure {
                error = e.message
                withAnimation(.snappy) { stage = .pick }
            } catch {
                self.error = "Something went wrong. Try again."
                withAnimation(.snappy) { stage = .pick }
            }
        }
    }

    private func log(_ items: [FoodScanItem]) {
        for i in items.indices where keep[i] ?? true {
            let f = items[i], x = amount[i] ?? 1
            lab.eat(custom: String(f.name.prefix(40)), kcal: Int((Double(f.kcal) * x).rounded()),
                    protein: f.protein * x, carbs: f.carbs * x, fat: f.fat * x)
        }
        Haptics.play(.goal)
        dismiss()
    }

    private func reset() {
        photo = nil
        scan = nil
        error = nil
        withAnimation(.snappy) { stage = .pick }
    }
}

/// The Fuel tab's scan card: one tap to the camera.
struct FoodScanCard: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(LinearGradient(colors: [C.brandHi, C.brand], startPoint: .topLeading, endPoint: .bottomTrailing)))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Scan your plate").font(F.round(17, .bold)).foregroundStyle(C.creme)
                        Text("AI").font(F.round(11, .heavy)).foregroundStyle(C.brandInk)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(C.brandHi))
                    }
                    Text("Photo in, calories and protein out. \(AIUsage.shared.line("food")).")
                        .font(F.round(13, .semibold)).foregroundStyle(C.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .heavy)).foregroundStyle(C.muted)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(C.char800)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(C.brand.opacity(0.45), lineWidth: 1)))
        }
        .buttonStyle(.plain)
    }
}
