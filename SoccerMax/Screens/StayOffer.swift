// "WAIT, DON'T DELETE ME!" ? v2 (2026-10-30). The user: only for people who hit the paywall and don't buy; a whole new
// paywall with ALL THREE plans 40% off (not 50), strong visuals, and a 10-minute countdown before the original paywall
// comes back.
//
// HOW IT WORKS
// - iOS never tells an app it's being deleted, but holding the icon shows the app's quick actions right above
//   "Remove App". The item ("WAIT, DON'T DELETE ME!" / "Tap for 40% OFF everything") is DYNAMIC and only there while:
//   the player has reached the paywall (`sm.paywall.seen`) AND has no access AND the offer hasn't run out.
//   v3 (2026-10-30, user): the offer is ONLY during onboarding (`sm.onboarded` false). Once onboarded, the item becomes
//   "Deleting? Tell us why" for everyone ? `DeleteFeedbackView` ? a PostHog SURVEY response (posthog-survey-delete.mjs).
//   It's set the moment the paywall appears and cleared the moment they get access (App.swift onChange).
// - Tapping it opens the 40% OFF page with a REAL 10-minute clock. The clock starts on the first open and is saved, so
//   closing and re-opening doesn't reset it. When it hits 0:00 the page closes, the original paywall is underneath,
//   and the long-press item is gone for good (honest urgency ? no fake timer that restarts).
// - Products: PayID.monthlyOff $5.99/mo · yearlyOff $17.99/yr (no trial) · lifetimeOff $23.99 (asc/step11-offer40.mjs).
import PostHog
import StoreKit
import SwiftUI
import UIKit

// MARK: - catching the quick action (cold launch + already running)

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ app: UIApplication, configurationForConnecting s: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let item = options.shortcutItem { Task { @MainActor in QuickActions.handle(item) } }
        let c = UISceneConfiguration(name: nil, sessionRole: s.role)
        c.delegateClass = SceneDelegate.self
        return c
    }

    /// Portrait everywhere, EXCEPT the iPhone Duo's inner display (regular × regular): there any way up, so the app
    /// fills the big screen (pages stay a centered column ? DuoColumn) instead of a shrunken portrait box. 2026-11-01.
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.big(window?.windowScene?.traitCollection) ? .all : .portrait
    }
    static func big(_ t: UITraitCollection?) -> Bool {
        t?.horizontalSizeClass == .regular && t?.verticalSizeClass == .regular
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ scene: UIWindowScene, performActionFor item: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        Task { @MainActor in QuickActions.handle(item) }
        completionHandler(true)
    }

    /// Folding / unfolding the Duo switches screens ? ask iOS again which ways up are allowed (AppDelegate above).
    func windowScene(_ windowScene: UIWindowScene, didUpdate previousCoordinateSpace: any UICoordinateSpace,
                     interfaceOrientation previousInterfaceOrientation: UIInterfaceOrientation,
                     traitCollection previousTraitCollection: UITraitCollection) {
        guard AppDelegate.big(previousTraitCollection) != AppDelegate.big(windowScene.traitCollection) else { return }
        for w in windowScene.windows { w.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations() }
    }
}

@MainActor @Observable
final class QuickActions {
    static let shared = QuickActions()
    static let stay = "com.skillerai.ios.stay"
    static let why = "com.skillerai.ios.why"
    /// How long the 40% OFF lasts once opened.
    static let window: TimeInterval = 10 * 60
    private static let startKey = "sm.offer40.start"
    private static let seenKey = "sm.paywall.seen"

    /// The offer page is up. DEBUG `-route stay` opens it with a fresh clock.
    var showing = false
    /// Opened by a launch-list 40% OFF code (the waitlist email, 2026-11-01): same plans, no clock, no "don't delete me".
    /// DEBUG `-route launch40`.
    var launchCode = false
    /// The "Deleting? Tell us why" page is up. DEBUG `-route why`.
    var asking = false

    private init() {
        if DebugRoute.parts.first == "why" {
            Task { @MainActor in try? await Task.sleep(for: .milliseconds(700)); asking = true }
        }
        if DebugRoute.parts.first == "launch40" { openLaunch() }
        if DebugRoute.parts.first == "stay" {
            UserDefaults.standard.set(Date(), forKey: Self.startKey)
            present()
        }
    }

    /// A cover asked for before the first screen is up (cold launch from the long-press menu) never shows ?
    /// so it's presented a beat later.
    private func present() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            showing = true
            Haptics.play(.pop)
        }
    }

    /// When the 10 minutes run out (nil = never opened).
    var ends: Date? { (UserDefaults.standard.object(forKey: Self.startKey) as? Date)?.addingTimeInterval(Self.window) }
    var expired: Bool { ends.map { $0 <= .now } ?? false }

    static func handle(_ item: UIApplicationShortcutItem) {
        switch item.type {
        case stay: shared.open()
        case why:
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))   // same cold-launch beat as present()
                shared.asking = true
            }
        default: break
        }
    }

    /// A launch-list code was used ? the 40% OFF plans, for as long as they like.
    func openLaunch() {
        launchCode = true
        PostHogSDK.shared.capture("offer40_launch_opened")
        present()
    }

    func open() {
        guard offerOn else { refresh(); return }
        if ends == nil {
            UserDefaults.standard.set(Date(), forKey: Self.startKey)
            PostHogSDK.shared.capture("offer40_started")
        }
        present()
    }

    /// The paywall is on screen: from now on, holding the icon shows the offer.
    func paywallSeen() {
        UserDefaults.standard.set(true, forKey: Self.seenKey)
        refresh()
    }

    /// Still in onboarding (the paywall is its last real step; `sm.onboarded` flips after the account step).
    private var onboarding: Bool { !UserDefaults.standard.bool(forKey: "sm.onboarded") }
    /// The 40% OFF: ONLY during onboarding, after the paywall showed, unpaid, and the clock hasn't run out.
    private var offerOn: Bool {
        onboarding && UserDefaults.standard.bool(forKey: Self.seenKey) && !Purchases.shared.hasAccess && !expired
    }

    /// The long-press menu (2026-10-30, user): during onboarding = the 40% OFF offer; once onboarded = "Deleting? Tell
    /// us why" for EVERYONE (paid or not) ? the answer goes to PostHog Surveys. Never both.
    func refresh() {
        if offerOn {
            UIApplication.shared.shortcutItems = [UIApplicationShortcutItem(
                type: Self.stay, localizedTitle: "WAIT, DON'T DELETE ME!",
                localizedSubtitle: "Tap for 40% OFF everything",
                icon: UIApplicationShortcutIcon(systemImageName: "gift.fill"), userInfo: nil)]
        } else if !onboarding {
            UIApplication.shared.shortcutItems = [UIApplicationShortcutItem(
                type: Self.why, localizedTitle: "Deleting? Tell us why",
                localizedSubtitle: "It takes 10 seconds",
                icon: UIApplicationShortcutIcon(systemImageName: "text.bubble.fill"), userInfo: nil)]
        } else {
            UIApplication.shared.shortcutItems = []
        }
    }
}

// MARK: - the 40% OFF page

struct StayOfferView: View {
    /// true = opened by a launch-list code: no clock, no expiry, "you're on the list" words.
    var launch = false
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    @State private var pay = Purchases.shared
    @State private var pick = PayID.yearlyOff
    @State private var shown = false
    @State private var shine = false
    @State private var wobble = false

    private let ends = QuickActions.shared.ends ?? Date().addingTimeInterval(QuickActions.window)

    var body: some View {
        let name = store.answers.firstName.trimmingCharacters(in: .whitespaces)
        ScrollView {
            VStack(spacing: 12) {
                Mascot(lines: launch ? ["You made the launch list\(name.isEmpty ? "" : ", \(name)")!", "Here's your 40% off everything."]
                                     : ["WAIT\(name.isEmpty ? "" : ", \(name)")! Don't delete me!",
                                        "Here's 40% off everything.", "But only for 10 minutes!"], size: 92)
                    .padding(.horizontal, 20)
                ticket
                if !launch { clock }
                plans
                    .padding(.horizontal, 16)
                Text("Every drill in 3D · Sessions from the pros · Matchday film room · Streaks + teams")
                    .font(F.round(13, .semibold)).foregroundStyle(C.muted)
                    .multilineTextAlignment(.center).padding(.horizontal, 28)
            }
            .padding(.top, 40).padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .page()
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 17, weight: .heavy)) }
                .buttonStyle(.gameRound(.charcoal, size: 40))
                .accessibilityLabel("Close")
                .padding(.horizontal, 16).padding(.top, 8)
        }
        .overlay { Confetti().allowsHitTesting(false).ignoresSafeArea() }
        .dock {
            VStack(spacing: 8) {
                Button {
                    Task { if await pay.buy(pick) { Haptics.play(.goal); QuickActions.shared.refresh(); dismiss() } }
                } label: {
                    if pay.busy { ProgressView().tint(C.goldInk) } else { Text("CLAIM 40% OFF") }
                }
                .buttonStyle(.gameLarge(.gold, feel: .kick))
                .disabled(pay.busy)
                Text(fine).font(F.round(12)).foregroundStyle(C.muted).multilineTextAlignment(.center)
                HStack(spacing: 14) {
                    Button("No thanks") { dismiss() }
                    Link("Terms", destination: Legal.terms)
                    Link("Privacy", destination: Legal.privacy)
                }
                .font(F.round(12, .semibold)).foregroundStyle(C.creme2)
            }
        }
        .alert("Purchase", isPresented: Binding(get: { pay.error != nil }, set: { if !$0 { pay.error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(pay.error ?? "") }
        .onAppear {
            PostHogSDK.shared.capture(launch ? "launch_offer_viewed" : "stay_offer_viewed")
            withAnimation(.spring(response: 0.55, dampingFraction: 0.55).delay(0.2)) { shown = true }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: false).delay(1)) { shine = true }
            withAnimation(.easeInOut(duration: 0.9).repeatForever()) { wobble = true }
        }
        .task { if pay.products[PayID.yearlyOff] == nil { await pay.load() } }
        // time's up ? close; the original paywall is underneath and the long-press item goes away
        .task {
            guard !launch else { return }   // a launch-list code never runs out
            let left = ends.timeIntervalSinceNow
            if left > 0 { try? await Task.sleep(for: .seconds(left)) }
            if Task.isCancelled { return }
            PostHogSDK.shared.capture("offer40_expired")
            QuickActions.shared.refresh()
            dismiss()
        }
    }

    // MARK: pieces

    /// The coupon: a gold ticket with side notches, a dashed tear line, a shine sweeping across.
    private var ticket: some View {
        let shape = TicketShape(notch: 16)
        return HStack(spacing: 0) {
            VStack(spacing: -6) {
                Disp("40%", size: 78, color: C.creme, ink: C.goldInk)
                Disp("OFF", size: 32, color: C.creme, ink: C.goldInk)
            }
            .frame(maxWidth: .infinity)
            Rectangle().fill(.clear).frame(width: 2)
                .overlay(Rectangle().stroke(C.goldInk.opacity(0.55), style: StrokeStyle(lineWidth: 2.5, dash: [7, 6])))
                .padding(.vertical, 14)
            VStack(spacing: 4) {
                Text("EVERY").font(F.display(18))
                Text("PLAN").font(F.display(30))
                Text(launch ? "LAUNCH LIST" : "ONE TIME ONLY").font(F.round(11, .bold)).opacity(0.8)
            }
            .foregroundStyle(C.goldInk)
            .frame(width: 112)
        }
        .padding(.vertical, 8)
        .background(
            ZStack {
                shape.fill(C.goldLip).offset(y: 6)
                shape.fill(LinearGradient(colors: [C.goldHi, C.gold, C.goldMid], startPoint: .top, endPoint: .bottom))
                // shine
                GeometryReader { g in
                    LinearGradient(colors: [.clear, .white.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 70).rotationEffect(.degrees(18))
                        .offset(x: shine ? g.size.width + 80 : -150)
                }
                .clipShape(shape)
                shape.stroke(C.goldInk, lineWidth: 3)
            }
        )
        .padding(.horizontal, 26)
        .rotationEffect(.degrees(shown ? (wobble ? -3.5 : -1.5) : -14))
        .scaleEffect(shown ? 1 : 0.3)
        .opacity(shown ? 1 : 0)
        .shadow(color: C.gold.opacity(0.35), radius: 24)
    }

    /// MM:SS on four big stitched tiles + a draining bar. The last minute pulses.
    private var clock: some View {
        TimelineView(.periodic(from: .now, by: 1)) { t in
            let left = max(0, Int(ends.timeIntervalSince(t.date).rounded(.up)))
            let digits = String(format: "%02d%02d", left / 60, left % 60).map(String.init)
            let urgent = left <= 60
            VStack(spacing: 8) {
                Text("OFFER ENDS IN").font(F.display(15)).foregroundStyle(urgent ? C.gold : C.creme2)
                HStack(spacing: 6) {
                    DigitTile(d: digits[0], hot: urgent)
                    DigitTile(d: digits[1], hot: urgent)
                    Text(":").font(F.display(44)).foregroundStyle(C.gold).opacity(left % 2 == 0 ? 1 : 0.35)
                    DigitTile(d: digits[2], hot: urgent)
                    DigitTile(d: digits[3], hot: urgent)
                }
                GeometryReader { g in
                    Capsule().fill(C.char700)
                        .overlay(alignment: .leading) {
                            Capsule().fill(LinearGradient(colors: [C.goldHi, C.gold], startPoint: .top, endPoint: .bottom))
                                .frame(width: g.size.width * CGFloat(left) / CGFloat(QuickActions.window))
                                .animation(.linear(duration: 1), value: left)
                        }
                        .overlay(Capsule().stroke(C.charInk, lineWidth: 2))
                }
                .frame(width: 250, height: 12)
            }
            .scaleEffect(urgent && left % 2 == 0 ? 1.03 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: left)
        }
    }

    private var plans: some View {
        HStack(alignment: .bottom, spacing: 8) {
            OfferTile(on: pick == PayID.yearlyOff, badge: "BEST DEAL", name: "YEARLY",
                      was: pay.price(PayID.yearly), now: pay.price(PayID.yearlyOff), unit: "/yr",
                      sub: "\(pay.yearlyOffPerMonth)/mo") { pick = PayID.yearlyOff }
            OfferTile(on: pick == PayID.monthlyOff, badge: nil, name: "MONTHLY",
                      was: pay.price(PayID.monthly), now: pay.price(PayID.monthlyOff), unit: "/mo",
                      sub: "Cancel anytime") { pick = PayID.monthlyOff }
            OfferTile(on: pick == PayID.lifetimeOff, badge: "ONCE", name: "LIFETIME",
                      was: pay.price(PayID.lifetime), now: pay.price(PayID.lifetimeOff), unit: "",
                      sub: "Yours forever") { pick = PayID.lifetimeOff }
        }
        .padding(.top, 10)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: pick)
        .onChange(of: pick) { _, _ in Haptics.play(.press) }
    }

    /// The price line Apple wants right by the button.
    private var fine: String {
        switch pick {
        case PayID.yearlyOff: "\(pay.price(PayID.yearlyOff))/year. Renews yearly at this price. Cancel anytime."
        case PayID.monthlyOff: "\(pay.price(PayID.monthlyOff))/month. Renews monthly at this price. Cancel anytime."
        default: "\(pay.price(PayID.lifetimeOff)) once. No subscription."
        }
    }
}

// MARK: - parts

/// A ticket: rounded corners with a half-circle bite out of each side, where the tear line is.
private struct TicketShape: Shape {
    var notch: CGFloat
    func path(in r: CGRect) -> Path {
        let body = Path(roundedRect: r, cornerRadius: 22, style: .continuous)
        let x = r.maxX - 113
        var bites = Path()
        bites.addEllipse(in: CGRect(x: x - notch, y: r.minY - notch, width: notch * 2, height: notch * 2))
        bites.addEllipse(in: CGRect(x: x - notch, y: r.maxY - notch, width: notch * 2, height: notch * 2))
        return body.subtracting(bites)
    }
}

private struct DigitTile: View {
    let d: String
    let hot: Bool
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        Text(d)
            .font(F.display(40)).foregroundStyle(hot ? C.gold : C.creme)
            .contentTransition(.numericText(countsDown: true))
            .frame(width: 50, height: 60)
            .background(
                ZStack {
                    shape.fill(C.charInk).offset(y: 5)
                    shape.fill(LinearGradient(colors: [C.char700, C.char850], startPoint: .top, endPoint: .bottom))
                    Rectangle().fill(C.charInk.opacity(0.6)).frame(height: 2)   // the flip-clock seam
                    shape.inset(by: 4).stroke(C.creme.opacity(0.12), style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                    shape.stroke(hot ? C.gold : C.charInk, lineWidth: 2.5)
                }
            )
    }
}

private struct OfferTile: View {
    let on: Bool
    let badge: String?
    let name: String
    let was: String
    let now: String
    let unit: String
    let sub: String
    let pick: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        Button(action: pick) {
            VStack(spacing: 5) {
                Text(name).font(F.display(17)).foregroundStyle(on ? C.gold : C.creme).lineLimit(1).minimumScaleFactor(0.7)
                Text(was).font(F.round(14, .bold)).foregroundStyle(C.muted)
                    .strikethrough(true, color: C.gold.opacity(0.9))
                (Text(now).font(F.round(22, .bold)) + Text(unit).font(F.round(12, .semibold))).foregroundStyle(C.creme)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(sub).font(F.round(11, .semibold)).foregroundStyle(on ? C.creme2 : C.muted).lineLimit(1).minimumScaleFactor(0.7)
                Text("-40%").font(F.display(13)).foregroundStyle(C.brandInk)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(C.brand).overlay(Capsule().stroke(C.brandInk, lineWidth: 1.5)))
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20).padding(.bottom, 12).padding(.horizontal, 4)
            .background(
                shape.fill(C.char850)
                    .overlay(shape.fill(on ? LinearGradient(colors: [C.gold.opacity(0.26), C.gold.opacity(0.06)], startPoint: .top, endPoint: .bottom)
                                        : LinearGradient(colors: [C.char800, C.char850], startPoint: .top, endPoint: .bottom)))
                    .overlay(shape.stroke(on ? C.gold : C.charInk, lineWidth: on ? 3 : 2.5))
                    .background(shape.fill(on ? C.goldLip : C.charInk).offset(y: 5))
            )
            .overlay(alignment: .top) {
                if let badge {
                    Text(badge).font(F.display(11)).foregroundStyle(C.goldInk)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(LinearGradient(colors: [C.goldHi, C.gold], startPoint: .top, endPoint: .bottom))
                            .overlay(Capsule().stroke(C.goldInk, lineWidth: 1.5)))
                        .offset(y: -11)
                }
            }
            .scaleEffect(on ? 1.05 : 1)
            .shadow(color: on ? C.gold.opacity(0.35) : .clear, radius: 14)
        }
        .buttonStyle(.press(.pop))
    }
}

/// A one-shot burst of gold / grass / creme confetti falling from the top when the page opens.
private struct Confetti: View {
    private struct Bit { let x, speed, spin, size, delay, sway: Double; let color: Color }
    private let bits: [Bit] = (0..<70).map { _ in
        Bit(x: .random(in: 0...1), speed: .random(in: 0.55...1.0), spin: .random(in: 2...7),
            size: .random(in: 6...12), delay: .random(in: 0...0.6), sway: .random(in: 8...26),
            color: [C.gold, C.goldHi, C.brand, C.creme].randomElement()!)
    }
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { t in
            let e = t.date.timeIntervalSince(start)
            Canvas { ctx, s in
                guard e < 3.6 else { return }
                for b in bits {
                    let k = e - b.delay
                    guard k > 0 else { continue }
                    let y = -20 + k * b.speed * s.height * 0.55
                    guard y < s.height + 20 else { continue }
                    let x = b.x * s.width + sin(k * 3 + b.x * 9) * b.sway
                    var c = ctx
                    c.opacity = max(0, min(1, 3.6 - e))
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(k * b.spin))
                    c.fill(Path(roundedRect: CGRect(x: -b.size / 2, y: -b.size / 4, width: b.size, height: b.size / 2), cornerRadius: 1.5),
                           with: .color(b.color))
                }
            }
        }
    }
}

// MARK: - "Deleting? Tell us why" (after onboarding)

/// One tap on a reason (+ optional words) ? a PostHog SURVEY response, so it shows in PostHog ? Surveys ?
/// "Why are you deleting Soccer Lab?" (made by app/scripts/posthog-survey-delete.mjs ? ids below come from it).
struct DeleteFeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    @State private var reason: String?
    @State private var more = ""
    @State private var sent = false
    @FocusState private var typing: Bool

    private static let survey = "01a18ed7-248f-0000-df77-856f0cc706b7"
    private static let qReason = "23221a62-678e-4ab7-9559-2f872efc2fc0"
    private static let qMore = "8ba3048e-4fcb-49d2-8367-b42152ec40fc"
    private static let name = "Why are you deleting Soccer Lab?"
    private static let reasons = ["It costs too much", "I don't train enough", "It's missing something", "Bugs or too slow", "Something else"]

    var body: some View {
        let first = store.answers.firstName.trimmingCharacters(in: .whitespaces)
        ScrollView {
            VStack(spacing: 16) {
                if sent {
                    Mascot(lines: ["Thank you\(first.isEmpty ? "" : ", \(first)")!", "We read every single one."], size: 150)
                        .padding(.top, 40)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Mascot(lines: ["Leaving already?", "Tell us why. We read every one."], size: 110)
                    VStack(spacing: 10) {
                        ForEach(Self.reasons, id: \.self) { r in
                            Button { reason = r; Haptics.play(.press) } label: {
                                HStack {
                                    Text(r).font(F.round(17, .bold)).foregroundStyle(reason == r ? C.char950 : C.creme)
                                    Spacer()
                                    Image(systemName: reason == r ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(reason == r ? C.char950 : C.muted)
                                }
                                .padding(.horizontal, 16).frame(height: 54)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(reason == r ? C.brand : C.char800)
                                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(reason == r ? C.brandInk : C.charInk, lineWidth: 2.5))
                                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(reason == r ? C.brandLip : C.charInk).offset(y: 4))
                                )
                            }
                            .buttonStyle(.press(.pop))
                        }
                    }
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: reason)
                    TextField("Tell us more (optional)", text: $more, axis: .vertical)
                        .lineLimit(3...6)
                        .focused($typing)
                        .font(F.round(16, .semibold)).foregroundStyle(C.creme)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(C.char850)
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(C.char600, lineWidth: 2)))
                }
            }
            .frame(maxWidth: .infinity)   // full width even when only the thank-you mascot is left
            .padding(.horizontal, 18).padding(.top, 20).padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollDismissesKeyboard(.interactively)
        .background(AppBackground().ignoresSafeArea())
        .presentationBackground(C.char900)
        .overlay(alignment: .topTrailing) {
            Button { close() } label: { Image(systemName: "xmark").font(.system(size: 16, weight: .heavy)) }
                .buttonStyle(.gameRound(.charcoal, size: 38))
                .accessibilityLabel("Close")
                .padding(14)
        }
        .dock {
            if !sent {
                Button("SEND") { send() }
                    .buttonStyle(.gameLarge)
                    .disabled(reason == nil)
                    .opacity(reason == nil ? 0.5 : 1)
            }
        }
        .onAppear {
            PostHogSDK.shared.capture("survey shown", properties: ["$survey_id": Self.survey, "$survey_name": Self.name])
        }
    }

    private func send() {
        guard let reason else { return }
        let words = more.trimmingCharacters(in: .whitespacesAndNewlines)
        PostHogSDK.shared.capture("survey sent", properties: [
            "$survey_id": Self.survey,
            "$survey_name": Self.name,
            "$survey_response_\(Self.qReason)": reason,
            "$survey_response_\(Self.qMore)": words,
            "$survey_response": reason,       // older PostHog readers
            "$survey_response_1": words,
            "$survey_questions": [
                ["id": Self.qReason, "question": Self.name, "response": reason],
                ["id": Self.qMore, "question": "Anything else you want to tell us?", "response": words],
            ],
        ])
        PostHogSDK.shared.flush()
        typing = false
        Haptics.play(.goal)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { sent = true }
        Task { try? await Task.sleep(for: .seconds(2.6)); dismiss() }
    }

    private func close() {
        if !sent { PostHogSDK.shared.capture("survey dismissed", properties: ["$survey_id": Self.survey, "$survey_name": Self.name]) }
        dismiss()
    }
}
