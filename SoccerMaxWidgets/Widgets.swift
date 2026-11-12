// SOCCER LAB home-screen widgets (notes/34): STREAK (the fire + today's 10 min), MATCH OF THE DAY (crests + clubs +
// film length ? never the score, like the Matchday list), CONSISTENCY (a square per day: blue = trained).
// They only read WidgetSnapshot (written by the app's WidgetSync); the streak is re-counted here every hour.
import CoreText
import SwiftUI
import WidgetKit

// MARK: - brand bits (same values as the app's Theme.swift)

enum W {
    static let brand = Color(hex: 0x1E78FF)
    static let brandHi = Color(hex: 0x7DB8FF)
    static let char950 = Color(hex: 0x050A18)
    static let char900 = Color(hex: 0x081022)
    static let char850 = Color(hex: 0x0B1530)
    static let char700 = Color(hex: 0x1A2A52)
    static let creme = Color(hex: 0xF2F6FF)
    static let creme2 = Color(hex: 0xC9D4EA)
    static let muted = Color(hex: 0x8493B0)
    static let gold = Color(hex: 0xFFC531)
    static let goldHi = Color(hex: 0xFFE48A)
    static let ember = Color(hex: 0xFF7A1A)

    static func display(_ size: CGFloat) -> Font { .custom("LuckiestGuy-Regular", size: size) }
    static func round(_ size: CGFloat) -> Font { .custom("Fredoka-Bold", size: size) }

    static func registerFonts() {
        for f in ["LuckiestGuy-Regular", "Fredoka-Bold"] {
            if let url = Bundle.main.url(forResource: f, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// The charcoal card every widget sits on.
struct Card: View {
    var glow: Color = .clear
    var body: some View {
        ZStack {
            LinearGradient(colors: [W.char850, W.char950], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [glow.opacity(0.32), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 190)
        }
    }
}

private struct Kicker: View {
    let text: String
    var body: some View { Text(text).font(W.round(11)).kerning(1.4).foregroundStyle(W.muted).lineLimit(1) }
}

// MARK: - timeline: one entry an hour (the streak countdown + today's square change with the clock)

struct Entry: TimelineEntry {
    let date: Date
    let snap: WidgetSnapshot
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: Date(), snap: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: Date(), snap: WidgetSnapshot.load() ?? .sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let snap = WidgetSnapshot.load() ?? WidgetSnapshot()
        let now = Date()
        let hour = Calendar.current.dateInterval(of: .hour, for: now)!.start
        let entries = [Entry(date: now, snap: snap)] + (1...24).map { Entry(date: hour.addingTimeInterval(Double($0) * 3600), snap: snap) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - 1. STREAK

struct StreakView: View {
    @Environment(\.widgetFamily) private var envFamily
    let entry: Entry
    var forced: WidgetFamily? = nil          // the render check sets the size (scripts in notes/34)
    private var family: WidgetFamily { forced ?? envFamily }

    var body: some View {
        let s = AirStreak.compute(entry.snap.trained, now: entry.date)
        let left = s.deadline.map { $0.timeIntervalSince(entry.date) } ?? 0
        let urgent = s.alive && !s.keptToday && left < 86_400
        switch family {
        case .accessoryCircular: circular(s)
        case .accessoryRectangular: rectangular(s, urgent: urgent)
        default: small(s, urgent: urgent)
        }
    }

    private func small(_ s: AirStreak, urgent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Kicker(text: "STREAK")
                Spacer()
                Flame(lit: s.alive, size: 30)
            }
            Spacer(minLength: 0)
            HStack(alignment: .lastTextBaseline, spacing: 5) {
                Text("\(s.days)").font(W.display(52)).foregroundStyle(urgent ? W.gold : W.creme)
                    .minimumScaleFactor(0.6).lineLimit(1)
                Text(s.days == 1 ? "DAY" : "DAYS").font(W.display(16)).foregroundStyle(urgent ? W.gold : W.creme2)
            }
            Spacer(minLength: 4)
            status(s, urgent: urgent)
        }
        .containerBackground(for: .widget) { Card(glow: s.alive ? (urgent ? W.ember : W.gold) : .clear) }
        .widgetURL(URL(string: "soccermax://stats"))
    }

    @ViewBuilder private func status(_ s: AirStreak, urgent: Bool) -> some View {
        if !s.alive {
            Text("Train 10 min to light it").font(W.round(12)).foregroundStyle(W.creme2).lineLimit(2)
        } else if s.keptToday {
            Label("LIT TODAY", systemImage: "checkmark.seal.fill").font(W.round(12)).foregroundStyle(W.brand)
        } else if urgent, let d = s.deadline {
            HStack(spacing: 4) {
                Text("OUT IN").font(W.round(11)).foregroundStyle(W.gold)
                Text(d, style: .timer).font(.system(size: 13, weight: .heavy, design: .monospaced)).monospacedDigit()
                    .foregroundStyle(W.gold)
            }
        } else {
            FuelBar(minutes: s.today)
        }
    }

    private func circular(_ s: AirStreak) -> some View {
        Gauge(value: s.alive ? max(0.08, s.air(entry.date)) : 0) {
            Image(systemName: "flame.fill")
        } currentValueLabel: {
            Text("\(s.days)").font(.system(size: 20, weight: .heavy, design: .rounded))
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: "soccermax://stats"))
    }

    private func rectangular(_ s: AirStreak, urgent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Label("\(s.days) DAY STREAK", systemImage: "flame.fill").font(.system(size: 15, weight: .heavy, design: .rounded))
            if !s.alive { Text("Train 10 min to light it") }
            else if s.keptToday { Text("Lit today") }
            else if urgent, let d = s.deadline { Text("Out in \(Text(d, style: .timer))") }
            else { Text("\(Int(s.today)) of 10 min today") }
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: "soccermax://stats"))
    }
}

/// The streak's fire, drawn with the flame symbol: gold?ember when lit, a grey ember when out.
private struct Flame: View {
    let lit: Bool
    let size: CGFloat
    var body: some View {
        Image(systemName: "flame.fill")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(lit ? AnyShapeStyle(LinearGradient(colors: [W.goldHi, W.gold, W.ember], startPoint: .top, endPoint: .bottom))
                                 : AnyShapeStyle(W.char700))
    }
}

/// Today's minutes toward the 10 that keep the fire lit.
private struct FuelBar: View {
    let minutes: Double
    var body: some View {
        let p = min(1, minutes / AirStreak.keep)
        VStack(alignment: .leading, spacing: 4) {
            Text("\(Int(minutes)) / 10 MIN TODAY").font(W.round(11)).kerning(0.6).foregroundStyle(W.creme2)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(W.char700)
                    Capsule().fill(W.brand).frame(width: max(p > 0 ? 6 : 0, g.size.width * p))
                }
            }
            .frame(height: 6)
        }
    }
}

struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "streak", provider: Provider()) { StreakView(entry: $0) }
            .configurationDisplayName("Streak")
            .description("Your fire. Train 10 minutes at least once every 3 days to keep it lit.")
            .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - 2. MATCH OF THE DAY (no score ? the film tells it)

struct MatchView: View {
    @Environment(\.widgetFamily) private var envFamily
    let entry: Entry
    var forced: WidgetFamily? = nil          // the render check sets the size (scripts in notes/34)
    private var family: WidgetFamily { forced ?? envFamily }

    var body: some View {
        Group {
            if let m = entry.snap.match {
                if family == .systemMedium { medium(m) } else { small(m) }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Kicker(text: "MATCH OF THE DAY")
                    Spacer()
                    Text("No game picked yet. Train today and check back.").font(W.round(13)).foregroundStyle(W.creme2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .containerBackground(for: .widget) { Card(glow: W.brand) }
        .widgetURL(URL(string: entry.snap.match.map { "soccermax://match/\($0.id)" } ?? "soccermax://match"))
    }

    private func small(_ m: WidgetSnapshot.Match) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Kicker(text: "MATCH OF THE DAY")
            Spacer(minLength: 6)
            VStack(alignment: .leading, spacing: 7) {
                team("home", m.home, size: 26)
                team("away", m.away, size: 26)
            }
            Spacer(minLength: 6)
            WatchPill(m: m, long: false)
        }
    }

    private func medium(_ m: WidgetSnapshot.Match) -> some View {
        VStack(spacing: 0) {
            HStack {
                Kicker(text: "MATCH OF THE DAY")
                Spacer()
                Text(m.league.uppercased()).font(W.round(11)).kerning(0.8).foregroundStyle(W.muted).lineLimit(1)
            }
            Spacer(minLength: 4)
            HStack(alignment: .center, spacing: 6) {
                side("home", m.home)
                Text("VS").font(W.display(22)).foregroundStyle(W.muted)
                side("away", m.away)
            }
            Spacer(minLength: 4)
            HStack {
                Text(dayText(m.date)).font(W.round(11)).foregroundStyle(W.muted)
                Spacer()
                WatchPill(m: m, long: true)
            }
        }
    }

    private func team(_ key: String, _ name: String, size: CGFloat) -> some View {
        HStack(spacing: 8) {
            Crest(side: key, size: size)
            Text(name.uppercased()).font(W.display(14)).foregroundStyle(W.creme).lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private func side(_ key: String, _ name: String) -> some View {
        VStack(spacing: 6) {
            Crest(side: key, size: 46)
            Text(name.uppercased()).font(W.display(14)).foregroundStyle(W.creme).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    private func dayText(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "TODAY" }
        if cal.isDateInYesterday(d) { return "LAST NIGHT" }
        return d.formatted(.dateTime.weekday(.wide)).uppercased()
    }
}

private struct WatchPill: View {
    let m: WidgetSnapshot.Match
    let long: Bool
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: m.watched ? "checkmark" : "play.fill").font(.system(size: 10, weight: .heavy))
            Text(m.watched ? "WATCHED" : long ? "WATCH · \(m.minutes) MIN" : "\(m.minutes) MIN")
                .font(W.round(12)).kerning(0.6)
        }
        .foregroundStyle(m.watched ? W.brand : W.char950)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(m.watched ? W.char700 : W.brand))
    }
}

/// A club crest the app saved into the shared folder (a grey disc until it has).
private struct Crest: View {
    let side: String
    let size: CGFloat
    var body: some View {
        if let url = WidgetSnapshot.crest(side), let img = UIImage(contentsOfFile: url.path) {
            Image(uiImage: img).resizable().scaledToFit().frame(width: size, height: size)
        } else {
            Circle().fill(W.char700).frame(width: size, height: size)
                .overlay(Image(systemName: "shield.fill").font(.system(size: size * 0.45)).foregroundStyle(W.muted))
        }
    }
}

struct MatchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "match", provider: Provider()) { MatchView(entry: $0) }
            .configurationDisplayName("Match of the Day")
            .description("Last night's best game, ready to watch as a film.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - 3. CONSISTENCY: a square per day

struct ConsistencyView: View {
    @Environment(\.widgetFamily) private var envFamily
    let entry: Entry
    var forced: WidgetFamily? = nil          // the render check sets the size (scripts in notes/34)
    private var family: WidgetFamily { forced ?? envFamily }

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: entry.date)
        let monday = addDays(today, -((cal.component(.weekday, from: today) + 5) % 7))
        let trained = entry.snap.trained
        let thisWeek = (0..<7).filter { (trained[dateKey(addDays(monday, $0))] ?? 0) >= AirStreak.keep }.count

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Kicker(text: "CONSISTENCY")
                Spacer()
                Text("\(thisWeek)/7").font(W.display(16)).foregroundStyle(thisWeek > 0 ? W.brand : W.muted)
                if family == .systemMedium {
                    Text("THIS WEEK").font(W.round(11)).foregroundStyle(W.muted)
                }
            }
            GeometryReader { g in
                if family == .systemMedium { weeksAcross(g.size, monday: monday, today: today) }
                else { weeksDown(g.size, monday: monday, today: today) }
            }
            if family == .systemMedium { legend }
        }
        .containerBackground(for: .widget) { Card() }
        .widgetURL(URL(string: "soccermax://stats"))
    }

    /// Medium: Mon?Sun rows, one column per week, this week on the right (like a year-in-squares).
    private func weeksAcross(_ size: CGSize, monday: Date, today: Date) -> some View {
        let gap: CGFloat = 3
        let cell = (size.height - gap * 6) / 7
        let weeks = max(1, Int((size.width + gap) / (cell + gap)))
        return HStack(spacing: gap) {
            ForEach(0..<weeks, id: \.self) { w in
                VStack(spacing: gap) {
                    ForEach(0..<7, id: \.self) { d in
                        square(addDays(monday, (w - weeks + 1) * 7 + d), today: today, size: cell)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// Small: Mon?Sun columns, one row per week, this week at the bottom (a little calendar).
    private func weeksDown(_ size: CGSize, monday: Date, today: Date) -> some View {
        let gap: CGFloat = 3
        let cell = min((size.width - gap * 6) / 7, 18)
        let weeks = max(1, Int((size.height + gap) / (cell + gap)))
        return VStack(spacing: gap) {
            ForEach(0..<weeks, id: \.self) { w in
                HStack(spacing: gap) {
                    ForEach(0..<7, id: \.self) { d in
                        square(addDays(monday, (w - weeks + 1) * 7 + d), today: today, size: cell)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    /// Green = trained 10+ min (kept the fire), faded green = some, dark = no training, faint = still to come.
    private func square(_ d: Date, today: Date, size: CGFloat) -> some View {
        let t = entry.snap.trained[dateKey(d)] ?? 0
        let fill: Color = d > today ? W.char850 : t >= AirStreak.keep ? W.brand : t > 0 ? W.brand.opacity(0.35) : W.char700
        return RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(fill)
            .overlay(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .stroke(d == today ? W.creme : .clear, lineWidth: 1.5))
            .frame(width: size, height: size)
    }

    private var legend: some View {
        HStack(spacing: 12) {
            key(W.brand, "TRAINED")
            key(W.brand.opacity(0.35), "A LITTLE")
            key(W.char700, "MISSED")
        }
    }

    private func key(_ c: Color, _ s: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 9, height: 9)
            Text(s).font(W.round(10)).kerning(0.6).foregroundStyle(W.muted)
        }
    }
}

struct ConsistencyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "consistency", provider: Provider()) { ConsistencyView(entry: $0) }
            .configurationDisplayName("Consistency")
            .description("A square for every day. Green means you trained.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) { StreakWidget() } timeline: { Entry(date: .now, snap: .sample) }
#Preview(as: .systemMedium) { MatchWidget() } timeline: { Entry(date: .now, snap: .sample) }
#Preview(as: .systemMedium) { ConsistencyWidget() } timeline: { Entry(date: .now, snap: .sample) }
