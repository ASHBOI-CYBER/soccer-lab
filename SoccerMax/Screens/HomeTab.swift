// HOME tab (SOCCER LAB, 2026-11-13). The day at a glance: today's session and how far through it you are, your rank
// and the global leaderboard (Ranks.swift, 2026-11-15), this week's training days, shortcuts into each part of the app, today's fuel and what Film has asked you to fix.
// It only reads what the other tabs keep (Lab, AppStore); every card opens the tab that owns it.
import SwiftUI

struct HomeTab: View {
    @Environment(AppStore.self) private var store
    @State private var lab = Lab.shared
    @State private var running = false
    // test builds: `-route tab:home:streak` opens the streak screen
    @State private var streak = DebugRoute.parts.contains("streak")

    private var plan: [Drill] { LabPlan.today(position: store.answers.position) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    coachCard
                    today
                    HomeRankCard()
                    GlobalBoardCard()
                    week
                    shortcuts
                    fuel
                    if !lab.fixList.isEmpty { fixes }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .tabRoot("Home")
            .page()
        }
        .fullScreenCover(isPresented: $running) { RunView().duoColumn() }
        .sheet(isPresented: $streak) { StreakSheet() }
    }

    // MARK: header

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 0) {
                    Text("SOCCER ").foregroundStyle(C.creme)
                    Text("LAB").foregroundStyle(C.brand)
                }
                .font(.system(size: 22, weight: .heavy)).kerning(1.5)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Soccer Lab")
                Text("\(greeting), \(store.answers.firstName)")
                    .font(F.round(15, .semibold)).foregroundStyle(C.muted)
            }
            Spacer(minLength: 0)
            Button { streak = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: "flame.fill").foregroundStyle(store.air.days > 0 ? Color(hex: 0xFF9F43) : C.muted)
                    Text("\(store.air.days)").foregroundStyle(C.creme)
                }
                .font(F.round(15, .bold))
                .padding(.horizontal, 12).frame(height: 40)
                .background(Capsule().fill(C.char800).overlay(Capsule().stroke(C.line, lineWidth: 1)))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(store.air.days) day streak. Show streak")
            Button { Nav.shared.tab = .profile } label: {
                Text(String(store.answers.firstName.prefix(1)).uppercased())
                    .font(F.round(16, .bold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(LinearGradient(colors: [C.brandHi, C.brand], startPoint: .top, endPoint: .bottom)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profile")
        }
        .padding(.top, 10)
    }

    // MARK: today's session

    private var today: some View {
        let list = plan
        let done = list.filter { lab.isDone($0.id) }.count
        let minutes = list.reduce(0) { $0 + $1.min }
        let finished = !list.isEmpty && done == list.count
        // a recovery day (LabPlan.restDays) until they train anyway
        let rest = done == 0 && LabPlan.isRest(todayKey(), training: store.answers.trainingDaysPerWeek)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("TODAY'S SESSION").font(F.round(12, .bold)).kerning(1.6).foregroundStyle(.white.opacity(0.85))
                Spacer()
                Text(rest ? "REST" : finished ? "DONE" : "\(done) OF \(list.count)")
                    .font(F.round(11, .bold)).kerning(1).foregroundStyle(.white)
                    .padding(.horizontal, 10).frame(height: 24)
                    .background(Capsule().fill(.white.opacity(0.2)))
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(rest ? "Recovery day" : LabPlan.title(position: store.answers.position))
                    .font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                Text(rest ? "You train \(store.answers.trainingDaysPerWeek) days a week, so today is for rest: stretch, drink water and sleep well."
                     : finished ? "All \(list.count) drills done. Recover well and come back tomorrow."
                     : "\(list.count) drills built for a \(store.answers.positionName.lowercased()), about \(minutes) minutes.")
                    .font(F.round(14, .medium)).foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            GeometryReader { g in
                let f = list.isEmpty ? 0 : CGFloat(done) / CGFloat(list.count)
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.22))
                    Capsule().fill(.white).frame(width: max(f > 0 ? 8 : 0, g.size.width * f))
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
            Button { Nav.shared.tab = .training } label: {
                HStack(spacing: 6) {
                    Text(rest ? "See recovery tips" : finished ? "See this week's plan" : done == 0 ? "Start training" : "Keep going")
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .heavy))
                }
                .font(F.round(15, .semibold)).foregroundStyle(C.brandLip)
                .frame(maxWidth: .infinity).frame(height: 46)
                .background(Capsule().fill(.white))
            }
            .buttonStyle(.press(.kick))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(colors: [C.brand, C.brandMid, C.brandLip], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.white.opacity(0.22), lineWidth: 1))
                .shadow(color: C.brand.opacity(0.4), radius: 18, y: 6)
        )
    }

    // MARK: this week

    private var week: some View {
        let trained = DAYS.filter { (store.trained[dateKey(dateOf($0))] ?? 0) >= 1 }.count
        return Button { Nav.shared.tab = .training } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("THIS WEEK").font(F.round(12, .bold)).kerning(1.6).foregroundStyle(C.muted)
                    Spacer()
                    Text("Week \(lab.week())").font(F.round(13, .semibold)).foregroundStyle(C.muted)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(trained)").font(.system(size: 24, weight: .bold)).foregroundStyle(C.creme)
                    Text(trained == 1 ? "day trained" : "days trained").font(F.round(15, .semibold)).foregroundStyle(C.muted)
                }
                HStack(spacing: 8) {
                    ForEach(DAYS, id: \.self) { d in
                        let when = dateOf(d)
                        let on = (store.trained[dateKey(when)] ?? 0) >= 1
                        let isToday = d == todayKey()
                        VStack(spacing: 6) {
                            Circle()
                                .fill(on ? C.brand : C.char700)
                                .shadow(color: on ? C.brand.opacity(0.8) : .clear, radius: 6)
                                .overlay(Circle().stroke(isToday ? C.brandHi : Color.clear, lineWidth: 2))
                                .frame(width: 22, height: 22)
                                .overlay { if on { Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white) } }
                            Text(String(d.prefix(1))).font(F.round(11, .bold)).foregroundStyle(isToday ? C.creme : C.muted)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(16)
            .background(card)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This week, \(trained) days trained. Opens Training.")
    }

    // MARK: AI coach

    private var coachCard: some View {
        Button { Nav.shared.coach = true } label: {
            HStack(spacing: 14) {
                CoachBadge(size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Ask Coach").font(.system(size: 17, weight: .bold)).foregroundStyle(C.creme)
                    Text("Your AI coach knows your position, sessions and food.")
                        .font(F.round(13, .medium)).foregroundStyle(C.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(C.muted)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(colors: [C.brand.opacity(0.22), C.char800], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(C.brand.opacity(0.45), lineWidth: 1))
            )
        }
        .buttonStyle(.press(.stud))
        .accessibilityLabel("Ask Coach, your AI training coach")
    }

    // MARK: shortcuts

    private var shortcuts: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                shortcut("Live run", "Track distance and pace", "figure.run", labSkillColor("Runs")) { running = true }
                shortcut("Review a clip", "Find what to work on", "video.fill", C.brandHi) { Nav.shared.tab = .film }
            }
            HStack(spacing: 10) {
                shortcut("Log food", "Stay on your nutrition target", "fork.knife", labSkillColor("Stretching")) { Nav.shared.tab = .nutrition }
                if Nav.teamsOn {
                    shortcut("My team", "Chat and leaderboard", "person.3.fill", labSkillColor("Defending")) { Nav.shared.team = true }
                } else {
                    shortcut("Ask Coach", "Your AI training coach", "sparkles", Color(hex: 0xA78BFA)) { Nav.shared.coach = true }
                }
            }
        }
    }

    private func shortcut(_ title: String, _ sub: String, _ icon: String, _ tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon).font(.system(size: 17, weight: .bold)).foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.16)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(F.round(15, .semibold)).foregroundStyle(C.creme)
                    Text(sub).font(F.round(12, .medium)).foregroundStyle(C.muted).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(card)
        }
        .buttonStyle(.press(.stud))
    }

    // MARK: fuel

    private var fuel: some View {
        let day = lab.fuelToday
        let goal = lab.targets
        let left = max(0, goal.kcal - day.kcal)
        return Button { Nav.shared.tab = .nutrition } label: {
            HStack(spacing: 14) {
                LabRing(value: Double(day.kcal), goal: Double(goal.kcal), width: 7) {
                    Image(systemName: "flame.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(C.brandHi)
                }
                .frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 3) {
                    Text("TODAY'S NUTRITION").font(F.round(12, .bold)).kerning(1.6).foregroundStyle(C.muted)
                    Text(left > 0 ? "\(left) kcal left" : "Target reached").font(F.round(18, .bold)).foregroundStyle(C.creme)
                    Text("\(day.water) of \(goal.water) glasses of water").font(F.round(13, .medium)).foregroundStyle(C.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .heavy)).foregroundStyle(C.muted)
            }
            .padding(16)
            .background(card)
        }
        .buttonStyle(.plain)
    }

    // MARK: fix list

    private var fixes: some View {
        let n = lab.fixList.count
        return Button { Nav.shared.tab = .training } label: {
            HStack(spacing: 14) {
                Image(systemName: "wrench.and.screwdriver.fill").font(.system(size: 17, weight: .bold)).foregroundStyle(C.gold)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(C.gold.opacity(0.16)))
                VStack(alignment: .leading, spacing: 3) {
                    Text("FROM YOUR FILM").font(F.round(12, .bold)).kerning(1.6).foregroundStyle(C.muted)
                    Text("\(n) drill\(n == 1 ? "" : "s") on your Fix List").font(F.round(17, .bold)).foregroundStyle(C.creme)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .heavy)).foregroundStyle(C.muted)
            }
            .padding(16)
            .background(card)
        }
        .buttonStyle(.plain)
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: 0x13161D), C.char850], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(LinearGradient(colors: [Color.white.opacity(0.10), C.line], startPoint: .top, endPoint: .bottom), lineWidth: 1))
    }
}
