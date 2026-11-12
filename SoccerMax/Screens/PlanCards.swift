// Plan building blocks ? the habit-tracker look. The week is a rail of date medallions whose rings fill as sets
// get ticked; each training day is a chunky card with its drills fanned like a hand of cards; a done day turns
// into mowed pitch and the rail between two done days turns green (don't break the chain). Rest days stay quiet.
import SwiftUI

// MARK: - ring + medallion

/// A progress ring that fills in when it appears and springs to every change.
struct Ring: View {
    var progress: Double
    var lineWidth: CGFloat
    var track: Color = C.char950
    var fill: Color? = nil
    var dashed = false
    @State private var shown = 0.0

    var body: some View {
        ZStack {
            Circle().stroke(track, style: StrokeStyle(lineWidth: dashed ? lineWidth * 0.4 : lineWidth, dash: dashed ? [3, 4.5] : []))
            Circle()
                .trim(from: 0, to: shown)
                .stroke(fill.map { AnyShapeStyle($0) } ?? AnyShapeStyle(AngularGradient(colors: [C.brandMid, C.brand, C.brandHi], center: .center)),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
        .onAppear { withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) { shown = progress } }
        .onChange(of: progress) { _, p in withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) { shown = p } }
    }
}

/// The date (or a count) on a ring. Done = a green coin with a check, like a medal you earned.
struct DayMedallion: View {
    let label: String
    let state: DayState
    var progress: Double = 0
    var halo = false
    var size: CGFloat = 58

    var body: some View {
        ZStack {
            if halo { Halo(size: size) }
            if state == .done { coin } else { ring }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if state == .done { CheckBadge(size: max(16, size * 0.38)).offset(x: size * 0.06, y: size * 0.06) }
        }
    }

    private var labelText: some View {
        let s = size * (label.count > 2 ? 0.27 : 0.36)
        return Text(label)
            .font(F.display(s))
            .foregroundStyle(state == .done ? .white : state == .missed || state == .rest ? C.muted : C.creme)
            .shadow(color: state == .done ? C.brandInk : C.charInk.opacity(state == .rest ? 0 : 1), radius: 0, y: max(1.5, s * 0.08))
            .offset(y: s * 0.06)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private var ring: some View {
        let lw = size * (state == .rest ? 0.07 : 0.11)
        return ZStack {
            Circle().fill(state == .rest ? C.char900 : C.charInk)
            Ring(progress: progress, lineWidth: lw, track: state == .rest ? C.char600 : C.char950,
                 fill: state == .missed ? C.char600 : nil, dashed: state == .rest)
                .padding(state == .rest ? 0 : 2.5)
            Circle()
                .fill(LinearGradient(colors: state == .rest ? [.clear] : [C.char700, C.char800], startPoint: .top, endPoint: .bottom))
                .padding(lw + 5)
            labelText
        }
    }

    private var coin: some View {
        ZStack {
            Circle().fill(C.brandLip).overlay(Circle().stroke(C.brandInk, lineWidth: 2.5)).offset(y: 3)
            Circle().fill(LinearGradient(colors: [C.brandHi, C.brand, C.brandMid], startPoint: .top, endPoint: .bottom))
            Circle().inset(by: size * 0.09).stroke(.white.opacity(0.35), lineWidth: 2)
                .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center))
            Circle().stroke(C.brandInk, lineWidth: 2.5)
            labelText
        }
    }
}

/// Today's pulse: a ring that keeps breathing out of the medallion.
struct Halo: View {
    let size: CGFloat
    @State private var on = false
    var body: some View {
        Circle()
            .stroke(C.brand, lineWidth: 3)
            .frame(width: size, height: size)
            .scaleEffect(on ? 1.38 : 1)
            .opacity(on ? 0 : 0.7)
            .onAppear { withAnimation(.easeOut(duration: 1.9).repeatForever(autoreverses: false)) { on = true } }
    }
}

struct CheckBadge: View {
    var size: CGFloat = 22
    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: size * 0.48, weight: .black))
            .foregroundStyle(C.brandMid)
            .frame(width: size, height: size)
            .background(Circle().fill(C.creme))
            .overlay(Circle().stroke(C.charInk, lineWidth: 2))
    }
}

// MARK: - card pieces

/// The day's drills fanned out like a hand of cards ? the first drill in front.
struct CoverFan: View {
    let drills: [Drill]
    var w: CGFloat = 40
    var h: CGFloat = 52

    var body: some View {
        let shown = Array(drills.prefix(3))
        let n = shown.count
        let step = w * 0.5
        ZStack {
            ForEach(Array(shown.enumerated()), id: \.offset) { i, d in
                let k = n == 1 ? 0 : Double(i) - Double(n - 1) / 2
                let order = n == 2 ? Double(-i) : -abs(k)
                Cover(drill: d)
                    .frame(width: w, height: h)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(C.charInk, lineWidth: 2))
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
                    .rotationEffect(.degrees(n == 1 ? 5 : k * 11), anchor: .bottom)
                    .offset(x: k * step, y: abs(k) * 4)
                    .zIndex(order)
            }
        }
        .frame(width: w + CGFloat(max(0, n - 1)) * step + 14, height: h + 12)
    }
}

/// Mowed-pitch bands across a done card.
struct MowedStripes: View {
    var band: CGFloat = 24
    var body: some View {
        Canvas { ctx, size in
            let slant = size.height * 0.3
            var x = -slant
            var i = 0
            while x < size.width + slant {
                if i.isMultiple(of: 2) {
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: size.height))
                    p.addLine(to: CGPoint(x: x + slant, y: 0))
                    p.addLine(to: CGPoint(x: x + slant + band, y: 0))
                    p.addLine(to: CGPoint(x: x + band, y: size.height))
                    p.closeSubpath()
                    ctx.fill(p, with: .color(.white.opacity(0.085)))
                }
                x += band
                i += 1
            }
        }
        .allowsHitTesting(false)
    }
}

/// Chalk markings ? the halfway line and centre circle ? so every card reads as a pitch.
struct ChalkLines: View {
    var opacity: Double
    var body: some View {
        Canvas { ctx, size in
            let x = size.width * 0.74
            let r = size.height * 0.46
            var p = Path()
            p.move(to: CGPoint(x: x, y: -4))
            p.addLine(to: CGPoint(x: x, y: size.height + 4))
            p.addEllipse(in: CGRect(x: x - r, y: size.height / 2 - r, width: r * 2, height: r * 2))
            ctx.stroke(p, with: .color(.white.opacity(opacity)), lineWidth: 2)
            ctx.fill(Path(ellipseIn: CGRect(x: x - 3, y: size.height / 2 - 3, width: 6, height: 6)), with: .color(.white.opacity(opacity * 1.4)))
        }
        .allowsHitTesting(false)
    }
}

/// A card's face for a day state: charcoal, today's green edge, or done's green pitch.
struct DaySurface: View {
    let state: DayState
    var radius: CGFloat = 22
    var chalk = true

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            if state == .done {
                shape.fill(LinearGradient(colors: [Color(hex: 0x4D9BFF), C.brand, C.brandMid], startPoint: .top, endPoint: .bottom))
                MowedStripes().clipShape(shape)
                if chalk { ChalkLines(opacity: 0.2).clipShape(shape) }
                shape.inset(by: 3).stroke(.white.opacity(0.3), lineWidth: 2)
                    .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center))
            } else {
                shape.fill(LinearGradient(colors: state == .missed ? [C.char850, C.char850] : [C.char800, C.char850], startPoint: .top, endPoint: .bottom))
                if chalk { ChalkLines(opacity: state == .missed ? 0.025 : 0.055).clipShape(shape) }
                shape.inset(by: 2.5).stroke(.white.opacity(state == .missed ? 0.02 : 0.05), lineWidth: 1.5)
                    .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center))
            }
            shape.stroke(state == .done ? C.brandInk : state == .today ? C.brand : C.charInk, lineWidth: 2.5)
        }
    }

    static func lip(_ s: DayState) -> Color { s == .done || s == .today ? C.brandLip : C.charInk }
}

/// Cards sit on a darker lip and sink onto it when pressed (the game buttons' feel).
struct LipPress: ButtonStyle {
    var lip: Color = C.charInk
    var radius: CGFloat = 22
    var depth: CGFloat = 5
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed ? depth - 1 : 0)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(lip)
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(C.line, lineWidth: 1))
                    .offset(y: depth)
            )
            .padding(.bottom, depth)
            .animation(.spring(response: 0.18, dampingFraction: 0.55), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, down in Haptics.play(down ? .press : .stud) }
    }
}

// MARK: - the week rail

/// One day on the week rail: the medallion on the line, then the day's card (or a quiet rest line).
struct WeekRow: View {
    let day: String
    /// The rail above / below this day: nil = none, true = green (both training days around it done).
    var up: Bool?
    var down: Bool?
    @Environment(AppStore.self) private var store

    var body: some View {
        let state = store.state(day)
        let today = day == todayKey()
        HStack(spacing: 12) {
            NavigationLink(value: PlanRoute.day(day)) {
                DayMedallion(label: "\(dayNumber(day))", state: state, progress: store.progress(day),
                             halo: today && state != .done, size: state == .rest ? 40 : 58)
                    .frame(width: 60)
            }
            .buttonStyle(.press(.stud))
            NavigationLink(value: PlanRoute.day(day)) {
                if state == .rest { rest(today) } else { card(state, today) }
            }
            .buttonStyle(LipPress(lip: state == .rest ? .clear : DaySurface.lip(state), depth: state == .rest ? 0 : 5))
        }
        .padding(.vertical, state == .rest ? 4 : 7)
        .background(alignment: .topLeading) { rail }
    }

    private func card(_ state: DayState, _ today: Bool) -> some View {
        let items = store.items(day)
        let done = store.doneSets(day), total = store.totalSets(day), min = store.minutes(day)
        let sub: String = switch state {
        case .done: "Done · \(min) min"
        case .today: done > 0 ? "Today · \(done) of \(total) sets" : "Today · \(min) min"
        case .missed: done > 0 ? "\(done) of \(total) sets" : "Missed"
        default: store.label(day).map { "\($0) · \(min) min" } ?? "\(items.count) drill\(items.count == 1 ? "" : "s") · \(min) min"
        }
        return HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 5) {
                Text(FULL_DAY[day] ?? day)
                    .font(F.display(20))
                    .foregroundStyle(state == .done ? .white : state == .missed ? C.muted : C.creme)
                    .shadow(color: state == .done ? C.brandInk : C.charInk, radius: 0, y: 2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(sub)
                    .font(F.round(14, .semibold))
                    .foregroundStyle(state == .done ? C.brandInk : state == .today ? C.brand : C.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            CoverFan(drills: items.map { Library.shared.drill($0.drill) })
                .opacity(state == .missed ? 0.55 : 1)
                .saturation(state == .missed ? 0.3 : 1)
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(height: 84)
        .background(DaySurface(state: state))
        .contentShape(Rectangle())
    }

    private func rest(_ today: Bool) -> some View {
        HStack(spacing: 8) {
            Text(today ? "Today" : (FULL_DAY[day] ?? day).capitalized)
                .font(F.round(16, .semibold))
                .foregroundStyle(today ? C.brand : C.muted)
            Text("· Rest").font(F.round(16, .semibold)).foregroundStyle(C.char600)
            Spacer()
            Image(systemName: "moon.zzz.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(C.char600)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(today ? C.brand.opacity(0.6) : C.char700, style: StrokeStyle(lineWidth: 1.5, dash: [5, 5])))
        .contentShape(Rectangle())
    }

    /// The line through the medallions; green where the chain is unbroken.
    private var rail: some View {
        GeometryReader { g in
            let mid = g.size.height / 2
            ZStack(alignment: .topLeading) {
                if let up {
                    Capsule().fill(up ? C.brand : C.char700).frame(width: 4, height: mid + 1).offset(x: 28, y: 0)
                }
                if let down {
                    Capsule().fill(down ? C.brand : C.char700).frame(width: 4, height: mid + 1).offset(x: 28, y: mid)
                }
            }
        }
    }
}

/// The streak on the Plan header: a gold flame and the count.
struct StreakChip: View {
    let n: Int
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(n > 0 ? AnyShapeStyle(LinearGradient(colors: [C.goldHi, C.gold, C.goldMid], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(C.muted))
                .symbolEffect(.bounce, value: n)
            Text("\(n)")
                .font(F.display(23))
                .foregroundStyle(C.creme)
                .shadow(color: C.charInk, radius: 0, y: 2)
                .contentTransition(.numericText())
                .offset(y: 2)
        }
        .padding(.leading, 13)
        .padding(.trailing, 15)
        .frame(height: 46)
        .background(Capsule().fill(LinearGradient(colors: [C.char700, C.char800], startPoint: .top, endPoint: .bottom)))
        .overlay(Capsule().stroke(C.line, lineWidth: 1))
        .background(Capsule().fill(C.charInk).offset(y: 4))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(n) sessions in a row")
    }
}

// MARK: - hero

/// The one hero on the Plan tab and a day page: the day's first drill's setup in 3D, its ring, one line, one button.
struct DayHero<Action: View>: View {
    let day: String
    var stageHeight: CGFloat = 200
    /// The drill names under the title (off on a day page, where the drills are listed right below).
    var names = true
    @ViewBuilder var action: Action
    @Environment(AppStore.self) private var store

    var body: some View {
        let items = store.items(day)
        let state = store.state(day)
        let today = day == todayKey()
        let done = store.doneSets(day), total = store.totalSets(day)
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .top) {
                if let first = items.first {
                    StageBox(params: .setup(id: first.drill), height: stageHeight)
                        .overlay(alignment: .bottom) {
                            LinearGradient(colors: [Self.floor.opacity(0), Self.floor], startPoint: .top, endPoint: .bottom)
                                .frame(height: 36)
                                .allowsHitTesting(false)
                        }
                } else {
                    RestArt().frame(height: 176)
                }
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        if today || (state != .rest && state != .before) {
                            Text(today ? "TODAY" : eyebrow(state))
                                .font(F.display(17))
                                .foregroundStyle(today || state == .done ? C.brand : C.creme2)
                                .shadow(color: C.charInk, radius: 0, y: 2)
                        }
                        Text("\((FULL_DAY[day] ?? day).prefix(3)) · \(shortDate(day))")
                            .font(F.round(13, .bold)).kerning(1.2)
                            .foregroundStyle(C.creme2.opacity(0.8))
                    }
                    Spacer()
                    if !items.isEmpty {
                        DayMedallion(label: "\(done)/\(total)", state: state == .done ? .done : .today,
                                     progress: store.progress(day), size: 62)
                    }
                }
                .padding(16)
            }
            VStack(alignment: .leading, spacing: 6) {
                Disp(title(items, state), size: 28)
                Text(note(items, state, total))
                    .font(F.round(15, .semibold))
                    .foregroundStyle(C.muted)
                    .lineLimit(1)
                action.padding(.top, 8)
            }
            .padding(16)
        }
        .background(Self.floor)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(C.line, lineWidth: 1))
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(C.charInk).offset(y: 5))
    }

    /// The 3D floor's colour where it fades out, so stage and card read as one dark screen.
    static var floor: Color { Color(hex: 0x14191D) }

    private func eyebrow(_ s: DayState) -> String {
        switch s {
        case .done: "DONE"
        case .missed: "MISSED"
        default: "COMING UP"
        }
    }

    private func title(_ items: [PlanItem], _ s: DayState) -> String {
        if items.isEmpty { return "REST DAY" }
        if s == .done { return "SESSION DONE" }
        if let l = store.label(day), store.raw(day).isEmpty { return l.uppercased() }
        return "\(items.count) DRILL\(items.count == 1 ? "" : "S") · \(store.minutes(day)) MIN"
    }

    private func note(_ items: [PlanItem], _ s: DayState, _ total: Int) -> String {
        let next = nextTraining.map { "Next up: \($0.capitalized)" }
        if items.isEmpty { return next ?? "Nothing planned this week yet" }
        if s == .done { return "All \(total) sets done" + (next.map { " · \($0)" } ?? "") }
        if !names {
            let done = store.doneSets(day)
            if done > 0 { return "\(done) of \(total) sets done" }
            return store.label(day) != nil && store.raw(day).isEmpty ? "\(items.count) drills · \(store.minutes(day)) min · \(total) sets" : "\(total) sets · tap a drill to change it"
        }
        let names = items.map { Library.shared.drill($0.drill).name }.joined(separator: " · ")
        return store.label(day) != nil && store.raw(day).isEmpty ? "\(store.minutes(day)) min · \(names)" : names
    }

    /// The next day with drills after this one (wrapping into next week).
    private var nextTraining: String? {
        let i = DAYS.firstIndex(of: day) ?? 0
        return (1...7).map { DAYS[(i + $0) % 7] }.first { !store.items($0).isEmpty }.flatMap { FULL_DAY[$0] }
    }
}

/// A rest day's hero: the ball asleep.
struct RestArt: View {
    @State private var float = false
    var body: some View {
        ZStack {
            Circle().fill(C.brand.opacity(0.13)).frame(width: 150, height: 150).blur(radius: 36)
            Ellipse().fill(.black.opacity(0.45)).frame(width: 78, height: 13).blur(radius: 3).offset(y: 44)
            BallGlyph(size: 80)
            Image(systemName: "zzz")
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(C.creme2)
                .offset(x: 56, y: float ? -60 : -46)
                .opacity(float ? 0.35 : 0.9)
        }
        .frame(maxWidth: .infinity)
        .onAppear { withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { float = true } }
    }
}

/// Fades content out under the status bar on screens without a nav bar.
struct TopScrim: View {
    var body: some View {
        GeometryReader { g in
            LinearGradient(stops: [.init(color: C.char900, location: 0), .init(color: C.char900.opacity(0.92), location: 0.55),
                                   .init(color: C.char900.opacity(0), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: g.safeAreaInsets.top + 18)
                .offset(y: -g.safeAreaInsets.top)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - the week ball hero

/// The Plan tab's centrepiece: this week's ball on the centre spot, the panel count, then today in one line + one button.
struct WeekBallHero<Action: View>: View {
    var onTapDay: (String) -> Void
    @ViewBuilder var action: Action
    @Environment(AppStore.self) private var store

    var body: some View {
        let ball = store.weekBall
        let day = todayKey()
        let items = store.items(day)
        let state = store.state(day)
        let done = store.doneSets(day), total = store.totalSets(day)
        VStack(spacing: 0) {
            ZStack {
                CentreSpot().frame(height: 80).offset(y: 128)
                WeekBall(model: ball, size: 252, onTapDay: onTapDay)
            }
            .frame(height: 300)
            .frame(maxWidth: .infinity)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Disp("\(ball.stitched)", size: 44, color: ball.stitched == WeekBallModel.count ? C.brand : C.creme)
                    .contentTransition(.numericText())
                Disp("/ \(WeekBallModel.count)", size: 22, color: C.muted)
            }
            Text(ball.stitched == WeekBallModel.count ? "BALL FINISHED · WEEK DONE" : "PANELS STITCHED · ONE PER SET")
                .font(F.round(12, .bold)).kerning(1.6)
                .foregroundStyle(ball.stitched == WeekBallModel.count ? C.brand : C.muted)
                .padding(.top, 2)

            // Today, in one line and one button.
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TODAY · \((FULL_DAY[day] ?? day).prefix(3)) \(shortDate(day))")
                        .font(F.round(12, .bold)).kerning(1.4)
                        .foregroundStyle(C.brand)
                    Text(items.isEmpty ? "REST DAY" : state == .done ? "SESSION DONE" : "\(items.count) DRILL\(items.count == 1 ? "" : "S") · \(store.minutes(day)) MIN")
                        .font(F.display(22))
                        .foregroundStyle(C.creme)
                        .shadow(color: C.charInk, radius: 0, y: 2)
                    Text(items.isEmpty ? "The ball rests too" : store.label(day) ?? items.map { Library.shared.drill($0.drill).name }.joined(separator: " · "))
                        .font(F.round(14, .semibold)).foregroundStyle(C.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
                if !items.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(0..<min(total, 8), id: \.self) { i in
                            PanelMark(state: i < done ? .stitched : state == .today ? .next : .empty, pent: i.isMultiple(of: 3), size: 15)
                        }
                    }
                }
            }
            .padding(.top, 26)
            action.padding(.top, 14)
        }
    }
}
