import SwiftUI
import WidgetKit

@main
struct KinetixWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        WeekWidget()
        LoadWidget()
        if #available(iOS 18.0, *) {
            WorkoutLiveActivityWithWatch()
        } else {
            WorkoutLiveActivity()
        }
    }
}
