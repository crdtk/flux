// Auto-hide dock (kickoff + dashboard + icontasks). No $ or backtick.
var d = new Panel;
d.location = "bottom";
d.height = 60;
d.hiding = "autohide";
d.lengthMode = "fit";
d.floating = false;
d.opacity = "opaque";
d.addWidget("org.kde.plasma.kickoff");
d.addWidget("org.kde.plasma.applicationdashboard");
d.addWidget("org.kde.plasma.icontasks");
