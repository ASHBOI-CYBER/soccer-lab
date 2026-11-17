// The paywall v2 (2026-10-28): a full-bleed REEL of the best Blender drill videos up top (story-style bars, crossfade
// + slow push-in), the player's name in the headline, five features with hand-drawn icons (stitched green tiles, the
// Week Ball's stitch language), then the plans. No FC card any more (the card is retired ? notes/19).
// Real StoreKit ? YEARLY $29.99 (7 days free, first time only) · MONTHLY $9.99 · LIFETIME $39.99 once.
import PostHog
import RevenueCat
import RevenueCatUI
import StoreKit
import SwiftUI

/// The reel (v3, 2026-10-30, user: the old ones "are pretty bad"): the path-traced drills that read best at a glance ?
/// close shots with a goal, a keeper or the ball in the air. Swipe through them; they also move on by themselves.
private let REEL: [(id: String, name: String)] = [
    ("chest-volley-shot", "CHEST + VOLLEY"),
    ("chip-the-keeper", "CHIP THE KEEPER"),
    ("elastico-cone", "ELASTICO"),
    ("gk-low-dives", "DIVING SAVES"),
    ("headers", "HEADERS"),
    ("feint-chain-sprint", "FEINT + SPRINT"),
]
private let REEL_HOLD = 3.8

/// The paywall everywhere (onboarding + PaywallGate). RevenueCat decides which one (notes/39): design a paywall for
/// the current offering in the RevenueCat dashboard and it shows that one (no app update needed); no dashboard
/// paywall ? our own SoccerMaxPaywall below. Either way, buying flips `Purchases.hasAccess` ? `done`.
struct PaywallView: View {
    let done: () -> Void
    @State private var pay = Purchases.shared
    @State private var finished = false

    var body: some View {
        Group {
            if let o = pay.offering, o.hasPaywall {
                RevenueCatUI.PaywallView(offering: o)
                    .onPurchaseCompleted { _, info in
                        if info.entitlements[PayID.entitlement]?.isActive == true { finish() }
                    }
                    .onRestoreCompleted { info in
                        if info.entitlements[PayID.entitlement]?.isActive == true { finish() }
                    }
                    .onAppear {
                        PostHogSDK.shared.capture("paywall_viewed", properties: ["paywall": "revenuecat", "offering": o.identifier])
                        QuickActions.shared.paywallSeen()
                    }
                    .onChange(of: pay.hasAccess) { _, has in if has { finish() } }
            } else {
                SoccerMaxPaywall { finish() }
            }
        }
        .task { if pay.offering == nil { await pay.load() } }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        Task { await pay.refresh() }
        done()
    }
}

/// Our own paywall (the reel + plans) ? used when the RevenueCat offering has no dashboard paywall.
struct SoccerMaxPaywall: View {
    let done: () -> Void
    @Environment(AppStore.self) private var store
    @State private var pick = PayID.yearly
    /// HAVE A CODE? ? team / gift = 7 days free, free-pass = lifetime (notes/26, notes/40).
    @State private var joining = false
    /// Apple's own code sheet (App Store offer codes, e.g. the creators' free month; 2026-11-17)
    @State private var redeeming = false
    @State private var team = Team.shared
    @State private var pay = Purchases.shared
    /// The features, kept off the one-screen page ? the big shiny SEE ALL FEATURES opens them full screen (2026-10-30).
    @State private var showFeatures = false
    /// `done` runs once ? buying here or on the 40% OFF page (which flips hasAccess) both land on it.
    @State private var finished = false

    private var trial: Bool { pick == PayID.yearly && pay.trialOffered }

    var body: some View {
        let a = store.answers
        // v2 (SOCCER LAB, 2026-11-14): black and blue like the rest of the app, and only what the app really has
        ScrollView {
            VStack(spacing: 14) {
                headline(a)
                outcomes(a)
                growth(a)
                rating
                plans
                trust
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .offerCodeRedemption(isPresented: $redeeming) { _ in
            Task { await pay.restore(); if pay.hasAccess { finish() } }
        }
        .background(AppBackground())
        .dock {
            VStack(spacing: 8) {
                Button {
                    Task { if await pay.buy(pick) { finish() } }
                } label: {
                    if pay.busy { ProgressView().tint(.white) } else { Text(cta) }
                }
                .buttonStyle(.gameLarge(.brand, feel: .kick))
                .disabled(pay.busy)
                HStack(spacing: 8) {
                    Link("Privacy Policy", destination: Legal.privacy)
                    Text("·").foregroundStyle(C.muted)
                    Link("Terms of Service", destination: Legal.terms)
                    Text("·").foregroundStyle(C.muted)
                    Button("Restore") { Task { await pay.restore(); if pay.hasAccess { finish() } } }
                }
                .font(F.round(14, .semibold)).foregroundStyle(C.creme2)
                .lineLimit(1).minimumScaleFactor(0.8)
                HStack(spacing: 16) {
                    Button(team.pendingCode != nil ? "Your code is ready. Use it" : "Have a code?") { joining = true }
                    Button("Redeem App Store code") { redeeming = true }
                }
                .font(F.round(13, .semibold)).foregroundStyle(C.muted)
                Text(fine).font(F.round(12)).foregroundStyle(C.muted).multilineTextAlignment(.center)
            }
        }
        .onAppear {
            PostHogSDK.shared.capture("paywall_viewed")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { Haptics.play(.land) }
            if team.pendingCode != nil { joining = true }
            #if DEBUG
            if DebugRoute.parts.contains("features") { showFeatures = true }   // sim.sh paywall:features
            if DebugRoute.parts.contains("code") { joining = true }            // sim.sh paywall:code
            #endif
            QuickActions.shared.paywallSeen()   // from now on, holding the icon shows the 40% OFF offer
        }
        .onChange(of: pay.hasAccess) { _, has in if has { finish() } }
        .task { await pay.load(); await pay.checkTrial() }
        .alert("Purchase", isPresented: Binding(get: { pay.error != nil }, set: { if !$0 { pay.error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(pay.error ?? "") }
        .sheet(isPresented: $joining) {
            JoinCodeSheet { finish() }
        }
        .sheet(isPresented: $showFeatures) {
            FeaturesSheet(answers: a) { showFeatures = false }
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        done()
    }

    // MARK: - pieces

    // v3 (2026-11-17): personal headline, outcomes for their position, a 5-week progress picture, savings, trust row.

    /// "STRIKER · CLUB" from onboarding.
    private func eyebrow(_ a: Answers) -> String {
        ([a.positionName] + (a.level.map { [$0] } ?? [])).joined(separator: " · ").uppercased()
    }

    private func headline(_ a: Answers) -> some View {
        let name = a.firstName.trimmingCharacters(in: .whitespaces)
        let title: Text = (name.isEmpty || name == "Player")
            ? Text("Let's build your game.").foregroundStyle(C.creme)
            : Text("\(name), ").foregroundStyle(C.brand) + Text("let's build your game.").foregroundStyle(C.creme)
        return VStack(spacing: 10) {
            Label(eyebrow(a), systemImage: "bolt.fill")
                .font(F.round(13, .heavy)).kerning(2).foregroundStyle(C.brandHi)
                .lineLimit(1).minimumScaleFactor(0.7)
            title
                .font(.system(size: 27, weight: .heavy))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("Every skill you want can be trained.")
                .font(F.round(15, .medium)).foregroundStyle(C.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    /// Four outcomes, worded for their position.
    private func outcomes(_ a: Answers) -> some View {
        let role: String
        switch LabPlan.group(a.position) {
        case "Goalkeeper": role = "keeper"
        case "Defender": role = "defender"
        case "Midfielder": role = "midfielder"
        default: role = (a.position == "LW" || a.position == "RW") ? "winger" : "attacker"
        }
        let rows: [(String, Color, String)] = [
            ("flame.fill", Color(hex: 0xFF9F43), "Walk into every match ready"),
            ("shield.lefthalf.filled", C.brandHi, "Become the \(role) your team relies on"),
            ("bolt.fill", Color(hex: 0xF5C542), "Turn practice into more game time"),
            ("trophy.fill", C.gold, "Stand out every time you play"),
        ]
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(rows.indices, id: \.self) { i in
                HStack(spacing: 14) {
                    Image(systemName: rows[i].0).font(.system(size: 18, weight: .bold)).foregroundStyle(rows[i].1)
                        .frame(width: 30)
                    Text(rows[i].2).font(F.round(16, .semibold)).foregroundStyle(C.creme)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 6)
    }

    /// A picture of training steadily with a plan vs on your own. An illustration, and it says so.
    private func growth(_ a: Answers) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            (Text("YOUR PATH · ").foregroundStyle(C.muted) + Text("NEXT 5 WEEKS").foregroundStyle(C.brandHi))
                .font(F.round(12, .heavy)).kerning(2)
            Canvas { ctx, size in
                var with = Path(), without = Path()
                for i in 0...40 {
                    let x = Double(i) / 40
                    let up = 0.88 - 0.72 * (x + 0.06 * sin(x * 9) * x)
                    let flat = 0.88 - 0.22 * x
                    let a = CGPoint(x: x * size.width, y: up * size.height), b = CGPoint(x: x * size.width, y: flat * size.height)
                    if i == 0 { with.move(to: a); without.move(to: b) } else { with.addLine(to: a); without.addLine(to: b) }
                }
                ctx.stroke(without, with: .color(C.muted.opacity(0.7)), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 6]))
                ctx.stroke(with, with: .color(C.brand), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
            }
            .frame(height: 62)
            HStack(spacing: 14) {
                Label("With Soccer Lab", systemImage: "circle.fill").foregroundStyle(C.creme2)
                Label("Training alone", systemImage: "circle.fill").foregroundStyle(C.muted)
                Spacer(minLength: 0)
                Text("\(a.trainingDaysPerWeek) days/week").foregroundStyle(C.muted)
            }
            .font(F.round(12, .semibold))
            .labelStyle(LegendDot())
            Text("An illustration of steady training with a plan, not a promise.")
                .font(F.round(10, .medium)).foregroundStyle(C.char600)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(C.char800)
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(C.line, lineWidth: 1)))
    }

    private var rating: some View {
        HStack(spacing: 10) {
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { _ in Image(systemName: "star.fill").font(.system(size: 17)).foregroundStyle(Color(hex: 0xF5B83D)) }
            }
            Text("Built for players who want more").font(F.round(15, .semibold)).foregroundStyle(C.creme2)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var trust: some View {
        HStack(spacing: 10) {
            ForEach(["Cancel anytime", "No hidden fees", "Instant access"], id: \.self) { t in
                Label(t, systemImage: "checkmark").font(F.round(12, .semibold)).foregroundStyle(C.creme2)
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// What a subscription opens, in the app's words (only things the app really does).
    private var features: some View {
        VStack(alignment: .leading, spacing: 12) {
            featureRow("figure.soccer", "A session every day for your position")
            featureRow("sparkles", "Ask Coach, your AI training coach")
            featureRow("video.fill", "Review your clips and get the drills that fix them")
            featureRow("fork.knife", "Fuel targets, meal plans and hydration")
            featureRow("location.fill", "Live GPS runs with distance and pace")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(C.char800)
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(C.line, lineWidth: 1)))
    }

    private func featureRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14, weight: .bold)).foregroundStyle(C.brandHi)
                .frame(width: 32, height: 32)
                .background(Circle().fill(C.brand.opacity(0.18)))
            Text(text).font(F.round(15, .semibold)).foregroundStyle(C.creme)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var plans: some View {
        HStack(alignment: .bottom, spacing: 8) {
            DayTile(on: pick == PayID.yearly, badge: pay.yearlySavesPercent.map { "\($0)% OFF" }, name: "Yearly",
                    perDay: pay.perDayValue(PayID.yearly), line: "\(pay.price(PayID.yearly))/year",
                    billed: pay.perWeek(PayID.yearly), was: "vs \(pay.weeklyForAYear)/yr") { pick = PayID.yearly }
            DayTile(on: pick == PayID.weekly, badge: nil, name: "Weekly",
                    perDay: pay.perDayValue(PayID.weekly), line: "\(pay.price(PayID.weekly))/week",
                    billed: nil, was: nil) { pick = PayID.weekly }
            // no LIFETIME tile (2026-11-14): Skiller AI's listing sells yearly and monthly only. Lifetime code passes
            // (free-pass links) still work; they never went through this tile.
        }
        .padding(.top, 10)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: pick)
    }

    /// One link for every code: team / gift (7 days free) or a free LIFETIME pass (notes/40).
    private var haveCode: some View {
        Button { joining = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "ticket.fill").font(.system(size: 13, weight: .heavy))
                Text(team.pendingCode != nil ? "Your code is ready. Use it" : "Have a code?").font(F.round(14, .semibold))
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .heavy))
            }
            .foregroundStyle(C.brandHi)
            .frame(height: 36)
        }
        .buttonStyle(.press(.pop))
    }

    private var cta: String {
        if !trial, pick == PayID.yearly || pick == PayID.weekly { return "Start my plan" }
        return switch pick {
        case PayID.yearly: trial ? "Start my free week" : "Continue with yearly"
        case PayID.weekly: "Continue with weekly"
        case PayID.monthly: "Continue with monthly"
        default: "Buy lifetime"
        }
    }

    /// The price line Apple wants right by the button.
    private var fine: String {
        switch pick {
        case PayID.yearly: trial ? "7 days free, then \(pay.price(PayID.yearly))/year. Renews yearly. Cancel anytime."
                                 : "Just \(pay.price(PayID.yearly)) per year (\(pay.yearlyMonthly)/mo) · Auto-renews · Cancel anytime."
        case PayID.weekly: "Just \(pay.price(PayID.weekly)) per week · Auto-renews · Cancel anytime."
        case PayID.monthly: "\(pay.price(PayID.monthly))/month. Renews monthly. Cancel anytime."
        default: "\(pay.price(PayID.lifetime)) once. No subscription."
        }
    }
}

// MARK: - the reel

/// The drills, full bleed, one per page: SWIPE left/right (or wait ? it moves on every few seconds until you swipe).
/// Story bars on top, the drill's name bottom-left. Each page's loop plays on its own.
private struct PaywallReel: View {
    let topInset: CGFloat
    @State private var i = 0
    @State private var since = Date()
    @State private var touched = false
    @State private var pulse = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { g in
                TabView(selection: $i) {
                    ForEach(REEL.indices, id: \.self) { k in
                        ZStack {
                            C.char900
                            if let url = DrillVideo.url(REEL[k].id) {
                                LoopingVideo(url: url)
                                    .frame(width: max(g.size.width, g.size.height), height: max(g.size.width, g.size.height))
                            }
                        }
                        .frame(width: g.size.width, height: g.size.height)
                        .clipped()
                        .tag(k)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            // fades: a little at the top for the bars, a long one at the bottom into the page
            VStack(spacing: 0) {
                LinearGradient(colors: [C.char900.opacity(0.85), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: topInset + 60)
                Spacer()
                LinearGradient(colors: [.clear, C.char900.opacity(0.7), C.char900], startPoint: .top, endPoint: .bottom)
                    .frame(height: 170)
            }
            .allowsHitTesting(false)
            // story bars (the current one fills while it auto-plays; full once you've swiped)
            VStack {
                TimelineView(.animation) { t in
                    let p = touched ? 1 : min(1, t.date.timeIntervalSince(since) / REEL_HOLD)
                    HStack(spacing: 5) {
                        ForEach(REEL.indices, id: \.self) { k in
                            GeometryReader { g in
                                Capsule().fill(C.creme.opacity(0.25))
                                    .overlay(alignment: .leading) {
                                        Capsule().fill(C.creme)
                                            .frame(width: g.size.width * (k < i ? 1 : k == i ? p : 0))
                                    }
                            }
                            .frame(height: 4)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, topInset + 8)
                Spacer()
            }
            .allowsHitTesting(false)
            // now playing + swipe hint
            HStack(spacing: 8) {
                Circle().fill(C.brand).frame(width: 9, height: 9)
                    .scaleEffect(pulse ? 1.25 : 0.8).opacity(pulse ? 1 : 0.55)
                Text(REEL[i].name).font(F.display(14)).foregroundStyle(C.creme)
                    .id(i)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                if !touched {
                    Image(systemName: "hand.draw.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(C.creme2)
                    Text("SWIPE").font(F.display(12)).foregroundStyle(C.creme2)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Capsule().fill(C.charInk.opacity(0.55)).overlay(Capsule().stroke(C.creme.opacity(0.12), lineWidth: 1)))
            .padding(.leading, 16)
            .padding(.bottom, 70)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: i)
            .allowsHitTesting(false)
        }
        .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever()) { pulse = true } }
        .onChange(of: i) { _, _ in
            Haptics.play(.stud)
            // a change we didn't make = the player swiped: stop auto-advancing, they're driving now
            if Date().timeIntervalSince(since) < REEL_HOLD - 0.2 { touched = true }
            since = .now
        }
        .task(id: since) {
            guard !touched else { return }
            try? await Task.sleep(for: .seconds(REEL_HOLD))
            if !Task.isCancelled, !touched { withAnimation(.easeInOut(duration: 0.5)) { i = (i + 1) % REEL.count } }
        }
    }
}

// MARK: - plans

private struct PlanTile: View {
    let on: Bool
    let badge: String?
    let name: String
    let price: String
    let unit: String
    let sub: String
    let pick: () -> Void

    var body: some View {
        Button(action: pick) {
            VStack(spacing: 6) {
                Text(name).font(F.round(15, .semibold)).foregroundStyle(on ? C.brandHi : C.creme2).lineLimit(1).minimumScaleFactor(0.7)
                (Text(price).font(.system(size: 22, weight: .bold)) + Text(unit).font(F.round(12, .semibold))).foregroundStyle(C.creme)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(sub).font(F.round(12, .medium)).foregroundStyle(C.muted).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20).padding(.bottom, 14).padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(on ? AnyShapeStyle(LinearGradient(colors: [C.brand.opacity(0.26), C.char800], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(C.char800))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(on ? C.brand : C.line, lineWidth: on ? 2 : 1))
            )
            .overlay(alignment: .top) {
                if let badge {
                    Text(badge).font(F.round(11, .bold)).kerning(0.6).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(C.brand))
                        .offset(y: -11)
                }
            }
            .overlay(alignment: .topTrailing) {
                if on {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .black)).foregroundStyle(.white)
                        .frame(width: 20, height: 20).background(Circle().fill(C.brand))
                        .offset(x: 5, y: -6)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .shadow(color: on ? C.brand.opacity(0.35) : .clear, radius: 14)
        }
        .buttonStyle(.press(.pop))
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The trial, as three stops on a line: today ? day 7 ? anytime.
private struct TrialSteps: View {
    let price: String
    var body: some View {
        let steps = [("Today", "Full access, free", C.brand), ("Day 7", "First \(price)", C.gold), ("Anytime", "Cancel in Settings", C.creme2)]
        ZStack(alignment: .top) {
            Rectangle().fill(C.char600).frame(height: 3).padding(.horizontal, 50).padding(.top, 7)
            HStack(alignment: .top, spacing: 0) {
                ForEach(steps, id: \.0) { s in
                    VStack(spacing: 6) {
                        Circle().fill(s.2).frame(width: 16, height: 16).overlay(Circle().stroke(C.line, lineWidth: 1))
                        Text(s.0).font(F.display(15)).foregroundStyle(C.creme)
                        Text(s.1).font(F.round(12, .semibold)).foregroundStyle(C.muted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .gameCard(padding: 14, radius: 18)
    }
}

// MARK: - features

/// The big shiny button under the headline (user, 2026-10-30: "bigger and more shiny"): a gold capsule with a light
/// sweep running across it every couple of seconds and a sparkle that twinkles.
private struct ShinyFeaturesButton: View {
    let action: () -> Void
    @State private var twinkle = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").font(.system(size: 17, weight: .heavy))
                    .scaleEffect(twinkle ? 1.15 : 0.9).rotationEffect(.degrees(twinkle ? 8 : -8))
                Text("SEE ALL FEATURES").font(F.display(18))
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .black))
            }
            .foregroundStyle(C.goldInk)
            .padding(.horizontal, 26).frame(height: 50)
            .background {
                ZStack {
                    Capsule().fill(C.goldLip).offset(y: 4)
                    Capsule().fill(LinearGradient(colors: [C.goldHi, C.gold], startPoint: .top, endPoint: .bottom))
                    // the shine: a soft white band sliding left ? right, then a pause
                    TimelineView(.animation) { t in
                        let cycle = 2.4, run = 0.9
                        let p = t.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle) / run
                        GeometryReader { g in
                            LinearGradient(colors: [.clear, .white.opacity(0.75), .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: 60)
                                .rotationEffect(.degrees(18))
                                .offset(x: -80 + (g.size.width + 160) * min(1, p))
                                .opacity(p < 1 ? 1 : 0)
                        }
                    }
                    .clipShape(Capsule())
                    .blendMode(.plusLighter)
                    Capsule().inset(by: 4).stroke(C.goldInk.opacity(0.25), style: StrokeStyle(lineWidth: 1.4, dash: [3, 3]))
                    Capsule().stroke(C.goldInk, lineWidth: 2.5)
                }
            }
            .shadow(color: C.gold.opacity(0.45), radius: 14)
        }
        .buttonStyle(.press(.pop))
        .onAppear { withAnimation(.easeInOut(duration: 0.8).repeatForever()) { twinkle = true } }
        .accessibilityLabel("See all features")
    }
}

/// WHAT YOU GET ? every feature, spread over the whole popup (user, 2026-10-30: "make sure the features take up the
/// whole popup, add more if necessary"). Rows grow to fill tall phones; a small phone scrolls instead of squashing.
private struct FeaturesSheet: View {
    let answers: Answers
    let close: () -> Void
    @State private var shown = false

    private var rows: [(PayIcon, String, String)] {
        let fix = answers.fix.first?.lowercased()
        let days = answers.days.count
        let custom = days > 0
            ? "\(days) days a week, built around your \(fix ?? "game")"
            : "Your week, built around your \(fix ?? "game")"
        return [
            (.drills, "400+ DRILLS IN 3D", "See every move before you try it"),
            (.custom, "MADE FOR YOU", custom),
            (.pros, "TRAIN LIKE THE PROS", "Sessions from Messi, Mbappé + more"),
            (.fitness, "FITNESS + WARM-UPS", "Sprints, core, stretches. No gym needed."),
            (.film, "MATCHDAY FILM ROOM", "Real games broken down in 3D"),
            (.levels, "LEVEL UP", "XP, badges and a stat graph that grows"),
            (.team, "STREAK FIRE", "Train 10 min every 3 days. Keep it lit."),
            (.chat, "TEAMS + CHAT", "Train with friends. Climb the leaderboard."),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Disp("WHAT YOU GET", size: 30)
            ViewThatFits(in: .vertical) {
                list
                ScrollView { list }.scrollIndicators(.hidden)
            }
            Button("GOT IT", action: close)
                .buttonStyle(.gameLarge(.gold, feel: .kick))
        }
        .padding(.horizontal, 18)
        .padding(.top, 24)
        .padding(.bottom, 8)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(C.char900)
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.85).delay(0.1)) { shown = true } }
    }

    private var list: some View {
        VStack(spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                HStack(spacing: 14) {
                    PayIconTile(icon: r.0, size: 46)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.1).font(F.display(19)).foregroundStyle(C.creme)
                        Text(r.2).font(F.round(14, .semibold)).foregroundStyle(C.muted)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 62, maxHeight: 92)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(C.char850)
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(C.line, lineWidth: 1)))
                .opacity(shown ? 1 : 0)
                .offset(x: shown ? 0 : 28)
                .animation(.spring(response: 0.55, dampingFraction: 0.8).delay(0.1 + Double(i) * 0.06), value: shown)
            }
        }
    }
}

// MARK: - custom feature icons

enum PayIcon { case drills, custom, pros, film, team, fitness, levels, chat }

/// A stitched grass tile (the Week Ball's stitch language) with a hand-drawn creme glyph outlined in ink.
struct PayIconTile: View {
    let icon: PayIcon
    var size: CGFloat = 54

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        ZStack {
            shape.fill(C.brandLip).offset(y: 4)
            shape.fill(LinearGradient(colors: [C.brandHi, C.brand, C.brandMid], startPoint: .top, endPoint: .bottom))
            shape.inset(by: 4).stroke(C.creme.opacity(0.45), style: StrokeStyle(lineWidth: 1.4, dash: [3, 3]))
            shape.stroke(C.line, lineWidth: 1)
            Canvas { ctx, s in PayGlyph.draw(icon, in: &ctx, size: s) }
                .padding(size * 0.1)
        }
        .frame(width: size, height: size)
        .padding(.bottom, 4)
    }
}

/// The glyphs, drawn in a unit box (0?1) and scaled. Every line is ink first (thick), then creme on top.
enum PayGlyph {
    static func draw(_ icon: PayIcon, in ctx: inout GraphicsContext, size s: CGSize) {
        let w = s.width
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * w, y: y * w) }
        let ink = GraphicsContext.Shading.color(C.charInk)
        let cream = GraphicsContext.Shading.color(C.creme)
        let thick = StrokeStyle(lineWidth: w * 0.13, lineCap: .round, lineJoin: .round)
        let thin = StrokeStyle(lineWidth: w * 0.055, lineCap: .round, lineJoin: .round)
        /// A filled shape with an ink outline.
        func solid(_ p: Path, fill: GraphicsContext.Shading = cream) {
            ctx.stroke(p, with: ink, style: thick)
            ctx.fill(p, with: fill)
        }
        /// A creme line with an ink outline.
        func line(_ p: Path, dash: [CGFloat] = []) {
            var t = thick; t.dash = dash.map { $0 * w }
            var n = thin; n.lineWidth = w * 0.07; n.dash = dash.map { $0 * w }
            ctx.stroke(p, with: ink, style: t)
            ctx.stroke(p, with: cream, style: n)
        }
        func ball(_ c: CGPoint, _ r: CGFloat) {
            let b = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            solid(b)
            var pent = Path()
            for k in 0..<5 {
                let a = -CGFloat.pi / 2 + CGFloat(k) * 2 * .pi / 5
                let q = CGPoint(x: c.x + cos(a) * r * 0.42, y: c.y + sin(a) * r * 0.42)
                k == 0 ? pent.move(to: q) : pent.addLine(to: q)
            }
            pent.closeSubpath()
            ctx.fill(pent, with: ink)
        }

        switch icon {
        case .drills:
            // a cone, the ball's dashed flight over it, the ball landing
            var arc = Path()
            arc.move(to: pt(0.18, 0.5))
            arc.addQuadCurve(to: pt(0.7, 0.42), control: pt(0.42, -0.02))
            line(arc, dash: [0.09, 0.1])
            var cone = Path()
            cone.move(to: pt(0.3, 0.42))
            cone.addLine(to: pt(0.44, 0.84))
            cone.addLine(to: pt(0.16, 0.84))
            cone.closeSubpath()
            solid(cone)
            var band = Path()
            band.move(to: pt(0.24, 0.66)); band.addLine(to: pt(0.37, 0.66))
            ctx.stroke(band, with: ink, style: thin)
            var base = Path()
            base.move(to: pt(0.08, 0.86)); base.addLine(to: pt(0.52, 0.86))
            line(base)
            ball(pt(0.72, 0.68), w * 0.17)

        case .custom:
            // a coach's board: X ? dashed run ? O, with a check of "done for you"
            let board = Path(roundedRect: CGRect(x: 0.1 * w, y: 0.16 * w, width: 0.8 * w, height: 0.7 * w), cornerRadius: 0.12 * w)
            solid(board, fill: .color(C.brandInk))
            let clip = Path(roundedRect: CGRect(x: 0.36 * w, y: 0.06 * w, width: 0.28 * w, height: 0.16 * w), cornerRadius: 0.05 * w)
            solid(clip)
            var x = Path()
            x.move(to: pt(0.22, 0.34)); x.addLine(to: pt(0.36, 0.48))
            x.move(to: pt(0.36, 0.34)); x.addLine(to: pt(0.22, 0.48))
            ctx.stroke(x, with: cream, style: StrokeStyle(lineWidth: w * 0.065, lineCap: .round))
            var run = Path()
            run.move(to: pt(0.3, 0.58))
            run.addQuadCurve(to: pt(0.62, 0.66), control: pt(0.36, 0.76))
            ctx.stroke(run, with: cream, style: StrokeStyle(lineWidth: w * 0.05, lineCap: .round, dash: [w * 0.06, w * 0.07]))
            var head = Path()
            head.move(to: pt(0.56, 0.58)); head.addLine(to: pt(0.66, 0.66)); head.addLine(to: pt(0.55, 0.72))
            ctx.stroke(head, with: cream, style: StrokeStyle(lineWidth: w * 0.05, lineCap: .round, lineJoin: .round))
            let o = Path(ellipseIn: CGRect(x: 0.58 * w, y: 0.3 * w, width: 0.18 * w, height: 0.18 * w))
            ctx.stroke(o, with: .color(C.gold), style: StrokeStyle(lineWidth: w * 0.065))

        case .pros:
            // a shirt with a gold star
            var shirt = Path()
            shirt.move(to: pt(0.36, 0.12))
            shirt.addQuadCurve(to: pt(0.64, 0.12), control: pt(0.5, 0.26))
            shirt.addLine(to: pt(0.92, 0.28))
            shirt.addLine(to: pt(0.8, 0.46))
            shirt.addLine(to: pt(0.72, 0.41))
            shirt.addLine(to: pt(0.72, 0.9))
            shirt.addLine(to: pt(0.28, 0.9))
            shirt.addLine(to: pt(0.28, 0.41))
            shirt.addLine(to: pt(0.2, 0.46))
            shirt.addLine(to: pt(0.08, 0.28))
            shirt.closeSubpath()
            solid(shirt)
            var star = Path()
            let c = pt(0.5, 0.6), R = w * 0.17, r = w * 0.075
            for k in 0..<10 {
                let a = -CGFloat.pi / 2 + CGFloat(k) * .pi / 5
                let rr = k.isMultiple(of: 2) ? R : r
                let q = CGPoint(x: c.x + cos(a) * rr, y: c.y + sin(a) * rr)
                k == 0 ? star.move(to: q) : star.addLine(to: q)
            }
            star.closeSubpath()
            ctx.stroke(star, with: ink, style: StrokeStyle(lineWidth: w * 0.06, lineJoin: .round))
            ctx.fill(star, with: .color(C.gold))

        case .film:
            // a film frame with sprocket holes and a play button
            let frame = Path(roundedRect: CGRect(x: 0.06 * w, y: 0.18 * w, width: 0.88 * w, height: 0.64 * w), cornerRadius: 0.1 * w)
            solid(frame)
            for k in 0..<4 {
                let hx = (0.18 + CGFloat(k) * 0.2) * w
                ctx.fill(Path(roundedRect: CGRect(x: hx, y: 0.24 * w, width: 0.1 * w, height: 0.07 * w), cornerRadius: 0.02 * w), with: ink)
                ctx.fill(Path(roundedRect: CGRect(x: hx, y: 0.69 * w, width: 0.1 * w, height: 0.07 * w), cornerRadius: 0.02 * w), with: ink)
            }
            var play = Path()
            play.move(to: pt(0.42, 0.37)); play.addLine(to: pt(0.64, 0.5)); play.addLine(to: pt(0.42, 0.63)); play.closeSubpath()
            ctx.fill(play, with: .color(C.brandMid))
            ctx.stroke(play, with: ink, style: StrokeStyle(lineWidth: w * 0.04, lineJoin: .round))

        case .fitness:
            // a stopwatch: ring, button on top, a gold sweep and the hand
            let face = Path(ellipseIn: CGRect(x: 0.14 * w, y: 0.22 * w, width: 0.72 * w, height: 0.72 * w))
            solid(face)
            let crown = Path(roundedRect: CGRect(x: 0.42 * w, y: 0.06 * w, width: 0.16 * w, height: 0.14 * w), cornerRadius: 0.04 * w)
            solid(crown)
            var sweep = Path()
            sweep.move(to: pt(0.5, 0.58))
            sweep.addArc(center: pt(0.5, 0.58), radius: w * 0.26, startAngle: .degrees(-90), endAngle: .degrees(40), clockwise: false)
            sweep.closeSubpath()
            ctx.fill(sweep, with: .color(C.gold))
            var hand = Path()
            hand.move(to: pt(0.5, 0.58)); hand.addLine(to: pt(0.69, 0.71))
            ctx.stroke(hand, with: ink, style: StrokeStyle(lineWidth: w * 0.07, lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: 0.45 * w, y: 0.53 * w, width: 0.1 * w, height: 0.1 * w)), with: ink)

        case .levels:
            // three rising bars and a gold star on the top one
            for (k, h) in [0.3, 0.48, 0.66].enumerated() {
                let x = 0.1 + CGFloat(k) * 0.28
                solid(Path(roundedRect: CGRect(x: x * w, y: (0.9 - h) * w, width: 0.22 * w, height: h * w), cornerRadius: 0.05 * w))
            }
            var star = Path()
            let c = pt(0.77, 0.14), R = w * 0.13, r = w * 0.06
            for k in 0..<10 {
                let a = -CGFloat.pi / 2 + CGFloat(k) * .pi / 5
                let rr = k.isMultiple(of: 2) ? R : r
                let q = CGPoint(x: c.x + cos(a) * rr, y: c.y + sin(a) * rr)
                k == 0 ? star.move(to: q) : star.addLine(to: q)
            }
            star.closeSubpath()
            ctx.stroke(star, with: ink, style: StrokeStyle(lineWidth: w * 0.05, lineJoin: .round))
            ctx.fill(star, with: .color(C.gold))

        case .chat:
            // a chat bubble with a ball inside (team chat)
            var bub = Path(roundedRect: CGRect(x: 0.08 * w, y: 0.12 * w, width: 0.84 * w, height: 0.6 * w), cornerRadius: 0.18 * w)
            bub.move(to: pt(0.26, 0.68)); bub.addLine(to: pt(0.2, 0.9)); bub.addLine(to: pt(0.44, 0.7))
            solid(bub)
            ball(pt(0.5, 0.42), w * 0.17)

        case .team:
            // the streak fire: an outer flame, a gold heart
            func flame(_ cx: CGFloat, _ by: CGFloat, _ h: CGFloat, _ hw: CGFloat) -> Path {
                var f = Path()
                f.move(to: pt(cx, by - h))
                f.addCurve(to: pt(cx + hw, by - h * 0.32), control1: pt(cx + hw * 0.25, by - h * 0.78), control2: pt(cx + hw * 1.05, by - h * 0.62))
                f.addCurve(to: pt(cx, by), control1: pt(cx + hw * 0.95, by - h * 0.1), control2: pt(cx + hw * 0.5, by))
                f.addCurve(to: pt(cx - hw, by - h * 0.32), control1: pt(cx - hw * 0.5, by), control2: pt(cx - hw * 0.95, by - h * 0.1))
                f.addCurve(to: pt(cx - hw * 0.35, by - h * 0.7), control1: pt(cx - hw * 1.05, by - h * 0.55), control2: pt(cx - hw * 0.6, by - h * 0.6))
                f.addCurve(to: pt(cx, by - h), control1: pt(cx - hw * 0.2, by - h * 0.82), control2: pt(cx - hw * 0.1, by - h * 0.9))
                f.closeSubpath()
                return f
            }
            solid(flame(0.5, 0.92, 0.84, 0.36))
            ctx.fill(flame(0.5, 0.86, 0.44, 0.19), with: .color(C.gold))
            ctx.stroke(flame(0.5, 0.86, 0.44, 0.19), with: ink, style: StrokeStyle(lineWidth: w * 0.04, lineJoin: .round))
        }
    }
}

/// A small coloured dot in front of a chart legend line.
private struct LegendDot: LabelStyle {
    func makeBody(configuration: LabelStyleConfiguration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 7))
            configuration.title
        }
    }
}

/// A plan box, per day first (2026-11-17, the layout the user asked for): name and tick, the per-day price big,
/// the per-week line, and for yearly the billed price with what weekly would cost for a year.
private struct DayTile: View {
    let on: Bool
    let badge: String?
    let name: String
    let perDay: String
    let line: String
    let billed: String?
    let was: String?
    let pick: () -> Void

    var body: some View {
        Button(action: pick) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(name).font(.system(size: 20, weight: .heavy)).foregroundStyle(C.creme)
                    Spacer(minLength: 4)
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24, weight: .semibold)).foregroundStyle(on ? C.brand : C.muted)
                }
                (Text(perDay).font(.system(size: 30, weight: .heavy)).foregroundStyle(on ? C.brandHi : C.creme)
                 + Text(" /day").font(F.round(15, .semibold)).foregroundStyle(C.muted))
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(line).font(F.round(18, .heavy)).foregroundStyle(C.creme)
                    .lineLimit(1).minimumScaleFactor(0.7)
                if let billed {
                    (Text(billed).font(F.round(13, .semibold)).foregroundStyle(C.muted)
                     + Text(was.map { "  " + $0 } ?? "").font(F.round(11, .semibold)).foregroundStyle(C.muted))
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(on ? AnyShapeStyle(LinearGradient(colors: [C.brand.opacity(0.22), C.char800], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(C.char800))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(on ? C.brand : C.line, lineWidth: on ? 2.5 : 1))
                    .shadow(color: on ? C.brand.opacity(0.45) : .clear, radius: 14)
            )
            .overlay(alignment: .topTrailing) {
                if let badge {
                    Text(badge).font(F.round(14, .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Capsule().fill(C.brand))
                        .offset(x: -16, y: -14)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
