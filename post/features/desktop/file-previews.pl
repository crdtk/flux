%% desktop/file-previews — thumbnails in Dolphin and the file dialogs:
%% previews shown by default, video thumbnails via ffmpegthumbs (KF6
%% thumbcreator plugin; NOT in Dolphin's default plugin set, so it must be
%% added to PreviewSettings/Plugins explicitly). Dolphin reads dolphinrc at
%% launch — reopen it after applying.

binary_pkg('/usr/lib/x86_64-linux-gnu/qt6/plugins/kf6/thumbcreator/ffmpegthumbs.so',
           ffmpegthumbs).

%% File-dialog previews (kdeglobals — affects open/save dialogs everywhere).
user_config(dolphin_previews, Check,
    "kwriteconfig5 --file kdeglobals --group 'KFileDialog Settings' --key 'Show Preview' true") :-
    user_home(Home),
    format(atom(Check),
        "grep -q '^Show Preview=true' ~w/.config/kdeglobals 2>/dev/null", [Home]).

%% Dolphin view previews + the ffmpegthumbs plugin. When the Plugins key is
%% absent Dolphin runs its built-in default set, so the seed below mirrors
%% those defaults and adds ffmpegthumbs; when present, append — never
%% clobber choices the user made in Dolphin's settings dialog.
user_config(dolphin_video_previews, Check, Fix) :-
    user_home(Home),
    format(atom(Check),
        "grep -Eq '^Plugins=.*ffmpegthumbs' ~w/.config/dolphinrc 2>/dev/null && grep -q '^PreviewsShown=true' ~w/.config/dolphinrc 2>/dev/null",
        [Home, Home]),
    Fix = "P=$(kreadconfig6 --file dolphinrc --group PreviewSettings --key Plugins); if [ -z \"$P\" ]; then kwriteconfig6 --file dolphinrc --group PreviewSettings --key Plugins 'directorythumbnail,imagethumbnail,jpegthumbnail,svgthumbnail,kraorathumbnail,windowsexethumbnail,windowsimagethumbnail,ffmpegthumbs'; else case \"$P\" in *ffmpegthumbs*) : ;; *) kwriteconfig6 --file dolphinrc --group PreviewSettings --key Plugins \"$P,ffmpegthumbs\" ;; esac; fi; kwriteconfig6 --file dolphinrc --group General --key PreviewsShown true".
