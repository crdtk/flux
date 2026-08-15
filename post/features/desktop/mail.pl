%% desktop/mail — Thunderbird as the credential-holding mail proxy.
%% Decision (2026-08-14): mail credentials/OAuth/sync live in Thunderbird
%% alone; the CLI reads mail through its Gloda full-text index
%% (global-messages-db.sqlite, opened READ-ONLY — consumer: `make
%% mail-search`, the one file allowed to know the Gloda schema; the
%% schema is private and dies with the Panorama rewrite, so the whole
%% read path must stay disposable). Nothing outside Thunderbird ever
%% writes mail state. Deleting this module revokes the proxy decision.

%% The archive's `thunderbird` (2:1snap1) is a snap-transitional shell —
%% uninstallable here (snapd purged+pinned, debloat.pl) and a decoy by
%% construction. Mozilla's official tarball is the real deb-free path,
%% same pattern as blender_official: /opt + /usr/local/bin symlink +
%% desktop entry; the bundle self-updates in place.
opt_install(thunderbird_official, '/opt/thunderbird/thunderbird', Cmd) :-
    downloads_dir(DDir),
    format(atom(Cmd),
        "curl -fsSL 'https://download.mozilla.org/?product=thunderbird-latest&os=linux64&lang=en-US' -o ~w/thunderbird-latest.tar.xz && mkdir -p /opt/thunderbird && tar -xaf ~w/thunderbird-latest.tar.xz -C /opt/thunderbird --strip-components=1 && ln -sf /opt/thunderbird/thunderbird /usr/local/bin/thunderbird && mkdir -p /usr/local/share/applications && printf '[Desktop Entry]\\nName=Thunderbird\\nExec=/usr/local/bin/thunderbird %%u\\nIcon=/opt/thunderbird/chrome/icons/default/default128.png\\nType=Application\\nCategories=Network;Email;\\nMimeType=x-scheme-handler/mailto;message/rfc822;\\n' > /usr/local/share/applications/thunderbird.desktop && (update-desktop-database /usr/local/share/applications 2>/dev/null || true)",
        [DDir, DDir]).

%% ATN add-ons, system-wide: tb_addon(Name, ATNSlug, GUID) is the whole
%% catalog — adding an add-on is adding one fact. The generic clause
%% below fetches ATN's version-independent latest-XPI URL into
%% distribution/extensions/ (auto-installs into every profile on next
%% start; the filename MUST be the GUID or the channel ignores it),
%% guarded on the /opt binary so rules wait for the tarball install.
%%
%% Both translators send text to Google's servers — a stated trade-off
%% accepted 2026-08-14 (on-device Bergamot is on Thunderbird's roadmap,
%% unshipped; delete these facts when it lands). Two DISSIMILAR backends
%% (Translate vs Gemini) so one service degrading doesn't take both.
%% thunderbird-translate's Gemini API key is pasted in the add-on's own
%% settings — human-only (XXIV), never a POST artifact.
tb_addon(buxar_translate,       buxartranslate,          'buxarnet@yandex.com').
tb_addon(thunderbird_translate, 'thunderbird-translate', 'thunderbird-translate@sully-vian').

config_patch(Name, '/opt/thunderbird/thunderbird', Check, Fix) :-
    tb_addon(Name, Slug, Guid),
    format(atom(Check),
        "test -s '/opt/thunderbird/distribution/extensions/~w.xpi'", [Guid]),
    format(atom(Fix),
        "mkdir -p /opt/thunderbird/distribution/extensions && curl -fsSL 'https://addons.thunderbird.net/thunderbird/downloads/latest/~w/addon-latest.xpi' -o '/opt/thunderbird/distribution/extensions/~w.xpi'",
        [Slug, Guid]).

%% Gloda must stay ON in every profile or the search seam silently goes
%% stale. user.js is the safe write (read at startup, never touched by a
%% live Thunderbird — prefs.js is); the pin overrides any GUI opt-out.
%% No profiles yet ⇒ nothing to configure ⇒ pass (the advisory below
%% owns that story).
user_config(gloda_enabled, Check, Fix) :-
    user_home(Home),
    format(atom(Check),
        "for d in ~w/.thunderbird/*/; do test -f \"$d/prefs.js\" || continue; grep -qs 'mailnews.database.global.indexer.enabled\", true' \"$d/user.js\" || exit 1; done",
        [Home]),
    format(atom(Fix),
        "for d in ~w/.thunderbird/*/; do test -f \"$d/prefs.js\" || continue; grep -qs 'mailnews.database.global.indexer.enabled\", true' \"$d/user.js\" || printf 'user_pref(\"mailnews.database.global.indexer.enabled\", true);\\n' >> \"$d/user.js\"; done",
        [Home]).

%% The account wizard is skippable: a Thunderbird account is a pref
%% graph, and user.js seeds it before first start. Identity comes from
%% git config (user.name/user.email — sensed at APPLY time, never
%% assumed); the server half is Gmail's fixed IMAP/SMTP endpoints with
%% authMethod 10 (OAuth2). The graph is all-or-nothing: a partial seed
%% confuses the Account Manager, so one printf writes the whole block.
%% Profiles the wizard already configured (accountmanager.accounts in
%% prefs.js) are left alone. No profile yet ⇒ -CreateProfile makes one
%% headlessly. Stable pref namespace (enterprise/NixOS territory) — no
%% Panorama expiry, unlike the Gloda seam.
user_config(mail_account_seed, Check, Fix) :-
    user_home(Home),
    format(atom(Check),
        "EMAIL=$(git config --get user.email) && grep -qs \"useremail\\\", \\\"$EMAIL\" ~w/.thunderbird/*/user.js ~w/.thunderbird/*/prefs.js",
        [Home, Home]),
    format(atom(Fix),
        "EMAIL=$(git config --get user.email) && NAME=$(git config --get user.name) && ls -d ~w/.thunderbird/*/ >/dev/null 2>&1 || thunderbird --headless -CreateProfile default >/dev/null 2>&1; for d in ~w/.thunderbird/*/; do test -f \"$d/prefs.js\" && grep -qs 'mail.accountmanager.accounts' \"$d/prefs.js\" && continue; grep -qs \"useremail\\\", \\\"$EMAIL\" \"$d/user.js\" || printf 'user_pref(\"mail.accountmanager.accounts\", \"account1\");\\nuser_pref(\"mail.accountmanager.defaultaccount\", \"account1\");\\nuser_pref(\"mail.account.account1.server\", \"server1\");\\nuser_pref(\"mail.account.account1.identities\", \"id1\");\\nuser_pref(\"mail.identity.id1.fullName\", \"%s\");\\nuser_pref(\"mail.identity.id1.useremail\", \"%s\");\\nuser_pref(\"mail.identity.id1.smtpServer\", \"smtp1\");\\nuser_pref(\"mail.server.server1.type\", \"imap\");\\nuser_pref(\"mail.server.server1.name\", \"%s\");\\nuser_pref(\"mail.server.server1.hostname\", \"imap.googlemail.com\");\\nuser_pref(\"mail.server.server1.port\", 993);\\nuser_pref(\"mail.server.server1.socketType\", 3);\\nuser_pref(\"mail.server.server1.userName\", \"%s\");\\nuser_pref(\"mail.server.server1.authMethod\", 10);\\nuser_pref(\"mail.smtpservers\", \"smtp1\");\\nuser_pref(\"mail.smtpserver.smtp1.hostname\", \"smtp.googlemail.com\");\\nuser_pref(\"mail.smtpserver.smtp1.port\", 587);\\nuser_pref(\"mail.smtpserver.smtp1.try_ssl\", 2);\\nuser_pref(\"mail.smtpserver.smtp1.authMethod\", 10);\\nuser_pref(\"mail.smtpserver.smtp1.username\", \"%s\");\\n' \"$NAME\" \"$EMAIL\" \"$EMAIL\" \"$EMAIL\" \"$EMAIL\" >> \"$d/user.js\"; done",
        [Home, Home]).

%% Thunderbird starts with the session (XDG autostart): Gloda indexes
%% only while the app runs, so a login-started Thunderbird is what keeps
%% `make mail-search` current instead of minutes-to-days stale. Content
%% probe on the Exec line, not mere file existence (XXI).
user_config(thunderbird_autostart, Check, Fix) :-
    user_home(Home),
    format(atom(Check),
        "grep -qs 'Exec=/usr/local/bin/thunderbird' ~w/.config/autostart/thunderbird.desktop",
        [Home]),
    format(atom(Fix),
        "mkdir -p ~w/.config/autostart && printf '[Desktop Entry]\\nName=Thunderbird\\nExec=/usr/local/bin/thunderbird\\nType=Application\\nX-KDE-StartupNotify=false\\n' > ~w/.config/autostart/thunderbird.desktop",
        [Home, Home]).

%% Account setup is OAuth-in-browser — human-only (XXIV): WARN and name
%% the step; never emit it as a command. Until the first sync completes,
%% no Gloda db exists and mail-search has nothing to read.
advisory(user_config, gloda_index, 'no Gloda index yet — launch thunderbird once, add the account (OAuth in-app), let it sync; then `make mail-search Q=...`') :-
    user_home(Home),
    format(atom(Probe), "ls ~w/.thunderbird/*/global-messages-db.sqlite >/dev/null 2>&1", [Home]),
    \+ shell_ok(Probe).
