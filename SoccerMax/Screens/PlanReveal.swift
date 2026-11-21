// The last steps of onboarding (2026-11-21).
//   AGREE   right after Welcome: the player confirms the basics (age, training safety, AI, terms) before anything else.
//           Ali: "one legal acknowledgment page which will pop at the start".
//   BUILD   after the account: a short "we're building your plan" sequence, a ring counting to 100% while each step
//           ticks off. It is a presentation of work the app really does (the plan comes from their answers).
//   READY   "your plan is ready": their position, level, goal, training days and the three skills the plan trains
//           first, then the paywall. Fasih: "making your plan and then paywall".
// Nothing here claims reviews, user counts or results the app doesn't have.
import SwiftUI

// MARK: - agree

struct AgreeStep: View {
    let ctx: OBContext
    @Environment(AppStore.self) private var store
    @State private var age = false
    @State private var safety = false
    @State private var terms = false

    var body: some View {
        OBShell(ctx: ctx, title: "Before you start", sub: Text("Please read and tick each one."),
                cta: "I agree", canNext: age && safety && terms,
                onNext: {
                    store.answers.agreedAt = Date()
                    ctx.next()
                }) {
            VStack(alignment: .leading, spacing: 12) {
                tick($age, "I'm 13 or older, or I use Soccer Lab with a parent or guardian's permission.")
                tick($safety, "I train at my own risk. I'll warm up, train in a safe space, and stop if anything hurts.")
                tick($terms, "I understand AI answers can be wrong and aren't medical or dietary advice, and I agree to the Terms of Use and Privacy Policy.")
                HStack(spacing: 18) {
                    Link("Terms of Use", destination: Legal.terms)
                    Link("Privacy Policy", destination: Legal.privacy)
                }
                .font(F.round(15, .bold)).foregroundStyle(C.brandHi)
                .padding(.top, 4)
            }
        }
    }

    private func tick(_ on: Binding<Bool>, _ text: String) -> some View {
        Button { on.wrappedValue.toggle(); Haptics.play(on.wrappedValue ? .pop : .unlatch) } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: on.wrappedValue ? "checkmark.square.fill" : "square")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(on.wrappedValue ? C.brand : C.muted)
                Text(text).font(F.round(16, .medium)).foregroundStyle(C.creme)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(C.char800)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(on.wrappedValue ? C.brand.opacity(0.6) : C.line, lineWidth: 1)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on.wrappedValue ? .isSelected : [])
    }
}

// MARK: - build

struct BuildPlanStep: View {
    let ctx: OBContext
    @Environment(AppStore.self) private var store
    @State private var progress = 0.0
    @State private var done = false

    private var steps: [String] {
        let a = store.answers
        return ["Reading your answers", "Looking at the \(a.positionName.lowercased()) role", "Picking your focus skills",
                "Building your drill list", "Planning your training week", "Setting the difficulty", "Locking in your plan"]
    }

    var body: some View {
        let n = store.answers.firstName
        let reached = Int(progress * Double(steps.count))
        VStack(spacing: 22) {
            Spacer(minLength: 20)
            ZStack {
                Circle().stroke(C.char800, lineWidth: 10)
                Circle().trim(from: 0, to: progress)
                    .stroke(LinearGradient(colors: [C.brandHi, C.brand], startPoint: .top, endPoint: .bottom),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if done {
                    VStack(spacing: 2) {
                        Image(systemName: "checkmark").font(.system(size: 44, weight: .heavy)).foregroundStyle(C.brandHi)
                        Text("READY").font(F.round(12, .heavy)).kerning(1.4).foregroundStyle(C.brandHi)
                    }
                } else {
                    Text("\(Int(progress * 100))%").font(.system(size: 44, weight: .heavy, design: .rounded))
                        .foregroundStyle(C.creme).monospacedDigit().contentTransition(.numericText())
                }
            }
            .frame(width: 170, height: 170)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(done ? "Your plan is ready" : "Building your plan, \(Int(progress * 100)) percent")
            VStack(spacing: 6) {
                (Text("\(n), ").foregroundStyle(C.brandHi) + Text("we're building your plan").foregroundStyle(C.creme))
                    .font(.system(size: 24, weight: .bold)).multilineTextAlignment(.center)
                Text(done ? "All set." : steps[min(reached, steps.count - 1)] + "…")
                    .font(F.round(15, .semibold)).foregroundStyle(C.brandHi)
            }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(steps.indices, id: \.self) { i in
                    let state = i < reached || done ? 2 : i == reached ? 1 : 0
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(state == 2 ? C.brand : C.char800).frame(width: 22, height: 22)
                            if state == 2 { Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white) }
                            if state == 1 { ProgressView().controlSize(.mini).tint(C.brandHi) }
                        }
                        Text(steps[i]).font(F.round(15, .semibold))
                            .foregroundStyle(state == 0 ? C.char600 : C.creme)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 30)
            Spacer(minLength: 20)
        }
        .padding(.horizontal, 20)
        .task {
            // about seven seconds, a little uneven so it reads as work being done
            let stops: [Double] = [0.08, 0.17, 0.29, 0.41, 0.52, 0.63, 0.71, 0.80, 0.88, 0.94, 1.0]
            for p in stops {
                try? await Task.sleep(for: .milliseconds(Int.random(in: 480...820)))
                if Task.isCancelled { return }
                withAnimation(.easeInOut(duration: 0.45)) { progress = p }
                Haptics.play(.stud)
            }
            withAnimation(.snappy) { done = true }
            Haptics.play(.goal)
            try? await Task.sleep(for: .milliseconds(900))
            if !Task.isCancelled { ctx.next() }
        }
    }
}

// MARK: - ready

struct PlanReadyStep: View {
    let ctx: OBContext
    @Environment(AppStore.self) private var store

    var body: some View {
        let a = store.answers
        let focus = PlanReadyStep.focus(a.position)
        let target = Calendar.current.date(byAdding: .day, value: 28, to: Date()) ?? Date()
        OBShell(ctx: ctx, title: "\(a.firstName), your plan is ready", sub: nil, cta: "See my plan",
                onNext: { ctx.finish() }) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("YOUR FIRST 4 WEEKS · UNTIL").font(F.round(12, .heavy)).kerning(1.3).foregroundStyle(C.muted)
                    Text(target.formatted(.dateTime.day().month(.wide).year())).font(.system(size: 26, weight: .heavy))
                        .foregroundStyle(C.brandHi)
                }
                VStack(spacing: 0) {
                    row("Position", a.positionName)
                    row("Level", a.level ?? "Your level")
                    row("Main goal", a.goal ?? "Improve my skills")
                    row("Training", "\(a.trainingDaysPerWeek) days a week · recovery on the rest")
                }
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(C.char800))
                VStack(alignment: .leading, spacing: 12) {
                    Text("WHAT YOUR PLAN TRAINS FIRST").font(F.round(12, .heavy)).kerning(1.3).foregroundStyle(C.muted)
                    ForEach(Array(focus.enumerated()), id: \.offset) { i, s in
                        HStack(spacing: 12) {
                            Text("#\(i + 1)").font(F.round(14, .heavy)).foregroundStyle(C.brandHi).frame(width: 30, alignment: .leading)
                            Text(s).font(F.round(16, .bold)).foregroundStyle(C.creme)
                            Spacer()
                            Capsule().fill(C.char700).frame(width: 90, height: 8)
                                .overlay(alignment: .leading) { Capsule().fill(C.brand).frame(width: 90 * [0.9, 0.7, 0.5][i], height: 8) }
                        }
                    }
                    Text("Picked for a \(a.positionName.lowercased()). Your daily sessions mix these with ball work everyone needs.")
                        .font(F.round(13, .medium)).foregroundStyle(C.muted).fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(C.char850)
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(C.line, lineWidth: 1)))
            }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(F.round(15, .semibold)).foregroundStyle(C.muted)
            Spacer(minLength: 12)
            Text(v).font(F.round(15, .bold)).foregroundStyle(C.creme).multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    /// The three skills a position's plan leans on most (from LabPlan.focus).
    static func focus(_ position: String) -> [String] {
        let nice = ["First touch": "First Touch", "Ball mastery": "Ball Mastery", "Core": "Core Strength", "Runs": "Speed"]
        var count: [String: Int] = [:], order: [String] = []
        for id in LabPlan.focus(LabPlan.group(position)) where Library.shared.has(id) {
            let s = Library.shared.drill(id).skill
            if count[s] == nil { order.append(s) }
            count[s, default: 0] += 1
        }
        let top = order.sorted { (count[$0] ?? 0) > (count[$1] ?? 0) }.prefix(3).map { nice[$0] ?? $0 }
        return top.count == 3 ? Array(top) : Array((top + ["Ball Mastery", "First Touch", "Speed"]).prefix(3))
    }
}
