%% desktop/no-keyring — the NO-KEYRING POLICY (decided 2026-07-08, see
%% memory: project-kwallet-pam): kdewallet is decommissioned and no Secret
%% Service replaces it. Secrets come from the invoking environment
%% (getenv-gated rules, XXII). Keyring-API consumers fall back per app:
%% Chrome/VS Code get --password-store=basic. kwallet6 itself cannot be
%% purged (hard dependency of plasma-workspace/KIO — removal takes 106
%% packages) so it is neutralized: PAM unlock stripped, satellites purged,
%% wallet data archived. Revoking this decision: delete this file, move
%% kwalletd.decommissioned back, re-enable in kwalletrc.

hardening_check(kwallet_decommissioned,
    "! dpkg -s libpam-kwallet5 >/dev/null 2>&1 && ! grep -rq pam_kwallet /etc/pam.d/ 2>/dev/null",
    "apt-get purge -y kwalletmanager libpam-kwallet5 libpam-kwallet-common signon-kwallet-extension 2>/dev/null || true; grep -rl pam_kwallet /etc/pam.d/ 2>/dev/null | xargs -r sed -i '/pam_kwallet/d'").

%% Chrome on a KDE desktop autodetects kwallet6 for Safe Storage; with the
%% wallet gone it must be pinned to the basic store or it prompts/warns.
config_patch(chrome_password_store,
    '/usr/bin/google-chrome',
    "grep -q 'password-store=basic' /usr/share/applications/google-chrome.desktop 2>/dev/null",
    "sed -i 's|/usr/bin/google-chrome-stable|/usr/bin/google-chrome-stable --password-store=basic|g' /usr/share/applications/google-chrome.desktop").

% Wallet disabled by content (not file existence — the original bug was an
% existence-only sentinel) and the wallet data moved aside, not deleted:
% kdewallet.kwl still holds the old Chrome/VS Code Safe Storage keys,
% PyCharm GitHub token and Kaggle creds, recoverable by moving the
% directory back and re-enabling.
user_config(kwallet_disabled, Check, Fix) :-
    user_home(Home),
    format(atom(Check),
        "grep -q '^Enabled=false' ~w/.config/kwalletrc 2>/dev/null && test ! -d ~w/.local/share/kwalletd",
        [Home, Home]),
    format(atom(Fix),
        "printf '[Wallet]\\nEnabled=false\\nFirst Use=false\\n' > ~w/.config/kwalletrc; test -d ~w/.local/share/kwalletd && mv ~w/.local/share/kwalletd ~w/.local/share/kwalletd.decommissioned; pkill kwalletd6 2>/dev/null; pkill kwalletd5 2>/dev/null; true",
        [Home, Home, Home, Home]).

% VS Code's argv.json is JSONC (ships with comments) — jq can't merge it, so
% the key is sed-inserted after the opening brace. "basic" = obfuscated
% on-disk storage, the deliberate trade-off of the no-keyring policy.
user_config(vscode_password_store, Check, Fix) :-
    user_home(Home),
    format(atom(Check),
        "grep -q '\"password-store\"' ~w/.vscode/argv.json 2>/dev/null", [Home]),
    format(atom(Fix),
        "if test -f ~w/.vscode/argv.json; then sed -i '0,/^{/s//{\\n\\t\"password-store\": \"basic\",/' ~w/.vscode/argv.json; else mkdir -p ~w/.vscode && printf '{\\n\\t\"password-store\": \"basic\"\\n}\\n' > ~w/.vscode/argv.json; fi",
        [Home, Home, Home, Home]).
