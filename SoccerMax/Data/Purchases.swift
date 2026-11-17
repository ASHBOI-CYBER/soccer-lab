// In-app purchases through RevenueCat (2026-10-30, notes/39; was raw StoreKit 2 since 2026-10-28).
// Access = the RevenueCat entitlement `soccer_max_pro` (PayID.entitlement). Three ways to pay, set up in App Store Connect
// AND in the RevenueCat dashboard (offering "default": packages $rc_monthly · $rc_annual · $rc_lifetime):
//   MONTHLY  $9.99 / month   (auto-renewing, group "SOCCER LAB")
//   YEARLY   $29.99 / year   (auto-renewing, same group, 7 days free for new subscribers)
//   LIFETIME $39.99 once     (non-consumable)
// Access = any of the three, or a friend's team trial (Team.onTrial, notes/26). The paywall gates the app until then.
// The SDK key is REVENUECAT_API_KEY (Secrets.xcconfig ? Info.plist). test_? = RevenueCat's Test Store (fake purchases,
// products "monthly" / "yearly" / "lifetime"); swap to the appl_? key before an App Store build.
// Our class is also called `Purchases`, so the SDK is always written `RC` (= RevenueCat.Purchases) here.
import PostHog
import RevenueCat
import SwiftUI

private typealias RC = RevenueCat.Purchases

enum PayID {
    static let monthly = "com.skillerai.ios.monthly"
    /// Soccer Lab sells WEEKLY + yearly (2026-11-17); monthly stays only for anyone who already has it.
    static let weekly = "com.skillerai.ios.weekly"
    static let yearly = "com.skillerai.ios.annual"   // Skiller AI's existing yearly plan
    static let lifetime = "com.skillerai.ios.lifetime"
    /// The same $29.99 yearly with NO free week ? sold to anyone who already had their one free week (2026-10-29).
    static let yearlyNoTrial = "com.skillerai.ios.yearly.notrial"
    /// "WAIT, DON'T DELETE ME" (Screens/StayOffer.swift): the same yearly at 50% off, $14.99 a year, no trial ? only
    /// offered from the long-press menu to people on their way out.
    static let stay = "com.skillerai.ios.yearly.stay"
    /// The 40% OFF offer (2026-10-30, Screens/StayOffer.swift): every plan 40% off ? $5.99/mo · $17.99/yr (no trial) ·
    /// $23.99 lifetime. Only sold from the long-press "WAIT, DON'T DELETE ME!" page, during its one 10-minute window.
    /// (The 50% `stay` plan is retired from the UI; kept here so anyone who bought it still has access.)
    static let monthlyOff = "com.skillerai.ios.monthly.off40"
    static let yearlyOff = "com.skillerai.ios.yearly.off40"
    static let lifetimeOff = "com.skillerai.ios.lifetime.off40"
    static let all = [yearly, weekly, monthly, lifetime, yearlyNoTrial, stay, monthlyOff, yearlyOff, lifetimeOff]
    /// The RevenueCat entitlement every product above unlocks (attach ALL of them to it in the dashboard).
    static let entitlement = "soccer_lab_pro"   // RevenueCat project SOCCER LAB (2026-11-17; was soccer_max_pro)
    /// Any store product id ? our id. The Test Store's products are just "monthly" / "yearly" / "lifetime".
    static func normalize(_ id: String) -> String {
        if all.contains(id) { return id }
        return ["weekly": weekly, "monthly": monthly, "yearly": yearly, "annual": yearly, "lifetime": lifetime][id] ?? id
    }
    /// Short plan name for analytics.
    static func plan(_ id: String) -> String {
        [weekly: "weekly", monthly: "monthly", yearly: "yearly", yearlyNoTrial: "yearly", lifetime: "lifetime", stay: "yearly_stay",
         monthlyOff: "monthly_40off", yearlyOff: "yearly_40off", lifetimeOff: "lifetime_40off"][id] ?? id
    }
}

/// Links the paywall and Settings need. Apple's standard EULA covers Terms; the privacy page must exist before review.
enum Legal {
    /// Support email shown in the app. CHANGE before release to an inbox someone reads (see site/privacy.html too).
    static let supportEmail = "aliazam6068@gmail.com"
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacy = URL(string: "https://glittery-banoffee-bbbd05.netlify.app/privacy")!
}

@MainActor @Observable
final class Purchases {
    static let shared = Purchases()

    /// Store products by our id (PayID). The 3 main plans come from the RevenueCat offering; the extras (no-trial
    /// yearly, 40% off, 50% off) are fetched by id because they're sold outside the paywall.
    private(set) var products: [String: StoreProduct] = [:]
    private var packages: [String: Package] = [:]
    /// The current RevenueCat offering. When a paywall is designed for it in the dashboard, that paywall is shown
    /// instead of ours (Onboarding/Paywall.swift `PaywallView`).
    private(set) var offering: Offering?
    private(set) var info: CustomerInfo?
    /// Our ids of what the person owns right now (active subscriptions + lifetime).
    private(set) var owned: Set<String> = []
    private(set) var busy = false
    var error: String?

    /// The soccer_max_pro entitlement (renewal date, will-renew, trial?) ? nil until RevenueCat answers.
    var entitlement: EntitlementInfo? { info?.entitlements[PayID.entitlement] }
    /// Paid, or on a friend's team trial. Before RevenueCat answers, the last known answer ? the paywall never flashes.
    /// The whole app is FREE FOR NOW (user, 2026-11-08: "remove the paywall" ? "app fully free for now"): no paywall in
    /// onboarding, no paywall gate after it, no 40% OFF stay offer. Set false to bring the hard paywall back.
    /// 2026-11-17: OFF. The paywall is on (payment test in TestFlight's sandbox, then launch).
    static let freeForNow = false

    var hasAccess: Bool {
        if Self.freeForNow { return true }
        let paid = info.map { $0.entitlements[PayID.entitlement]?.isActive == true } ?? UserDefaults.standard.bool(forKey: Self.paidKey)
        return paid || Team.shared.onTrial || DebugRoute.freeAccess
    }
    var isLifetime: Bool { owned.contains(PayID.lifetime) || owned.contains(PayID.lifetimeOff) }

    private static let paidKey = "sm.paid"
    private var updates: Task<Void, Never>?

    private init() {
        Self.configure()
        guard RC.isConfigured else { return }
        // every change (purchase, renewal, refund, expiry, restore on another device) lands here
        updates = Task { [weak self] in
            for await info in RC.shared.customerInfoStream { self?.apply(info) }
        }
        Task { await load() }
    }

    /// Runs once, on first use of `Purchases.shared` (App.swift holds it from launch).
    private static func configure() {
        guard !RC.isConfigured else { return }
        guard let key = Bundle.main.object(forInfoDictionaryKey: "REVENUECAT_API_KEY") as? String,
              !key.isEmpty, !key.hasPrefix("$(") else {
            #if DEBUG
            print("Purchases are off: REVENUECAT_API_KEY is not set (Secrets.xcconfig). Nothing can be bought in this build.")
            #endif
            return
        }
        #if DEBUG
        RC.logLevel = .debug
        #else
        RC.logLevel = .warn
        #endif
        RC.configure(with: Configuration.Builder(withAPIKey: key).build())
    }

    private func apply(_ i: CustomerInfo) {
        info = i
        var ids = i.activeSubscriptions
        ids.formUnion(i.nonSubscriptions.map(\.productIdentifier))
        if let e = i.entitlements[PayID.entitlement], e.isActive { ids.insert(e.productIdentifier) }
        owned = Set(ids.map(PayID.normalize))
        UserDefaults.standard.set(i.entitlements[PayID.entitlement]?.isActive == true, forKey: Self.paidKey)
    }

    /// Offering + extra products + who the person is. Safe to call again (the SDK caches).
    func load() async {
        guard RC.isConfigured else { return }
        do {
            let current = try await RC.shared.offerings().current
            offering = current
            for p in current?.availablePackages ?? [] {
                let id: String = switch p.packageType {
                case .weekly: PayID.weekly
                case .monthly: PayID.monthly
                case .annual: PayID.yearly
                case .lifetime: PayID.lifetime
                default: PayID.normalize(p.storeProduct.productIdentifier)
                }
                packages[id] = p
                products[id] = p.storeProduct
            }
            let extra = PayID.all.filter { products[$0] == nil }
            for p in await RC.shared.products(extra) { products[PayID.normalize(p.productIdentifier)] = p }
        } catch {
            PostHogExportLogger.info("revenuecat offerings failed", attributes: ["error": error.localizedDescription])
        }
        await refresh()
    }

    /// Re-reads what the person owns (cached by the SDK, works offline).
    func refresh() async {
        guard RC.isConfigured, let i = try? await RC.shared.customerInfo() else { return }
        apply(i)
    }

    /// Returns true when the purchase went through (false = cancelled / pending / failed).
    @discardableResult
    func buy(_ pick: String) async -> Bool {
        guard RC.isConfigured else { error = "Purchases aren't set up yet."; return false }
        if products[pick] == nil { await load() }
        // one free week per account: after a team / gift week (or Apple's), "yearly" is the plan without the trial
        let id = pick == PayID.yearly && freeWeekUsed && products[PayID.yearlyNoTrial] != nil ? PayID.yearlyNoTrial : pick
        busy = true; defer { busy = false }
        do {
            let result: PurchaseResultData
            if let pkg = packages[id] { result = try await RC.shared.purchase(package: pkg) }
            else if let p = products[id] { result = try await RC.shared.purchase(product: p) }
            else { error = "Can't reach the App Store. Try again in a moment."; return false }
            if result.userCancelled { return false }
            apply(result.customerInfo)
            guard let e = result.customerInfo.entitlements[PayID.entitlement], e.isActive else {
                // paid, but the product isn't attached to soccer_max_pro in the RevenueCat dashboard
                error = "Your purchase went through but didn't unlock yet. Tap Restore, or email \(Legal.supportEmail)."
                PostHogExportLogger.info("purchase without entitlement", attributes: ["product_id": id])
                return false
            }
            let trial = e.periodType == .trial
            if trial { Self.markFreeWeekUsed() }
            // Money stats: plan + price paid now (0 during the free week; Apple bills it after).
            let price = products[id].map { NSDecimalNumber(decimal: $0.price).doubleValue } ?? 0
            PostHogSDK.shared.capture("subscription_purchased", properties: [
                "product_id": id,
                "plan": PayID.plan(id),
                "price": price,
                "revenue": trial ? 0 : price,
                "currency": products[id]?.currencyCode ?? "USD",
                "has_introductory_offer": trial
            ])
            if trial { PostHogSDK.shared.capture("trial_started", properties: ["plan": PayID.plan(id), "price": price]) }
            PostHogExportLogger.info("subscription purchase verified", attributes: [
                "product_id": id,
                "has_introductory_offer": trial
            ])
            return true
        } catch {
            switch ErrorCode(rawValue: (error as NSError).code) {
            case .purchaseCancelledError: return false
            case .paymentPendingError: self.error = "Waiting for approval (Ask to Buy)."
            case .networkError, .offlineConnectionError: self.error = "No connection. Try again in a moment."
            case .productAlreadyPurchasedError: await refresh()
            default: self.error = error.localizedDescription
            }
            return false
        }
    }

    func restore() async {
        guard RC.isConfigured else { return }
        busy = true; defer { busy = false }
        do {
            apply(try await RC.shared.restorePurchases())
        } catch {
            self.error = error.localizedDescription
            return
        }
        if entitlement?.isActive != true {
            error = "No purchases found for this Apple ID."
        } else {
            PostHogSDK.shared.capture("purchase_restored", properties: ["entitlement_count": owned.count])
            PostHogExportLogger.info("purchase restore completed", attributes: ["entitlement_count": owned.count])
        }
    }

    // MARK: who is buying (Team.swift calls these on Apple sign-in / account delete)

    /// Ties purchases to the Supabase account, so a reinstall + sign-in brings the plan back on any device.
    func identify(_ userId: String) {
        guard RC.isConfigured, RC.shared.appUserID != userId else { return }
        Task {
            if let r = try? await RC.shared.logIn(userId) { apply(r.customerInfo) }
        }
    }

    /// Account deleted: back to an anonymous id, then silently re-read the Apple ID's purchases (no password prompt),
    /// so a paid person never loses access just for deleting their profile.
    func signOut() {
        guard RC.isConfigured, !RC.shared.isAnonymous else { return }
        Task {
            _ = try? await RC.shared.logOut()
            if let i = try? await RC.shared.syncPurchases() { apply(i) }
        }
    }

    /// A creator's code on the RevenueCat customer (works before sign-in). The webhook reads it on the first purchase
    /// and gives that creator their share (supabase/2026-11-12-creators.sql).
    func tagCreator(_ code: String) {
        guard RC.isConfigured, code.count == 6, code.allSatisfy(\.isNumber) else { return }
        RC.shared.attribution.setAttributes(["creator_code": code])
    }

    // MARK: prices

    /// "$29.99" from the store, falling back to the set price before products load.
    func price(_ id: String) -> String {
        if let p = products[id] { return p.localizedPriceString }
        return [PayID.weekly: "$7.99", PayID.monthly: "$9.99", PayID.yearly: "$29.99", PayID.lifetime: "$39.99", PayID.stay: "$14.99",
                PayID.monthlyOff: "$5.99", PayID.yearlyOff: "$17.99", PayID.lifetimeOff: "$23.99"][id] ?? ""
    }

    var stayPerMonth: String { products[PayID.stay]?.localizedPricePerMonth ?? "$1.25" }
    /// The 40%-off yearly per month, for the offer page's "$1.50/mo".
    var yearlyOffPerMonth: String { products[PayID.yearlyOff]?.localizedPricePerMonth ?? "$1.50" }
    /// Yearly price per month, for the "$2.50/mo" line.
    var yearlyPerMonth: String { products[PayID.yearly]?.localizedPricePerMonth ?? "$2.50" }
    /// What yearly saves against paying weekly for a year (e.g. 89), or nil when either price is unknown.
    var yearlySavesPercent: Int? {
        func n(_ id: String) -> Decimal? {
            if let p = products[id] { return p.price }
            return Decimal(string: price(id).filter { $0.isNumber || $0 == "." })
        }
        guard let y = n(PayID.yearly), let w = n(PayID.weekly), w > 0 else { return nil }
        let pct = (1 - NSDecimalNumber(decimal: y).doubleValue / (NSDecimalNumber(decimal: w).doubleValue * 52)) * 100
        return pct >= 5 ? Int(pct.rounded(.down)) : nil
    }
    /// Just the money part of the per-day price ("$0.12").
    func perDayValue(_ id: String) -> String { perDay(id).replacingOccurrences(of: "/day", with: "") }
    /// The weekly plan for a whole year ("$415.48"), for the yearly box's "vs" line.
    var weeklyForAYear: String {
        if let p = products[PayID.weekly] {
            return (p.price * 52).formatted(.currency(code: p.currencyCode ?? "USD").precision(.fractionLength(2)))
        }
        let n = Decimal(string: price(PayID.weekly).filter { $0.isNumber || $0 == "." }) ?? 0
        return (n * 52).formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }
    /// Yearly per month ("$3.75"), for the small print.
    var yearlyMonthly: String {
        if let p = products[PayID.yearly] {
            return (p.price / 12).formatted(.currency(code: p.currencyCode ?? "USD").precision(.fractionLength(2)))
        }
        let n = Decimal(string: price(PayID.yearly).filter { $0.isNumber || $0 == "." }) ?? 0
        return (n / 12).formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }
    /// Price per week of a plan ("$0.67/week").
    func perWeek(_ id: String) -> String {
        let weeks: Decimal = id == PayID.weekly ? 1 : id == PayID.monthly ? Decimal(30) / 7 : 52
        if let p = products[id] {
            return (p.price / weeks).formatted(.currency(code: p.currencyCode ?? "USD").precision(.fractionLength(2))) + "/week"
        }
        let n = Decimal(string: price(id).filter { $0.isNumber || $0 == "." }) ?? 0
        return (n / weeks).formatted(.currency(code: "USD").precision(.fractionLength(2))) + "/week"
    }
    /// What a plan costs per day ("$0.10/day"), from the App Store's real local price when it has loaded.
    func perDay(_ id: String) -> String {
        let days: Decimal = id == PayID.weekly ? 7 : id == PayID.monthly ? 30 : 365
        if let p = products[id] {
            return (p.price / days).formatted(.currency(code: p.currencyCode ?? "USD").precision(.fractionLength(2))) + "/day"
        }
        let n = Decimal(string: price(id).filter { $0.isNumber || $0 == "." }) ?? 0
        return (n / days).formatted(.currency(code: "USD").precision(.fractionLength(2))) + "/day"
    }

    /// ONE free week per account (user 2026-10-29: "maximum 1 free or card 7 day trial per account"): a team invite,
    /// a friend's gift link, or Apple's card trial ? whichever comes first uses it up. Server flag `profiles.trial_used`
    /// (Team.trialUsed) + this phone's flag + Apple's own eligibility.
    var freeWeekUsed: Bool { UserDefaults.standard.bool(forKey: Self.usedKey) || Team.shared.trialUsed }
    private static let usedKey = "sm.trial.used"
    static func markFreeWeekUsed() {
        UserDefaults.standard.set(true, forKey: usedKey)
        Task { await Team.shared.markTrialUsed() }
    }

    /// True when this person can still get the yearly free trial (Apple says first-time subscriber AND no free week yet).
    /// NO free trial in Soccer Lab (user, 2026-11-17: "it is not free"). Turn back on here if a trial is ever added.
    static let freeTrial = false
    var trialOffered: Bool = Purchases.freeTrial
    func checkTrial() async {
        guard Self.freeTrial else { trialOffered = false; return }
        await Team.shared.refreshTrial()
        guard RC.isConfigured, let p = products[PayID.yearly] else { trialOffered = !freeWeekUsed; return }
        let status = await RC.shared.checkTrialOrIntroDiscountEligibility(product: p)
        if status == .ineligible { Self.markFreeWeekUsed() }   // Apple's free week (or a sub) already happened on this Apple ID
        trialOffered = status != .ineligible && status != .noIntroOfferExists && p.introductoryDiscount != nil && !freeWeekUsed
    }
}
