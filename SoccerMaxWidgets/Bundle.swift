// The widget extension's entry point (views in Widgets.swift, notes/34).
import SwiftUI
import WidgetKit

// MARK: - the bundle

@main
struct SoccerMaxWidgets: WidgetBundle {
    init() { W.registerFonts() }
    var body: some Widget {
        StreakWidget()
        MatchWidget()
        ConsistencyWidget()
        SessionLiveActivity()
    }
}

