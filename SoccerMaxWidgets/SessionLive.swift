// The running session on the lock screen and in the Dynamic Island (Shared/SessionActivity.swift).
import ActivityKit
import SwiftUI
import WidgetKit

struct SessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { ctx in
            LockView(session: ctx.attributes.session, s: ctx.state)
                .activityBackgroundTint(W.char900)
                .activitySystemActionForegroundColor(W.creme)
                .widgetURL(URL(string: "soccermax://session"))
        } dynamicIsland: { ctx in
            let s = ctx.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DRILL \(s.index + 1) OF \(s.count)").font(W.round(12)).foregroundStyle(W.muted)
                        Text(s.drill.uppercased()).font(W.display(18)).foregroundStyle(W.creme).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LiveClock(s: s, size: 26).padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Segments(s: s).padding(.horizontal, 4).padding(.top, 6)
                }
            } compactLeading: {
                Image(systemName: s.paused == nil ? "soccerball" : "pause.fill").foregroundStyle(s.paused == nil ? W.brand : W.gold)
            } compactTrailing: {
                LiveClock(s: s, size: 15).frame(maxWidth: 52)
            } minimal: {
                Image(systemName: s.paused == nil ? "soccerball" : "pause.fill").foregroundStyle(s.paused == nil ? W.brand : W.gold)
            }
            .keylineTint(W.brand)
        }
    }
}

private struct LockView: View {
    let session: String
    let s: SessionActivityAttributes.ContentState
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(session.uppercased()) · \(s.index + 1)/\(s.count)").font(W.round(12)).foregroundStyle(W.muted).lineLimit(1)
                    Text(s.drill.uppercased()).font(W.display(22)).foregroundStyle(W.creme).lineLimit(1).minimumScaleFactor(0.6)
                    Text(s.dose).font(W.round(13)).foregroundStyle(W.brand).lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    LiveClock(s: s, size: 34)
                    if s.paused != nil { Text("PAUSED").font(W.round(11)).foregroundStyle(W.gold) }
                }
            }
            Segments(s: s)
        }
        .padding(16)
    }
}

/// Counts up by itself while running (the system ticks it); frozen while paused.
private struct LiveClock: View {
    let s: SessionActivityAttributes.ContentState
    let size: CGFloat
    var body: some View {
        Group {
            if let p = s.paused {
                Text(clock(p)).foregroundStyle(W.gold)
            } else {
                Text(timerInterval: s.startedAt...Date.distantFuture, countsDown: false).foregroundStyle(W.brand)
            }
        }
        .font(.system(size: size, weight: .heavy, design: .rounded))
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
    }
}

private struct Segments: View {
    let s: SessionActivityAttributes.ContentState
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(1, s.count), id: \.self) { i in
                Capsule()
                    .fill(i < s.index ? W.brand : i == s.index ? W.brandHi : W.char700)
                    .frame(height: 5)
            }
        }
    }
}
