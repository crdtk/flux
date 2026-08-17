%% desktop/mail — Thunderbird as the credential-holding mail proxy.
%% Decision (2026-08-14): mail credentials/OAuth/sync live in Thunderbird
%% alone. The CLI read path is thunderbird-cli (`tb`) over the bridge
%% below — live mailbox queries through Thunderbird's own extension API,
%% no private schema. (The Gloda SQL catalog was deleted 2026-08-17 by
%% the no-consumer rule; git history keeps it.) Nothing outside
%% Thunderbird ever writes mail state. Deleting this module revokes the
%% proxy decision.

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
%% Translators send text to external servers — a stated trade-off
%% accepted 2026-08-14 (on-device Bergamot is on Thunderbird's roadmap,
%% unshipped; delete these facts when it lands). Two DISSIMILAR backends
%% (Google Translate vs DeepL) so one service degrading doesn't take
%% both. 2026-08-17: thunderbird-translate (Gemini) replaced — Google
%% retired gemini-2.5-flash and v1.1 hardcodes it (404 on every call);
%% DeepL free API (500k chars/month) is the better engine for German
%% mail anyway. The DeepL API key is pasted in the add-on's own
%% settings — human-only (XXIV), never a POST artifact.
tb_addon(buxar_translate,      buxartranslate,          'buxarnet@yandex.com').
tb_addon(quicktranslate_deepl, 'quicktranslate-deepl',  'quicktranslate-deepl@jurdant.alexis').
%% Dead Gemini add-on: remove the stale system-wide XPI wherever present.
hardening_check(no_gemini_translate,
    "! test -e '/opt/thunderbird/distribution/extensions/thunderbird-translate@sully-vian.xpi'",
    "rm -f '/opt/thunderbird/distribution/extensions/thunderbird-translate@sully-vian.xpi'").

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

%% Thunderbird starts with the session (XDG autostart): the tb bridge
%% extension only lives while the app runs — a login-started Thunderbird
%% is what makes `tb` queries answerable at all (and keeps Gloda, TB's
%% own search index, current). Content probe on the Exec line, not mere
%% file existence (XXI).
user_config(thunderbird_autostart, Check, Fix) :-
    user_home(Home),
    format(atom(Check),
        "grep -qs 'Exec=/usr/local/bin/thunderbird' ~w/.config/autostart/thunderbird.desktop",
        [Home]),
    format(atom(Fix),
        "mkdir -p ~w/.config/autostart && printf '[Desktop Entry]\\nName=Thunderbird\\nExec=/usr/local/bin/thunderbird\\nType=Application\\nX-KDE-StartupNotify=false\\n' > ~w/.config/autostart/thunderbird.desktop",
        [Home, Home]).

%% Account setup is OAuth-in-browser — human-only (XXIV): WARN and name
%% the step; never emit it as a command. Until the first sync completes
%% there is no mailbox for tb (or TB's own search) to answer from.
advisory(user_config, mail_first_sync, 'no synced mailbox yet — launch thunderbird once, add the account (OAuth in-app), let it sync; then `tb search ...`') :-
    user_home(Home),
    format(atom(Probe), "ls ~w/.thunderbird/*/global-messages-db.sqlite >/dev/null 2>&1", [Home]),
    \+ shell_ok(Probe).

%% thunderbird-cli + bridge — live email queries over Thunderbird's
%% mailboxes. Requires: (1) two npm packages, (2) a signed XPI extension
%% in Thunderbird, (3) a persistent bridge daemon (tb-bridge). The bridge
%% is the IPC path between the CLI and Thunderbird's mailbox API.
opt_install(thunderbird_cli, '/usr/local/bin/tb', Cmd) :-
    Cmd = "npm install -g thunderbird-cli thunderbird-cli-bridge".

%% Bridge extension — signed by vitalio-sh, system-wide distribution.
%% Same pattern as tb_addon: downloaded to /opt/thunderbird/distribution/extensions
%% and auto-installs into every profile on next Thunderbird start.
config_patch(thunderbird_bridge_ext, '/opt/thunderbird/thunderbird', Check, Fix) :-
    Check = "test -s '/opt/thunderbird/distribution/extensions/thunderbird-ai@extension.xpi'",
    Fix   = "mkdir -p /opt/thunderbird/distribution/extensions && rm -f '/opt/thunderbird/distribution/extensions/thunderbird-ai-bridge@vitalio-sh.xpi' && curl -fsSL 'https://github.com/vitalio-sh/thunderbird-cli/releases/download/v1.0.2/thunderbird_ai_bridge-2.0.0-tb.xpi' -o '/opt/thunderbird/distribution/extensions/thunderbird-ai@extension.xpi'".

%% Install the bridge extension into every profile (backup to distribution
%% folder — ensures it's present even if the system-wide discovery fails).
user_config(thunderbird_bridge_in_profile, Check, Fix) :-
    user_home(Home),
    format(atom(Check),
        "for d in ~w/.thunderbird/*/extensions/; do test -f \"${d}thunderbird-ai@extension.xpi\" && exit 0; done; exit 1",
        [Home]),
    format(atom(Fix),
        "for d in ~w/.thunderbird/*/extensions/; do test -d \"$d\" && cp /opt/thunderbird/distribution/extensions/thunderbird-ai@extension.xpi \"$d\"; done",
        [Home]).

%% The bridge daemon as a supervised systemd user service: the extension
%% (a WebExtension — cannot spawn processes) dials 127.0.0.1:7701 with
%% retries, so "start with the extension" reduces to "the socket is
%% always there in the session". Restart=on-failure survives bridge
%% crashes; logs land in the user journal (journalctl --user -u
%% tb-bridge). Replaces the earlier unsupervised XDG-autostart entry.
user_config(thunderbird_bridge_daemon, Check, Fix) :-
    user_home(Home),
    format(atom(Check),
        "grep -qs 'ExecStart=/usr/local/bin/tb-bridge' ~w/.config/systemd/user/tb-bridge.service && systemctl --user is-enabled --quiet tb-bridge 2>/dev/null",
        [Home]),
    format(atom(Fix),
        "rm -f ~w/.config/autostart/thunderbird-bridge.desktop; mkdir -p ~w/.config/systemd/user && printf '[Unit]\\nDescription=thunderbird-cli bridge (tb <-> Thunderbird IPC)\\nPartOf=graphical-session.target\\n\\n[Service]\\nExecStart=/usr/local/bin/tb-bridge\\nRestart=on-failure\\nRestartSec=3\\n\\n[Install]\\nWantedBy=graphical-session.target\\n' > ~w/.config/systemd/user/tb-bridge.service && systemctl --user daemon-reload && systemctl --user enable --now tb-bridge",
        [Home, Home, Home]).
