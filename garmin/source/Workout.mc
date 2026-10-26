import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.Attention;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.Sensor;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

// One run: steps from the plan with pace targets (or a free run), recorded as a Garmin
// running activity. The Lap (Back) button skips to the next step; once the steps are done,
// or on a free run, it marks a lap. Sends a result to the phone when saved.
class Workout {
    var store;
    var session;
    var steps = [];
    var title = "Run";
    var miles = false;

    var recorder = null;
    var timer = null;
    var started = false;
    var running = false;
    var done = false;
    var gpsQuality = 0;

    // Live values.
    var timerSec = 0.0;
    var distance = 0.0;
    var heartRate = null;
    var pace = 0.0;
    var history = [];

    // The current step.
    var stepIndex = 0;
    var stepStartTimer = 0.0;
    var stepStartDist = 0.0;
    var stepIn = 0;
    var stepMeasured = 0;
    var stepHrSum = 0;
    var stepHrCount = 0;
    var results = [];

    // Laps after the plan (or on a free run).
    var laps = [];
    var lapStartTimer = 0.0;
    var lapStartDist = 0.0;
    var lapHrSum = 0;
    var lapHrCount = 0;

    // Whole run.
    var startEpoch = 0;
    var hrSum = 0;
    var hrCount = 0;
    var hrMax = 0;
    var splits = [];
    var splitStartTimer = 0.0;
    var splitHrSum = 0;
    var splitHrCount = 0;

    // Coaching.
    var cue = null;
    var cueUntil = 0.0;
    var offSince = -1.0;
    var lastCueAt = -1000.0;
    var saved = false;

    function initialize(theStore, theSession) {
        store = theStore;
        session = theSession;
        miles = store.isMiles();
        if (session != null) {
            var list = session["st"];
            if (list instanceof Lang.Array) { steps = list; }
            if (session["n"] != null) { title = session["n"]; }
        } else {
            title = "Free run";
        }
        Sensor.setEnabledSensors([Sensor.SENSOR_HEARTRATE]);
        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
        timer = new Timer.Timer();
        timer.start(method(:tick), 1000, true);
    }

    function onPosition(info) {
        if (info != null && info.accuracy != null) { gpsQuality = info.accuracy; }
    }

    function hasPlan() {
        return steps.size() > 0;
    }

    function currentStep() {
        if (!hasPlan() || done) { return null; }
        return steps[stepIndex];
    }

    // MARK: Start, pause, finish

    function start() {
        var name = title.length() > 15 ? title.substring(0, 15) : title;
        recorder = ActivityRecording.createSession({
            :name => name,
            :sport => Activity.SPORT_RUNNING,
            :subSport => Activity.SUB_SPORT_GENERIC
        });
        recorder.start();
        started = true;
        running = true;
        startEpoch = Time.now().value();
        buzz(true);
        if (hasPlan()) { showCue(Format.stepName(steps, 0), 4); }
    }

    function toggle() {
        if (recorder == null) { return; }
        if (running) {
            recorder.stop();
            running = false;
            buzz(false);
        } else {
            recorder.start();
            running = true;
            buzz(false);
        }
    }

    // The Lap (Back) button while running.
    function lapPressed() {
        if (hasPlan() && !done) {
            advance();
        } else {
            closeLap();
            if (recorder != null) { recorder.addLap(); }
            buzz(false);
            showCue("Lap " + laps.size(), 3);
        }
    }

    function finish(save) {
        if (recorder == null) { cleanup(); return; }
        if (running) { recorder.stop(); running = false; }
        if (save) {
            if (hasPlan() && !done) { closeStep(); }
            if ((!hasPlan() || done) && laps.size() > 0 && timerSec - lapStartTimer > 5) { closeLap(); }
            recorder.save();
            saved = true;
            store.addResult(result());
        } else {
            recorder.discard();
        }
        cleanup();
    }

    // Stops GPS, sensors and the timer.
    function cleanup() {
        if (timer != null) { timer.stop(); timer = null; }
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
        Sensor.setEnabledSensors([]);
    }

    // MARK: Every second

    function tick() {
        var info = Activity.getActivityInfo();
        if (info != null) {
            if (info.timerTime != null) { timerSec = info.timerTime / 1000.0; }
            if (info.elapsedDistance != null) { distance = info.elapsedDistance; }
            heartRate = info.currentHeartRate;
            if (running) { update(info); }
        }
        WatchUi.requestUpdate();
    }

    function update(info) {
        // Pace over about the last 10 seconds (single readings jump about).
        history.add([timerSec, distance]);
        if (history.size() > 11) { history = history.slice(1, null); }
        var first = history[0];
        var seconds = timerSec - first[0];
        var meters = distance - first[1];
        if (history.size() >= 4 && meters > 5 && seconds > 0) {
            pace = seconds / meters * 1000.0;
        } else if (info.currentSpeed != null && info.currentSpeed > 0.5) {
            pace = 1000.0 / info.currentSpeed;
        } else {
            pace = 0.0;
        }

        if (heartRate != null && heartRate > 0) {
            hrSum += heartRate; hrCount += 1;
            stepHrSum += heartRate; stepHrCount += 1;
            splitHrSum += heartRate; splitHrCount += 1;
            lapHrSum += heartRate; lapHrCount += 1;
            if (heartRate > hrMax) { hrMax = heartRate; }
        }

        // Splits per km or mile.
        var unitMeters = miles ? Format.MILE : 1000.0;
        if (distance >= unitMeters * (splits.size() + 1)) {
            splits.add([Math.round(timerSec - splitStartTimer).toNumber(), average(splitHrSum, splitHrCount)]);
            splitStartTimer = timerSec;
            splitHrSum = 0;
            splitHrCount = 0;
        }

        var step = currentStep();
        if (step == null) { return; }
        coach(step);
        if (stepRemainingMeters() != null) {
            if (stepRemainingMeters() <= 0) { advance(); }
        } else if (stepRemainingSeconds() != null && stepRemainingSeconds() <= 0) {
            advance();
        }
    }

    // Time on target, and "Speed up" / "Ease off" after the cue delay.
    function coach(step) {
        var fastest = step["f"];
        var slowest = step["sl"];
        if (fastest == null || fastest <= 0 || pace <= 0) { offSince = -1.0; return; }
        var guide = step["g"] == 1;
        var tolerance = store.tolerance;
        var tooSlow = pace > slowest + tolerance;
        var tooFast = pace < fastest - tolerance;
        if (!guide) {
            stepMeasured += 1;
            if (!tooSlow && !tooFast) { stepIn += 1; }
        }
        var kind = step["k"];
        var cueable = store.cuesOn && !guide && ("w".equals(kind) || "s".equals(kind));
        if (!cueable || (!tooSlow && !tooFast)) { offSince = -1.0; return; }
        if (offSince < 0) { offSince = timerSec; }
        if (timerSec - offSince >= store.cueDelay && timerSec - lastCueAt >= store.cueDelay) {
            lastCueAt = timerSec;
            showCue(tooSlow ? "Speed up" : "Ease off", 5);
            buzz(false);
        }
    }

    function stepRemainingMeters() {
        var step = currentStep();
        if (step == null || step["m"] == null || step["m"] <= 0) { return null; }
        return step["m"] - (distance - stepStartDist);
    }

    function stepRemainingSeconds() {
        var step = currentStep();
        if (step == null || step["sec"] == null || step["sec"] <= 0) { return null; }
        return step["sec"] - (timerSec - stepStartTimer);
    }

    // On to the next step (or done).
    function advance() {
        closeStep();
        if (recorder != null) { recorder.addLap(); }
        stepIndex += 1;
        stepStartTimer = timerSec;
        stepStartDist = distance;
        stepIn = 0;
        stepMeasured = 0;
        stepHrSum = 0;
        stepHrCount = 0;
        offSince = -1.0;
        if (stepIndex >= steps.size()) {
            done = true;
            stepIndex = steps.size() - 1;
            lapStartTimer = timerSec;
            lapStartDist = distance;
            lapHrSum = 0;
            lapHrCount = 0;
            buzz(true);
            showCue("Session done", 6);
        } else {
            buzz(true);
            showCue(Format.stepName(steps, stepIndex), 4);
        }
    }

    function closeStep() {
        results.add({
            "i" => stepIndex,
            "dur" => Math.round(timerSec - stepStartTimer).toNumber(),
            "dist" => Math.round(distance - stepStartDist).toNumber(),
            "in" => stepIn,
            "ms" => stepMeasured,
            "hr" => average(stepHrSum, stepHrCount)
        });
    }

    function closeLap() {
        laps.add([
            Math.round(timerSec - lapStartTimer).toNumber(),
            Math.round(distance - lapStartDist).toNumber(),
            average(lapHrSum, lapHrCount)
        ]);
        lapStartTimer = timerSec;
        lapStartDist = distance;
        lapHrSum = 0;
        lapHrCount = 0;
    }

    function average(sum, count) {
        return count > 0 ? Math.round(sum.toFloat() / count).toNumber() : 0;
    }

    // What's sent to Kinetix on the phone (see GarminSync.swift).
    function result() {
        var id = "";
        var source = "free";
        if (session != null) {
            if (session["id"] != null) { id = session["id"]; }
            if (session["src"] != null) { source = session["src"]; }
        }
        return {
            "t" => "result",
            "rid" => startEpoch.format("%d") + "-" + (Math.rand() % 100000).format("%d"),
            "id" => id,
            "src" => source,
            "n" => session == null ? "" : title,
            "start" => startEpoch,
            "end" => Time.now().value(),
            "dur" => Math.round(timerSec).toNumber(),
            "dist" => Math.round(distance).toNumber(),
            "hr" => average(hrSum, hrCount),
            "hrx" => hrMax,
            "seg" => results,
            "spl" => splits,
            "lap" => laps
        };
    }

    // MARK: Alerts

    function showCue(text, seconds) {
        cue = text;
        cueUntil = timerSec + seconds;
    }

    function activeCue() {
        return (cue != null && timerSec <= cueUntil) ? cue : null;
    }

    function buzz(strong) {
        if (Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(strong ? 90 : 60, strong ? 600 : 250)]);
        }
        if (Attention has :playTone) {
            Attention.playTone(strong ? Attention.TONE_LAP : Attention.TONE_KEY);
        }
    }
}
