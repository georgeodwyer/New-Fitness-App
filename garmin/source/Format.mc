import Toybox.Lang;
import Toybox.Math;
import Toybox.Time;
import Toybox.Time.Gregorian;

// Paces, times and distances the way Kinetix shows them.
module Format {
    const MILE = 1609.344;

    // "4:05" from seconds per km, in km or miles; "--:--" when there's no pace.
    function pace(secondsPerKm, miles) {
        if (secondsPerKm == null || secondsPerKm <= 0 || secondsPerKm > 1800) { return "--:--"; }
        var seconds = miles ? secondsPerKm * MILE / 1000.0 : secondsPerKm.toFloat();
        var whole = Math.round(seconds).toNumber();
        return (whole / 60).format("%d") + ":" + (whole % 60).format("%02d");
    }

    // "3:55-4:05" for a target range.
    function paceRange(fastest, slowest, miles) {
        return pace(fastest, miles) + "-" + pace(slowest, miles);
    }

    // "12:34" or "1:02:03".
    function duration(seconds) {
        if (seconds == null || seconds < 0) { seconds = 0; }
        var whole = Math.round(seconds).toNumber();
        var hours = whole / 3600;
        var minutes = (whole % 3600) / 60;
        var secs = whole % 60;
        if (hours > 0) {
            return hours.format("%d") + ":" + minutes.format("%02d") + ":" + secs.format("%02d");
        }
        return minutes.format("%d") + ":" + secs.format("%02d");
    }

    // "5.23" km or miles.
    function distance(meters, miles) {
        if (meters == null) { meters = 0; }
        var value = miles ? meters / MILE : meters / 1000.0;
        return value.format("%.2f");
    }

    function unit(miles) {
        return miles ? "mi" : "km";
    }

    // What's left of a step: "350 m" / "0.8 mi" by distance, "1:12" by time.
    function remaining(meters, seconds, miles) {
        if (meters != null) {
            if (meters < 0) { meters = 0; }
            if (miles) {
                return meters < 400 ? (meters * 1.09361).toNumber().format("%d") + " yd" : (meters / MILE).format("%.2f") + " mi";
            }
            return meters < 1000 ? Math.round(meters).toNumber().format("%d") + " m" : (meters / 1000.0).format("%.2f") + " km";
        }
        return duration(seconds);
    }

    // "Today", "Tomorrow" or "Wed".
    function day(epoch) {
        if (epoch == null) { return ""; }
        var today = Time.today().value();
        if (epoch < today + 86400) { return "Today"; }
        if (epoch < today + 2 * 86400) { return "Tomorrow"; }
        var info = Gregorian.info(new Time.Moment(epoch), Time.FORMAT_MEDIUM);
        return info.day_of_week.toString();
    }

    // A planned step's name: "Warm-up", "Rep 2 of 6", "Recovery", "Cool-down", or its label.
    function stepName(steps, index) {
        var step = steps[index];
        var kind = step["k"];
        if ("w".equals(kind)) {
            var count = 0;
            var number = 0;
            for (var i = 0; i < steps.size(); i++) {
                if ("w".equals(steps[i]["k"])) {
                    count += 1;
                    if (i == index) { number = count; }
                }
            }
            if (count > 1) { return "Rep " + number + " of " + count; }
        }
        var label = step["l"];
        if (label != null && label.length() > 0) { return label; }
        if ("u".equals(kind)) { return "Warm-up"; }
        if ("r".equals(kind)) { return "Recovery"; }
        if ("c".equals(kind)) { return "Cool-down"; }
        if ("w".equals(kind)) { return "Effort"; }
        return "Run";
    }

    // Shortens text to fit a width in a font.
    function fit(dc, text, font, width) {
        if (dc.getTextWidthInPixels(text, font) <= width) { return text; }
        var cut = text;
        while (cut.length() > 1 && dc.getTextWidthInPixels(cut + "...", font) > width) {
            cut = cut.substring(0, cut.length() - 1);
        }
        return cut + "...";
    }
}
