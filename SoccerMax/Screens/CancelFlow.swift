// CANCEL FLOW (2026-10-30). The user: "for monthly and yearly plans make sure there's an arrow so they can click on it
// and cancel their subscription. Make sure to get a 'why' first and stall as long as apple will allow."
// Settings ? the green plan card ? three short pages, then Apple's own cancel sheet:
//   1. WHY   ? the mascot asks why; one tap on a reason (logged to PostHog `cancel_reason`).
//   2. SAVE  ? an answer to that reason + the 50% OFF yearly (product .yearly.stay) unless they're already on it.
//   3. LOSE  ? what goes with the plan (streak, sessions, level, 408 drills) ? CANCEL IN APPLE.
// Apple's limit (Guideline 3.1.2 + 5.6 "don't make cancelling hard"): every page keeps a plain way forward to cancel
// and the X always closes. No loops, no hidden buttons, no extra pages ? three is the most to stack before the sheet.
import PostHog
import StoreKit
import SwiftUI

struct CancelFlow: View {
    let plan: PlanKind
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    @State private var pay = Purchases.shared
    // DEBUG `-route card:settings:yearly:cancel[:save|:lose]` opens a page directly.
    @State private var step = DebugRoute.parts.contains("lose") ? 2 : DebugRoute.parts.contains("save") ? 1 : 0
    @State private var reason: Reason? = DebugRoute.parts.contains("save") ? .price : nil
    @State private var wish = ""
    @State private var apple = false

    enum Reason: String, CaseIterable {
        case price = "It costs too much"
        case time = "I don't train enough"
        case missing = "It's missing something"
        case off = "Injured or season's over"
        case other = "Something else"
        var icon: String {
            switch self {
            case .price: "dollarsign.circle.fill"; case .time: "clock.fill"; case .missing: "puzzlepiece.fill"
            case .off: "bandage.fill"; case .other: "ellipsis.bubble.fill"
            }
        }
        var answer: [String] {
            switch self {
            case .price: ["I get it.", "Yearly works out far cheaper than weekly."]
            case .time: ["10 minutes is enough!", "Once every 3 days keeps your fire alive."]
            case .missing: ["Tell me what to add.", "I read every one of these."]
            case .off: ["Rest up, then come back strong.", "Your streak and stats will be waiting."]
            case .other: ["Before you go?", "Your streak and stats will be waiting."]
            }
        }
    }

    /// The 50% OFF yearly is only for people not already on it.
    /// Off in Soccer Lab 2.0 (2026-11-18): there are only two plans, weekly and yearly, and no discount product.
    private var canDiscount: Bool { false }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 17, weight: .heavy)) }
                    .buttonStyle(.gameRound(.charcoal, size: 40))
                    .accessibilityLabel("Close and keep my plan")
            }
            .padding(.horizontal, 16).padding(.top, 14)
            ScrollView {
                Group {
                    switch step {
                    case 0: why
                    case 1: save
                    default: lose
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .page()
        .dock { buttons }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: step)
        .manageSubscriptionsSheet(isPresented: $apple)
        .onChange(of: apple) { _, open in if !open { dismiss() } }
        .onAppear { PostHogSDK.shared.capture("cancel_flow_opened", properties: ["plan": plan.rawValue]) }
        .task { if pay.products[PayID.stay] == nil { await pay.load() } }
        .interactiveDismissDisabled(pay.busy)
    }

    // MARK: 1 ? why

    private var why: some View {
        VStack(spacing: 14) {
            Mascot(lines: ["Wait, \(store.answers.firstName)… why are you leaving?"], size: 150)
            ForEach(Reason.allCases, id: \.self) { r in
                Tile3D(on: reason == r, height: 62) {
                    reason = r
                    PostHogSDK.shared.capture("cancel_reason", properties: ["reason": r.rawValue, "plan": plan.rawValue])
                    Task { try? await Task.sleep(for: .milliseconds(250)); step = 1 }
                } content: {
                    HStack(spacing: 12) {
                        Image(systemName: r.icon).font(.system(size: 20, weight: .bold)).foregroundStyle(C.brand).frame(width: 28)
                        Text(r.rawValue).font(F.round(18, .semibold)).foregroundStyle(C.creme)
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                }
            }
        }
    }

    // MARK: 2 ? the answer to their reason

    private var save: some View {
        VStack(spacing: 18) {
            Mascot(lines: (reason ?? .other).answer, size: 150)
            if reason == .missing {
                TextField("What should Soccer Lab have?", text: $wish, axis: .vertical)
                    .lineLimit(3...5)
                    .font(F.round(17, .medium)).foregroundStyle(C.creme)
                    .gameCard(padding: 16, radius: 20)
            }
            if canDiscount { offer }
        }
    }

    private var offer: some View {
        VStack(spacing: 4) {
            Disp("50% OFF", size: 64, color: C.brand)
            Text("SOCCER LAB YEARLY").font(F.display(18)).foregroundStyle(C.creme)
            HStack(spacing: 10) {
                Text(pay.price(PayID.yearly)).strikethrough(true, color: C.muted).font(F.round(18, .bold)).foregroundStyle(C.muted)
                Text("\(pay.price(PayID.stay)) / year").font(F.round(22, .bold)).foregroundStyle(C.creme)
            }
            Text("That's \(pay.stayPerMonth) a month.").font(F.round(14, .semibold)).foregroundStyle(C.muted)
        }
        .frame(maxWidth: .infinity)
        .gameCard(padding: 18)
    }

    // MARK: 3 ? what goes with it

    private var lose: some View {
        let air = store.air
        return VStack(spacing: 16) {
            Mascot(lines: ["Here's what you'd lose.", "Sure you want to go?"], size: 130)
            VStack(spacing: 0) {
                loss("flame.fill", air.alive ? "Your \(air.days)-day streak" : "Your streak")
                Divider().overlay(C.char600)
                loss("checkmark.seal.fill", "\(store.completions.count) logged session\(store.completions.count == 1 ? "" : "s")")
                Divider().overlay(C.char600)
                loss("star.fill", "Level \(store.level.lv) and your stats")
                Divider().overlay(C.char600)
                loss("play.rectangle.fill", "Every drill, Socco and your film reviews")
            }
            .gameCard(padding: 6, radius: 20)
        }
    }

    private func loss(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 16, weight: .bold)).foregroundStyle(C.gold)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(C.char700))
            Text(text).font(F.round(17, .semibold)).foregroundStyle(C.creme)
            Spacer()
        }
        .padding(8)
    }

    // MARK: the dock

    @ViewBuilder private var buttons: some View {
        VStack(spacing: 12) {
            switch step {
            case 0:
                Button("KEEP MY PLAN") { dismiss() }.buttonStyle(.gameLarge)
            case 1:
                if canDiscount {
                    Button(pay.busy ? "ONE SEC…" : "CLAIM 50% OFF") {
                        PostHogSDK.shared.capture("cancel_saved", properties: ["how": "discount", "reason": reason?.rawValue ?? ""])
                        Task { if await pay.buy(PayID.stay) { Haptics.play(.goal); dismiss() } }
                    }
                    .buttonStyle(.gameLarge).disabled(pay.busy)
                    if let e = pay.error { Text(e).font(F.round(13, .semibold)).foregroundStyle(C.gold) }
                } else {
                    Button("KEEP MY PLAN") { kept() }.buttonStyle(.gameLarge)
                }
                next("Continue to cancel") { sendWish(); step = 2 }
            default:
                Button("KEEP MY PLAN") { kept() }.buttonStyle(.gameLarge)
                next("Cancel in Apple") {
                    PostHogSDK.shared.capture("cancel_to_apple", properties: ["reason": reason?.rawValue ?? ""])
                    apple = true
                }
            }
        }
    }

    private func next(_ title: String, _ go: @escaping () -> Void) -> some View {
        Button(title, action: go)
            .font(F.round(16, .bold)).foregroundStyle(C.creme.opacity(0.75))
            .padding(.vertical, 4)
    }

    private func kept() {
        sendWish()
        PostHogSDK.shared.capture("cancel_saved", properties: ["how": "kept", "step": step, "reason": reason?.rawValue ?? ""])
        Haptics.play(.goal)
        dismiss()
    }

    private func sendWish() {
        let w = wish.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty else { return }
        PostHogSDK.shared.capture("cancel_wish", properties: ["text": String(w.prefix(500))])
        wish = ""
    }
}
