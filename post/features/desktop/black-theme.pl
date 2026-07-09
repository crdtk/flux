%% desktop/black-theme — everything #000000: whole-desktop truly-black
%% scheme derived from BreezeDark (keeps its light foregrounds) and the
%% Terminator profile to match.

user_config(crucible_black, Check, Fix) :-
    user_home(Home),
    format(atom(Check),
        "test -f ~w/.local/share/color-schemes/CrucibleBlack.colors", [Home]),
    format(atom(Fix),
        "mkdir -p ~w/.local/share/color-schemes && sed -E 's/^(BackgroundNormal|BackgroundAlternate|activeBackground|inactiveBackground)=.*/\\1=0,0,0/; s/^Name=.*/Name=Crucible Black/; s/^ColorScheme=.*/ColorScheme=CrucibleBlack/' /usr/share/color-schemes/BreezeDark.colors > ~w/.local/share/color-schemes/CrucibleBlack.colors && (plasma-apply-colorscheme CrucibleBlack 2>/dev/null || true)",
        [Home, Home]).
user_config(terminator_black, Check, Fix) :-
    user_home(Home),
    format(atom(Check), "test -f ~w/.config/terminator/config", [Home]),
    format(atom(Fix),
        "mkdir -p ~w/.config/terminator && printf '%s\\n' '[profiles]' '  [[default]]' '    background_color = \"#000000\"' '    background_type = solid' '    foreground_color = \"#ffffff\"' > ~w/.config/terminator/config",
        [Home, Home]).
