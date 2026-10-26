import Toybox.Application.Storage;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Time;

// The plan from the iPhone (kept on the watch so it works without the phone nearby) and
// finished runs waiting to be confirmed by the phone. Message format: GarminSync.swift.
class SessionStore {
    var sessions = [];
    var units = "km";
    var tolerance = 10;
    var cueDelay = 20;
    var cuesOn = true;
    var pending = [];
    var lastPlanAt = 0;

    function initialize() {
        var value = Storage.getValue("sessions");
        if (value != null) { sessions = value; }
        value = Storage.getValue("units");
        if (value != null) { units = value; }
        value = Storage.getValue("tolerance");
        if (value != null) { tolerance = value; }
        value = Storage.getValue("cueDelay");
        if (value != null) { cueDelay = value; }
        value = Storage.getValue("cuesOn");
        if (value != null) { cuesOn = value; }
        value = Storage.getValue("pending");
        if (value != null) { pending = value; }
        value = Storage.getValue("lastPlanAt");
        if (value != null) { lastPlanAt = value; }
        dropPast();
    }

    // Sessions from today on (the plan is sent for the next week).
    function dropPast() {
        var today = Time.today().value();
        var kept = [];
        for (var i = 0; i < sessions.size(); i++) {
            var day = sessions[i]["day"];
            if (day == null || day >= today - 3600) { kept.add(sessions[i]); }
        }
        sessions = kept;
    }

    function receive(data) {
        if (!(data instanceof Lang.Dictionary)) { return; }
        var type = data["t"];
        if (type == null) { return; }
        if (type.equals("plan")) {
            var list = data["s"];
            sessions = (list instanceof Lang.Array) ? list : [];
            if (data["u"] != null) { units = data["u"]; }
            if (data["tol"] != null) { tolerance = data["tol"]; }
            if (data["cue"] != null) { cueDelay = data["cue"]; }
            if (data["cues"] != null) { cuesOn = data["cues"] == 1; }
            lastPlanAt = Time.now().value();
            dropPast();
            Storage.setValue("sessions", sessions);
            Storage.setValue("units", units);
            Storage.setValue("tolerance", tolerance);
            Storage.setValue("cueDelay", cueDelay);
            Storage.setValue("cuesOn", cuesOn);
            Storage.setValue("lastPlanAt", lastPlanAt);
        } else if (type.equals("ack")) {
            var rid = data["rid"];
            var kept = [];
            for (var i = 0; i < pending.size(); i++) {
                if (rid == null || !rid.equals(pending[i]["rid"])) { kept.add(pending[i]); }
            }
            pending = kept;
            Storage.setValue("pending", pending);
        }
    }

    function sayHello() {
        Communications.transmit({"t" => "hello", "v" => 1}, null, new KinetixListener());
    }

    // A finished run: kept until the phone says it's saved (the newest five at most).
    function addResult(result) {
        pending.add(result);
        while (pending.size() > 5) { pending = pending.slice(1, null); }
        Storage.setValue("pending", pending);
        sendPending();
    }

    function sendPending() {
        for (var i = 0; i < pending.size(); i++) {
            Communications.transmit(pending[i], null, new KinetixListener());
        }
    }

    function isMiles() {
        return "mi".equals(units);
    }
}

class KinetixListener extends Communications.ConnectionListener {
    function initialize() {
        Communications.ConnectionListener.initialize();
    }

    function onComplete() {
    }

    // Not sent (phone away or Kinetix closed): results are sent again next time.
    function onError() {
    }
}
