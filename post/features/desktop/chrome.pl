%% desktop/chrome — repairs born from real incidents: the vanished menu
%% entry and the Wayland-poisoned Ozone preference. (The password-store pin
%% belongs to desktop/no-keyring — it dies with that policy, not with Chrome.)

%% The google-chrome-stable package ships two desktop entries:
%% google-chrome.desktop (the visible menu entry) and
%% com.google.Chrome.desktop (NoDisplay=true helper). If the visible one
%% goes missing, Chrome vanishes from the app menu; reinstalling the
%% package restores the file dpkg still claims to own.
config_patch(chrome_menu_entry,
    '/usr/bin/google-chrome',
    "test -f /usr/share/applications/google-chrome.desktop",
    "apt-get install --reinstall -y google-chrome-stable").
%% Chrome persists a "Preferred Ozone platform" choice in its profile; a
%% Wayland/Auto value saved during a Wayland session makes Chrome try the
%% nonexistent wayland-0 socket in an X11 session and exit. Resetting to
%% Default lets Chrome follow the actual session. Chrome must not be
%% running during the rewrite (it saves Local State on exit).
config_patch(chrome_ozone_default, '/usr/bin/google-chrome', Check, Fix) :-
    user_home(Home),
    format(atom(Check),
        "! grep -q ozone-platform-hint '~w/.config/google-chrome/Local State' 2>/dev/null",
        [Home]),
    run_as_user(User),
    format(atom(Fix),
        "jq '.browser.enabled_labs_experiments |= ((. // []) | map(select(startswith(\"ozone\") | not)))' '~w/.config/google-chrome/Local State' > '~w/.config/google-chrome/Local State.tmp' && mv '~w/.config/google-chrome/Local State.tmp' '~w/.config/google-chrome/Local State' && chown ~w:~w '~w/.config/google-chrome/Local State'",
        [Home, Home, Home, Home, User, User, Home]).
