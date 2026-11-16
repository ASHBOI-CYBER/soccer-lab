// STREAK SCREEN (2026-11-17). The flame on Home opens it: the current streak and the best one, how long until it goes
// out, today's minutes toward the 10 that count, this week's days lit up, a month calendar (back through earlier
// months) and streak milestones. The streak rule is AirStreak (Shared/Streak.swift): 10 minutes of training at least
// once every 3 days keeps the fire going.
import SwiftUI

struct StreakSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()

    private let orange = Color(hex: 0xFF9F43)
    private static let milestones = [3, 7, 14, 30, 60, 100, 200, 365]

    private func trained(_ d: Date) -> Bool { (store.trained[dateKey(d)] ?? 0) >= AirStreak.keep }

    var body: some View {
        let s = store.air
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Disp("Streak", size: 32)
                        Text(s.alive ? "Keep the fire going." : "Start your streak with one drill today.")
                            .font(F.round(15, .semibold)).foregroundStyle(C.muted)
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(C.creme)
                            .frame(width: 40, height: 40).background(Circle().fill(C.char800))
                    }
                    .accessibilityLabel("Close")
                }
                .padding(.top, 22)

                hero(s)
                today(s)
                week
                calendar
                milestones(s)
                Text("Train at least \(Int(AirStreak.keep)) minutes, at least once every \(AirStreak.window) days, and your streak keeps going. Drills, sessions, runs and free sessions all count.")
                    .font(F.round(13, .medium)).foregroundStyle(C.muted).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .presentationDetents([.large])
        .presentationBackground(C.char900)
    }

    // the big number

    private func hero(_ s: AirStreak) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "flame.fill")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(s.alive ? LinearGradient(colors: [Color(hex: 0xFFD25E), orange, Color(hex: 0xFF5E3A)], startPoint: .top, endPoint: .bottom)
                                         : LinearGradient(colors: [C.char600, C.char700], startPoint: .top, endPoint: .bottom))
                .shadow(color: s.alive ? orange.opacity(0.7) : .clear, radius: 16)
                .frame(width: 76, height: 76)
                .background(Circle().fill(orange.opacity(s.alive ? 0.16 : 0.05)))
            VStack(alignment: .leading, spacing: 4) {
                Text("\(s.days)").font(.system(size: 44, weight: .heavy)).foregroundStyle(C.creme).monospacedDigit()
                    + Text(s.days == 1 ? " day" : " days").font(F.round(18, .bold)).foregroundStyle(C.muted)
                Text(deadline(s)).font(F.round(14, .semibold)).foregroundStyle(s.alive ? orange : C.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            VStack(spacing: 2) {
                Text("BEST").font(F.round(11, .heavy)).kerning(1).foregroundStyle(C.muted)
                Text("\(max(s.best, s.days))").font(F.round(22, .heavy)).foregroundStyle(C.gold).monospacedDigit()
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(C.char800)
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(s.alive ? orange.opacity(0.45) : C.line, lineWidth: 1)))
        .accessibilityElement(children: .combine)
    }

    private func deadline(_ s: AirStreak) -> String {
        guard s.alive, let d = s.deadline else { return "Train \(Int(AirStreak.keep)) minutes today to light it." }
        if s.keptToday { return "Today counts. Safe until \(d.formatted(.dateTime.weekday(.wide)))." }
        let hours = Int(d.timeIntervalSinceNow / 3600)
        return hours < 24 ? "Goes out in \(max(1, hours)) hours. Train today!" : "Train before \(d.formatted(.dateTime.weekday(.wide))) to keep it."
    }

    // today's minutes toward the 10 that count

    private func today(_ s: AirStreak) -> some View {
        let done = min(s.today, AirStreak.keep)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Today").font(F.round(15, .bold)).foregroundStyle(C.creme)
                Spacer()
                Text(s.keptToday ? "Done ✓" : "\(Int(done.rounded())) / \(Int(AirStreak.keep)) min")
                    .font(F.round(14, .bold)).foregroundStyle(s.keptToday ? C.brandHi : C.muted).monospacedDigit()
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(C.char700)
                    Capsule().fill(LinearGradient(colors: [Color(hex: 0xFFD25E), orange], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, g.size.width * done / AirStreak.keep))
                }
            }
            .frame(height: 10)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(C.char800))
    }

    // this week, Monday to Sunday

    private var week: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabKicker("THIS WEEK")
            HStack(spacing: 6) {
                ForEach(DAYS, id: \.self) { d in
                    let date = dateOf(d)
                    let lit = trained(date)
                    let isToday = d == todayKey()
                    VStack(spacing: 6) {
                        Text(String(d.prefix(1))).font(F.round(12, .bold)).foregroundStyle(isToday ? orange : C.muted)
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(lit ? orange.opacity(0.22) : C.char800)
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(isToday ? orange : C.line, lineWidth: isToday ? 2 : 1))
                            if lit {
                                Image(systemName: "flame.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(orange)
                            } else {
                                Text("\(Calendar.current.component(.day, from: date))").font(F.round(16, .bold))
                                    .foregroundStyle(date > Date() ? C.char600 : C.creme2)
                            }
                        }
                        .frame(height: 52)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(FULL_DAY[d]?.capitalized ?? d)\(lit ? ", trained" : "")")
                }
            }
        }
    }

    // a month at a glance

    private var calendar: some View {
        let cal = Calendar.current
        let days = cal.range(of: .day, in: .month, for: month)?.count ?? 30
        let lead = (cal.component(.weekday, from: month) + 5) % 7   // Monday first
        let count = (1...days).filter { trained(cal.date(byAdding: .day, value: $0 - 1, to: month)!) }.count
        let isThisMonth = cal.isDate(month, equalTo: Date(), toGranularity: .month)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { month = cal.date(byAdding: .month, value: -1, to: month)! } label: {
                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .bold)).frame(width: 36, height: 36)
                }
                .accessibilityLabel("Previous month")
                Spacer()
                VStack(spacing: 1) {
                    Text(month.formatted(.dateTime.month(.wide).year())).font(F.round(16, .bold)).foregroundStyle(C.creme)
                    Text("\(count) day\(count == 1 ? "" : "s") trained").font(F.round(12, .semibold)).foregroundStyle(C.muted)
                }
                Spacer()
                Button { month = cal.date(byAdding: .month, value: 1, to: month)! } label: {
                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).frame(width: 36, height: 36)
                }
                .disabled(isThisMonth)
                .accessibilityLabel("Next month")
            }
            .foregroundStyle(C.brandHi)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(["M", "T", "W", "T", "F", "S", "S"].indices, id: \.self) { i in
                    Text(["M", "T", "W", "T", "F", "S", "S"][i]).font(F.round(11, .bold)).foregroundStyle(C.muted)
                }
                ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: 34) }
                ForEach(1...days, id: \.self) { n in
                    let date = cal.date(byAdding: .day, value: n - 1, to: month)!
                    let lit = trained(date)
                    let today = cal.isDateInToday(date)
                    Text("\(n)")
                        .font(F.round(13, .bold)).monospacedDigit()
                        .foregroundStyle(lit ? Color.white : date > Date() ? C.char600 : C.creme2)
                        .frame(maxWidth: .infinity).frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(lit ? orange : C.char800.opacity(0.6))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(today ? orange : .clear, lineWidth: 2)))
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(C.char850)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(C.line, lineWidth: 1)))
    }

    // milestones

    private func milestones(_ s: AirStreak) -> some View {
        let best = max(s.best, s.days)
        return VStack(alignment: .leading, spacing: 12) {
            LabKicker("MILESTONES")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(Self.milestones, id: \.self) { m in
                    let got = best >= m
                    VStack(spacing: 4) {
                        Image(systemName: got ? "flame.fill" : "lock.fill").font(.system(size: 18, weight: .bold))
                            .foregroundStyle(got ? orange : C.char600)
                        Text("\(m)").font(F.round(16, .heavy)).foregroundStyle(got ? C.creme : C.muted)
                        Text("days").font(F.round(10, .bold)).foregroundStyle(C.muted)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(got ? orange.opacity(0.14) : C.char800))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(m) day streak, \(got ? "reached" : "not yet")")
                }
            }
        }
    }
}
