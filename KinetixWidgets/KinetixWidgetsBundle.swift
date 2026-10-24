import SwiftUI
import WidgetKit

/// Picks the widget set for the iOS version. A widget bundle can't hold an `if #available`,
/// so iOS 18 gets its own bundle (with the Apple Watch layout for the workout Live Activity).
@main
enum KinetixWidgetsMain {
    static func main() {
        if #available(iOS 18.0, *) {
            KinetixWidgetsBundle18.main()
        } else {
            KinetixWidgetsBundle.main()
        }
    }
}

struct KinetixWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        WeekWidget()
        LoadWidget()
        WorkoutLiveActivity()
    }
}

@available(iOS 18.0, *)
struct KinetixWidgetsBundle18: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        WeekWidget()
        LoadWidget()
        WorkoutLiveActivityWithWatch()
    }
}
