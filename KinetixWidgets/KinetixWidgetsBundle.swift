import SwiftUI
import WidgetKit

@main
struct KinetixWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        WeekWidget()
        LoadWidget()
        WorkoutLiveActivity()
    }
}
