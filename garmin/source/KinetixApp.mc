import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.WatchUi;

// Kinetix for Garmin: runs the sessions from your Kinetix plan with pace targets, records
// them like any Garmin run (saved to Garmin Connect) and sends the result back to Kinetix
// on your iPhone through Garmin Connect.
class KinetixApp extends Application.AppBase {
    var store;

    function initialize() {
        AppBase.initialize();
        store = new SessionStore();
    }

    function onStart(state) {
        Communications.registerForPhoneAppMessages(method(:onPhoneMessage));
        // Ask the phone for the latest plan and send any results it hasn't confirmed.
        store.sayHello();
        store.sendPending();
    }

    function onStop(state) {
    }

    function getInitialView() {
        var view = new HomeView(store);
        return [view, new HomeDelegate(store, view)];
    }

    function onPhoneMessage(message) {
        store.receive(message.data);
        WatchUi.requestUpdate();
    }
}

function getApp() {
    return Application.getApp();
}
