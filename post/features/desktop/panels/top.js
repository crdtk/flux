// Top bar on EVERY screen — see panels.pl for the rationale of each slot.
// Passed to plasmashell via "$(cat top.js)": no $ or backtick anywhere in
// this file (bash would expand them inside the double quotes).
function mkTop(s) {
    var p = new Panel;
    p.location = "top";
    p.screen = s;
    p.addWidget("com.github.chrtall.kppleMenu");

    var t = p.addWidget("com.github.antroids.application-title-bar");
    t.currentConfigGroup = ["Appearance"];
    t.writeConfig("widgetElements", ["windowTitle"]);
    t.writeConfig("overrideElementsMaximized", true);
    t.writeConfig("widgetElementsMaximized", ["windowCloseButton", "windowMinimizeButton", "windowMaximizeButton", "windowTitle"]);
    t.writeConfig("windowTitleSource", 0);
    t.writeConfig("windowTitleSourceMaximized", 0);
    t.writeConfig("windowTitleFontSize", 10);
    t.writeConfig("windowTitleUndefined", "Plasma");

    p.addWidget("org.kde.plasma.appmenu");
    p.addWidget("org.kde.plasma.panelspacer");

    var n = p.addWidget("org.kde.plasma.systemmonitor");
    n.currentConfigGroup = ["Appearance"];
    n.writeConfig("chartFace", "org.kde.ksysguard.textonly");
    n.writeConfig("title", "Net");
    n.currentConfigGroup = ["Sensors"];
    n.writeConfig("highPrioritySensorIds", ["network/all/download", "network/all/upload"]);

    var s = p.addWidget("org.kde.plasma.systemtray");
    s.currentConfigGroup = ["General"];
    s.writeConfig("extraItems", ["org.kde.plasma.volume", "org.kde.plasma.brightness", "org.kde.plasma.mediacontroller", "org.kde.plasma.networkmanagement"]);
    s.writeConfig("knownItems", ["org.kde.plasma.weather"]);

    var c = p.addWidget("org.kde.plasma.digitalclock");
    c.currentConfigGroup = ["Appearance"];
    c.writeConfig("dateDisplayFormat", "BesideTime");
    c.writeConfig("use24hFormat", 2);
    c.writeConfig("autoFontAndSize", false);
    c.writeConfig("fontSize", 14);
    c.writeConfig("dateFormat", "custom");
    c.writeConfig("customDateFormat", "dd.MM.yy |");

    // right wing, hand-arranged 2026-08-16 and adopted verbatim:
    // status/utility singles the tray popup would hide a click away
    p.addWidget("org.kde.kupapplet");
    p.addWidget("org.kde.plasma.clipboard");
    p.addWidget("org.kde.kscreen");
    p.addWidget("org.kde.plasma.systemmonitor.cpucore");
    p.addWidget("org.kde.kdeconnect");
    p.addWidget("org.kde.plasma.systemmonitor.net");
    p.addWidget("org.kde.plasma.notifications");
    p.addWidget("org.kde.plasma.printmanager");
    p.addWidget("org.kde.plasma.battery");

    var w2 = p.addWidget("org.kde.plasma.weather");
    w2.currentConfigGroup = ["WeatherStation"];
    w2.writeConfig("provider", "dwd");
    w2.writeConfig("placeInfo", "Berlin-Alex.|10389");
    w2.writeConfig("placeDisplayName", "Berlin-Alex.");
    w2.currentConfigGroup = ["Appearance"];
    w2.writeConfig("showTemperatureInCompactMode", true);

    p.addWidget("org.kde.plasma.brightness");
}

var have = panels().filter(function(q) { return q.location == "top"; }).map(function(q) { return q.screen; });
for (var i = 0; i < screenCount; i++) { if (have.indexOf(i) < 0) { mkTop(i); } }
