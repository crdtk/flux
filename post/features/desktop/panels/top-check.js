// Drift probe, run inside plasmashell: prints OK when every screen has a
// top bar, else MISSING<n>. Same constraint as top.js: no $ or backtick.
var have = panels().filter(function(q) { return q.location == "top"; }).map(function(q) { return q.screen; });
var m = 0;
for (var i = 0; i < screenCount; i++) { if (have.indexOf(i) < 0) { m += 1; } }
print(m == 0 ? "OK" : "MISSING" + m);
