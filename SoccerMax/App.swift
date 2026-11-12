// SOCCER LAB ? native SwiftUI app. Portrait only (Info.plist; the iPhone Duo inner display ignores that ? `duoColumn()`, notes/19). Onboarding first, then four tabs (Sessions · Matchday · Team · Stats · Profile).
// The only web content is the three.js canvas inside 3D viewports (Stage3DView).
import CoreText
import PostHog
import SwiftUI

/// The only path for application logs intentionally exported to PostHog.
enum PostHogExportLogger {
    static func info(_ message: String, attributes: [String: Any]) {
        PostHogSDK.shared.logger?.info(message, attributes: attributes)
    }
}

@main
struct SoccerMaxApp: App {
    /// Catches the long-press "WAIT, DON'T DELETE ME" quick action (Screens/StayOffer.swift).
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var phase
    @State private var purchases = Purchases.shared
    @State private var quick = QuickActions.shared
    @State private var store: AppStore = {
        let s = AppStore()
        if let r = DebugRoute.parts.first, !r.isEmpty { s.onboarded = r != "ob" }
        if DebugRoute.parts.contains("named"), s.answers.first.isEmpty { s.answers.first = "Alex" }   // DEBUG `-route ob:<step>:named`
        return s
    }()

    init() {
        configurePostHog()

        // Register the brand fonts now: the bar appearance below is built before UIKit would load UIAppFonts.
        for f in ["LuckiestGuy-Regular", "Fredoka-Medium", "Fredoka-SemiBold", "Fredoka-Bold"] {
            if let url = Bundle.main.url(forResource: f, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
        // Native bars in the brand's fonts and colors.
        let title = UIFont.systemFont(ofSize: 17, weight: .bold)
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.titleTextAttributes = [.font: title, .foregroundColor: UIColor(C.creme)]
        nav.largeTitleTextAttributes = [.font: UIFont.systemFont(ofSize: 32, weight: .heavy), .foregroundColor: UIColor(C.creme)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav

        let tab = UITabBarAppearance()
        tab.configureWithDefaultBackground()
        tab.backgroundColor = UIColor(C.char950).withAlphaComponent(0.85)
        let item = UITabBarItemAppearance()
        let font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        item.normal.titleTextAttributes = [.font: font, .foregroundColor: UIColor(C.muted)]
        item.selected.titleTextAttributes = [.font: font, .foregroundColor: UIColor(C.brand)]
        item.normal.iconColor = UIColor(C.muted)
        item.selected.iconColor = UIColor(C.brand)
        tab.stackedLayoutAppearance = item
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
        UIScrollView.appearance().showsVerticalScrollIndicator = false
        UIScrollView.appearance().showsHorizontalScrollIndicator = false

        // Snappy from the first tap (2026-10-28): everything slow is done now, in the background, not when a page opens ?
        // the haptic engine, every tile picture, saved club crests, the Matchday films on disk, the fire shader.
        Haptics.warm()
        ImageCache.warm()
        RemoteImages.warm()
        Task.detached(priority: .utility) { _ = Matchday.shared }
        if #available(iOS 18.0, *) {
            Task { try? await StreakFire.shader.compile(as: .colorEffect) }
        }
    }

    private func configurePostHog() {
        guard let projectToken = Bundle.main.object(forInfoDictionaryKey: "POSTHOG_PROJECT_TOKEN") as? String,
              !projectToken.isEmpty else {
            #if DEBUG
            print("PostHog is off: POSTHOG_PROJECT_TOKEN is not set (Secrets.xcconfig). No analytics are sent.")
            #endif
            return
        }

        guard let host = Bundle.main.object(forInfoDictionaryKey: "POSTHOG_HOST") as? String,
              !host.isEmpty else {
            #if DEBUG
            print("PostHog is off: POSTHOG_HOST is not set. No analytics are sent.")
            #endif
            return
        }

        let config = PostHogConfig(projectToken: projectToken, host: host)
        config.errorTrackingConfig.autoCapture = true
        config.logs.serviceName = "soccermax-ios"
        PostHogSDK.shared.setup(config)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if store.onboarded && purchases.hasAccess {
                    MainTabs()
                        .transition(.opacity)
                } else if store.onboarded {
                    // finished onboarding but never paid (or the sub / team trial ran out) ? the paywall, nothing else
                    PaywallGate()
                        .duoColumn()
                        .transition(.opacity)
                } else {
                    OnboardingFlow()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: store.onboarded)
            .animation(.easeInOut(duration: 0.35), value: purchases.hasAccess)
            // paid (or on a team trial) ? the long-press 40% OFF item goes away (Screens/StayOffer.swift)
            .onChange(of: purchases.hasAccess) { _, _ in quick.refresh() }
            .environment(store)
            .preferredColorScheme(.dark)
            .tint(C.brand)
            // invite links: soccermax.app/join/123456 (or soccermax://join/?) ? the Team tab (or the paywall, during
            // onboarding) has the code ready. Share links: soccermax.app/s/<id> ? what was shared (ShareLinks).
            .onOpenURL { url in
                if let c = Team.code(from: url) { Team.shared.pendingCode = c }
                else if let id = ShareLinks.id(from: url) { Nav.shared.openShare(id) }
                else { Nav.shared.open(url) }   // widget taps: soccermax://stats, soccermax://match/<id>
            }
            .task { WidgetSync.store = store; WidgetSync.push() }
            .task {
                // deleted the app and came back: the Apple sign-in survives in the Keychain ? bring the player back
                if !store.onboarded, Team.shared.signedIn, await Backup.shared.pull(store) { store.onboarded = true }
                if store.onboarded { await Team.shared.refresh(store) }
                quick.refresh()
            }
            // the backup goes up only here, and only when something changed (Data/Backup.swift ? cheap on purpose)
            .onChange(of: phase) { _, p in
                if p == .background { quick.refresh(); Task { await Backup.shared.push(store) } }
            }
            .fullScreenCover(isPresented: $quick.showing, onDismiss: { quick.launchCode = false }) {
                StayOfferView(launch: quick.launchCode).duoColumn().environment(store)   // column on the Duo's big screen
            }
            // after onboarding the long-press item is "Deleting? Tell us why" ? PostHog Surveys
            .sheet(isPresented: $quick.asking) { DeleteFeedbackView().environment(store) }
            .onChange(of: store.onboarded) { _, _ in quick.refresh() }
        }
    }
}

/// Tabs (SOCCER LAB, 2026-11-12): Training · Film · Nutrition · Profile. Team opens from Profile (a full-screen
/// cover, `Nav.shared.team`); the Map tab is gone.
enum AppTab: Hashable { case home, training, film, nutrition, profile }

struct MainTabs: View {
    @State private var demoDone = DebugRoute.parts == ["done", "demo"]
    @State private var tab: AppTab = {
        switch DebugRoute.parts.first {
        case "tab": return ["home": .home, "training": .training, "sessions": .training, "film": .film, "nutrition": .nutrition, "stats": .profile, "card": .profile, "profile": .profile][DebugRoute.parts[safe: 1] ?? ""] ?? .training
        case "stats", "card", "profile": return .profile
        case "sessions", "free": return .training
        default: return .home
        }
    }()

    var body: some View {
        TabView(selection: $tab) {
            HomeTab()
                .duoColumn()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppTab.home)
            TrainingTab()
                .duoColumn()
                .tabItem { Label("Training", systemImage: "figure.soccer") }
                .tag(AppTab.training)
            FilmTab()
                .duoColumn()
                .tabItem { Label("Film", systemImage: "play.rectangle.fill") }
                .tag(AppTab.film)
            NutritionTab()
                .duoColumn()
                .tabItem { Label("Nutrition", systemImage: "fork.knife") }
                .tag(AppTab.nutrition)
            ProfileTab()
                .duoColumn()
                .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
                .tag(AppTab.profile)
        }
        // ADD A PHOTO popup: first time in the app, then every 4th open while there's no photo (OnboardingFlow.swift)
        .photoNudge()
        // the session player covers everything while a session runs (SessionPlayer.swift)
        .fullScreenCover(item: Binding(get: { ActiveRun.shared.request }, set: { ActiveRun.shared.request = $0 })) { r in
            SessionPlayer(req: r)
        }
        // an area session (Sessions tab icons, START AGAIN, a teammate's session in the feed) ? FreeSession.swift
        .fullScreenCover(item: Binding(get: { FreeStart.shared.request }, set: { FreeStart.shared.request = $0 })) { r in
            FreeSession(area: r.area).duoColumn()
        }
        .onAppear { if DebugRoute.parts.first == "free" { FreeStart.shared.request = FreeRequest(area: nil) } }
        .onAppear { LiveRun.endAll() }
        // DEBUG `-route done:demo`: the session-done screen with a level-up, saving nothing
        .fullScreenCover(isPresented: $demoDone) { DemoDone() }
        .onChange(of: tab) { _, _ in Haptics.play(.stud) }
        // a code from a link (team invite, gift, creator) opens the Team page, which has the code box
        .onChange(of: Team.shared.pendingCode) { _, c in if c != nil { Nav.shared.team = true } }
        .onAppear { if Team.shared.pendingCode != nil { Nav.shared.team = true } }
        // TEAM lives behind Profile now: chat, leaderboard, invites and the code box, full screen with a Close bar
        .fullScreenCover(isPresented: Binding(get: { Nav.shared.team }, set: { Nav.shared.team = $0 })) {
            TeamTab()
                .safeAreaInset(edge: .top, spacing: 0) {
                    HStack {
                        Spacer()
                        Button { Nav.shared.team = false } label: {
                            Label("Close", systemImage: "xmark")
                                .font(F.round(15, .bold)).foregroundStyle(C.creme)
                                .padding(.horizontal, 14).frame(height: 44)
                                .background(Capsule().fill(C.char700))
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 6)
                    .background(C.char900)
                }
                .duoColumn()
        }
        .onChange(of: Nav.shared.tab) { _, t in if let t { tab = t; Nav.shared.tab = nil } }
        .sheet(item: Binding(get: { Nav.shared.session }, set: { Nav.shared.session = $0 })) { SharedSessionSheet(meta: $0.meta) }
        .onAppear { if let t = Nav.shared.tab { tab = t; Nav.shared.tab = nil } }
    }
}

/// DEBUG: the done screen with enough pretend XP to cross into the next level.
private struct DemoDone: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        let l = store.level
        NavigationStack {
            SessionDone(path: .constant(NavigationPath()), close: { dismiss() }, demoXP: l.need - l.into + 60)
        }
    }
}

/// Where a home-screen widget tap lands (notes/34): streak + consistency ? Stats, match of the day ? that film.
@Observable
final class Nav {
    static let shared = Nav()
    var tab: AppTab?
    /// The Team page is showing (opened from Profile, or by a code from a link).
    var team = false
    var tape: Int?
    /// A logged session picked on Profile's graph ? opens in the Sessions tab.
    var log: Completion?
    /// A session someone shared by link, waiting for SAVE TO MY SESSIONS.
    var session: LinkedSession?

    struct LinkedSession: Identifiable { let id: String; let meta: PostMeta }

    /// soccermax.app/s/<id>: a session ? its save sheet; a film ? that film; stats ? Stats.
    @MainActor func openShare(_ id: String) {
        Task { @MainActor in
            guard let s = await ShareLinks.fetch(id) else { return }
            switch s.kind {
            case "session": if let m = s.data { session = LinkedSession(id: id, meta: m) }
            default: if let o = s.open, let u = URL(string: o) { open(u) }
            }
        }
    }

    func open(_ url: URL) {
        guard url.scheme == "soccermax" else { return }
        switch url.host {
        case "stats": tab = .profile   // stats live on Profile now
        default: break
        }
    }
}

/// Every page sits on the charcoal weave.
extension View {
    func page() -> some View {
        background(AppBackground())
            .scrollContentBackground(.hidden)
            .toolbarBackground(.hidden, for: .navigationBar)
    }
}

/// Debug deep links for screenshots: launch with `-route drill:toe-taps` (also stats:demo, stats:year:demo, stats:demo-urgent, stats:demo-flat, session:0, session:0:pick, session:0:run, session:new, pro:messi, pro:messi:run, pros, tab:plan, move:cruyff,
/// plan:today, plan:templates, card:settings, card:stat:passing, ob:<step>). Ignored in release builds.
enum DebugRoute {
    static var value: String? {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "route")
        #else
        return nil
        #endif
    }
    static var parts: [String] { value?.components(separatedBy: ":") ?? [] }
    /// Debug routes (sim.sh tab:?, tape:?) skip the paywall; `ob` and `paywall` show it.
    static var freeAccess: Bool { guard let p = parts.first, !p.isEmpty else { return false }; return p != "ob" && p != "paywall" }
}
