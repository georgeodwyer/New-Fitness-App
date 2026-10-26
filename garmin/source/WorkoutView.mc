import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// The run screen: the step and its target, your pace (green on target, amber off it),
// what's left of the step, heart rate, and total time and distance.
class WorkoutView extends WatchUi.View {
    var workout;

    function initialize(theWorkout) {
        View.initialize();
        workout = theWorkout;
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        if (!workout.started) {
            drawReady(dc);
        } else {
            drawRunning(dc);
        }
    }

    function drawReady(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.25, Graphics.FONT_SMALL, Format.fit(dc, workout.title, Graphics.FONT_SMALL, w * 0.8), center);

        var gps = workout.gpsQuality;
        var gpsText = gps >= 3 ? "GPS ready" : (gps >= 2 ? "GPS: getting there" : "GPS: searching");
        dc.setColor(gps >= 3 ? Colors.GOOD : Colors.WARN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.40, Graphics.FONT_TINY, gpsText, center);

        if (workout.hasPlan()) {
            var first = workout.steps[0];
            dc.setColor(Colors.GREY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.53, Graphics.FONT_XTINY, "First: " + Format.stepName(workout.steps, 0) + " " +
                        stepLength(first), center);
        }
        dc.setColor(Colors.ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.70, Graphics.FONT_MEDIUM, "START", center);
        dc.setColor(Colors.DARK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.84, Graphics.FONT_XTINY, "BACK to cancel", center);
    }

    function stepLength(step) {
        if (step["m"] != null && step["m"] > 0) {
            return Format.remaining(step["m"], null, workout.miles);
        }
        return Format.duration(step["sec"]);
    }

    function drawRunning(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var miles = workout.miles;
        var step = workout.currentStep();

        // Top: the step, or paused.
        var top;
        if (!workout.running) {
            top = "PAUSED";
            dc.setColor(Colors.WARN, Graphics.COLOR_TRANSPARENT);
        } else if (step != null) {
            top = Format.stepName(workout.steps, workout.stepIndex);
            dc.setColor(Colors.ACCENT, Graphics.COLOR_TRANSPARENT);
        } else {
            top = workout.hasPlan() ? "Session done" : "Free run";
            dc.setColor(Colors.ACCENT, Graphics.COLOR_TRANSPARENT);
        }
        dc.drawText(w / 2, h * 0.12, Graphics.FONT_TINY, Format.fit(dc, top, Graphics.FONT_TINY, w * 0.6), center);

        // Target.
        var fastest = step == null ? null : step["f"];
        var hasTarget = fastest != null && fastest > 0;
        if (hasTarget) {
            dc.setColor(Colors.GREY, Graphics.COLOR_TRANSPARENT);
            var label = step["g"] == 1 ? "Guide " : "Target ";
            dc.drawText(w / 2, h * 0.22, Graphics.FONT_XTINY, label + Format.paceRange(step["f"], step["sl"], miles), center);
        }

        // Pace, coloured against the target.
        var pace = workout.pace;
        var color = Graphics.COLOR_WHITE;
        if (hasTarget && pace > 0 && step["g"] != 1) {
            var tolerance = workout.store.tolerance;
            var inRange = pace <= step["sl"] + tolerance && pace >= step["f"] - tolerance;
            color = inRange ? Colors.GOOD : Colors.WARN;
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.40, Graphics.FONT_NUMBER_HOT, Format.pace(pace, miles), center);
        dc.setColor(Colors.GREY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.53, Graphics.FONT_XTINY, "pace /" + Format.unit(miles), center);

        // Left: what's left of the step (or distance). Right: heart rate.
        var leftValue;
        var leftLabel;
        if (step != null) {
            var meters = workout.stepRemainingMeters();
            leftValue = meters != null ? Format.remaining(meters, null, miles) : Format.remaining(null, workout.stepRemainingSeconds(), miles);
            leftLabel = "to go";
        } else {
            leftValue = Format.distance(workout.distance, miles);
            leftLabel = Format.unit(miles);
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w * 0.32, h * 0.64, Graphics.FONT_MEDIUM, leftValue, center);
        dc.drawText(w * 0.70, h * 0.64, Graphics.FONT_MEDIUM, workout.heartRate == null ? "--" : workout.heartRate.format("%d"), center);
        dc.setColor(Colors.GREY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w * 0.32, h * 0.72, Graphics.FONT_XTINY, leftLabel, center);
        dc.drawText(w * 0.70, h * 0.72, Graphics.FONT_XTINY, "bpm", center);

        // Bottom: total time and distance, or a cue.
        var cue = workout.activeCue();
        if (cue != null) {
            dc.setColor(Colors.ACCENT, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(w * 0.18, h * 0.78, w * 0.64, h * 0.11, h * 0.05);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.835, Graphics.FONT_SMALL, Format.fit(dc, cue, Graphics.FONT_SMALL, w * 0.6), center);
        } else if (!workout.running) {
            dc.setColor(Colors.GREY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.82, Graphics.FONT_XTINY, "START resume  BACK finish", center);
        } else {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            var total = Format.duration(workout.timerSec) + "  " + Format.distance(workout.distance, miles) + " " + Format.unit(miles);
            dc.drawText(w / 2, h * 0.83, Graphics.FONT_SMALL, total, center);
        }
    }
}

class WorkoutDelegate extends WatchUi.BehaviorDelegate {
    var workout;

    function initialize(theWorkout) {
        BehaviorDelegate.initialize();
        workout = theWorkout;
    }

    // START/STOP: begin, then pause and resume.
    function onSelect() {
        if (!workout.started) {
            workout.start();
        } else {
            workout.toggle();
        }
        WatchUi.requestUpdate();
        return true;
    }

    // BACK/LAP: next step (or lap) while running; the finish menu when paused.
    function onBack() {
        if (!workout.started) {
            workout.cleanup();
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        } else if (workout.running) {
            workout.lapPressed();
        } else {
            showFinishMenu();
        }
        WatchUi.requestUpdate();
        return true;
    }

    function onMenu() {
        if (workout.started && !workout.running) { showFinishMenu(); }
        return true;
    }

    function showFinishMenu() {
        var menu = new WatchUi.Menu2({:title => "Run paused"});
        menu.addItem(new WatchUi.MenuItem("Save", "Sends it to Kinetix", :save, null));
        menu.addItem(new WatchUi.MenuItem("Resume", null, :resume, null));
        menu.addItem(new WatchUi.MenuItem("Discard", null, :discard, null));
        WatchUi.pushView(menu, new FinishMenuDelegate(workout), WatchUi.SLIDE_UP);
    }
}

class FinishMenuDelegate extends WatchUi.Menu2InputDelegate {
    var workout;

    function initialize(theWorkout) {
        Menu2InputDelegate.initialize();
        workout = theWorkout;
    }

    function onSelect(item) {
        var id = item.getId();
        if (id == :save) {
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            workout.finish(true);
            WatchUi.switchToView(new SummaryView(workout), new SummaryDelegate(), WatchUi.SLIDE_LEFT);
        } else if (id == :resume) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            workout.toggle();
        } else if (id == :discard) {
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            workout.finish(false);
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        }
    }
}

// After saving: the totals, and that it's on its way to Kinetix.
class SummaryView extends WatchUi.View {
    var workout;

    function initialize(theWorkout) {
        View.initialize();
        workout = theWorkout;
    }

    function onUpdate(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var miles = workout.miles;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(Colors.GOOD, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.16, Graphics.FONT_SMALL, "Saved", center);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.34, Graphics.FONT_NUMBER_MEDIUM, Format.distance(workout.distance, miles), center);
        dc.setColor(Colors.GREY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.46, Graphics.FONT_XTINY, Format.unit(miles), center);
        var average = workout.distance > 50 ? workout.timerSec / workout.distance * 1000.0 : 0;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.58, Graphics.FONT_SMALL,
                    Format.duration(workout.timerSec) + "  " + Format.pace(average, miles) + "/" + Format.unit(miles), center);
        dc.setColor(Colors.GREY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.72, Graphics.FONT_XTINY, "Sending to Kinetix", center);
        dc.drawText(w / 2, h * 0.79, Graphics.FONT_XTINY, "and Garmin Connect", center);
        dc.setColor(Colors.ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.89, Graphics.FONT_XTINY, "BACK when done", center);
    }
}

class SummaryDelegate extends WatchUi.BehaviorDelegate {
    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    function onSelect() {
        return onBack();
    }
}
