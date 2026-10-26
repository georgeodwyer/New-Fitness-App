import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

module Colors {
    const ACCENT = 0xF47B20;
    const GOOD = 0x2ECC40;
    const WARN = 0xFAB219;
    const GREY = 0xAAAAAA;
    const DARK = 0x555555;
}

// Pick a run: this week's planned runs from Kinetix (today first), then a free run.
// Up/Down to choose, Start to begin.
class HomeView extends WatchUi.View {
    var store;
    var index = 0;

    function initialize(theStore) {
        View.initialize();
        store = theStore;
    }

    function count() {
        return store.sessions.size() + 1;
    }

    // The chosen session, or null for a free run.
    function selected() {
        if (index < store.sessions.size()) { return store.sessions[index]; }
        return null;
    }

    function move(by) {
        index = (index + by + count()) % count();
        WatchUi.requestUpdate();
    }

    function onShow() {
        if (index >= count()) { index = 0; }
    }

    function onUpdate(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        dc.setColor(Colors.ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.13, Graphics.FONT_XTINY, "KINETIX", center);

        var session = selected();
        if (session == null) {
            dc.setColor(Colors.GREY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.28, Graphics.FONT_TINY, "Any time", center);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.42, Graphics.FONT_MEDIUM, "Free run", center);
            dc.setColor(Colors.GREY, Graphics.COLOR_TRANSPARENT);
            if (store.sessions.size() == 0) {
                var line1 = store.lastPlanAt == 0 ? "Open Kinetix on your" : "No planned runs";
                var line2 = store.lastPlanAt == 0 ? "iPhone to send your plan" : "this week";
                dc.drawText(w / 2, h * 0.55, Graphics.FONT_XTINY, line1, center);
                dc.drawText(w / 2, h * 0.62, Graphics.FONT_XTINY, line2, center);
            } else {
                dc.drawText(w / 2, h * 0.55, Graphics.FONT_XTINY, "No targets, laps on Back", center);
            }
        } else {
            dc.setColor(Colors.GREY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.28, Graphics.FONT_TINY, Format.day(session["day"]), center);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            var title = session["n"] == null ? "Run" : session["n"];
            var font = dc.getTextWidthInPixels(title, Graphics.FONT_MEDIUM) <= w * 0.8 ? Graphics.FONT_MEDIUM : Graphics.FONT_SMALL;
            dc.drawText(w / 2, h * 0.42, font, Format.fit(dc, title, font, w * 0.82), center);
            var detail = session["d"] == null ? "" : session["d"];
            dc.setColor(Colors.GREY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.55, Graphics.FONT_XTINY, Format.fit(dc, detail, Graphics.FONT_XTINY, w * 0.78), center);
            var steps = session["st"];
            if (steps instanceof Lang.Array && steps.size() > 1) {
                dc.drawText(w / 2, h * 0.62, Graphics.FONT_XTINY, steps.size() + " steps", center);
            }
        }

        dc.setColor(Colors.ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.75, Graphics.FONT_SMALL, "START to begin", center);
        dc.setColor(Colors.DARK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.87, Graphics.FONT_XTINY, (index + 1) + " of " + count() + "  UP/DOWN", center);
    }
}

class HomeDelegate extends WatchUi.BehaviorDelegate {
    var store;
    var view;

    function initialize(theStore, theView) {
        BehaviorDelegate.initialize();
        store = theStore;
        view = theView;
    }

    function onNextPage() {
        view.move(1);
        return true;
    }

    function onPreviousPage() {
        view.move(-1);
        return true;
    }

    function onSelect() {
        var workout = new Workout(store, view.selected());
        WatchUi.pushView(new WorkoutView(workout), new WorkoutDelegate(workout), WatchUi.SLIDE_LEFT);
        return true;
    }
}
