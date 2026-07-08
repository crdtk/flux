#!/usr/bin/env swipl
%% post/post.pl — Power-On Self Test: diagnostic and fix pipeline (ENGINE).
%%
%% stderr → colored boot-sequence output (human-readable).
%% stdout → shell commands that fix every failure (pipe to sudo bash).
%%
%% Pipe is acceptance:
%%   ./post.pl             — plan visible, nothing applied
%%   ./post.pl | sudo bash — plan applied
%%
%% The engine is generic: environment sensing, diagnosis drivers, the
%% selection mechanism, rule generation, the topological planner and the
%% emitter. All knowledge lives in features/<arena>/<decision>.pl modules
%% loaded by the glob at the bottom — one file per revocable decision
%% (constitution XXV): "remove all X logic" must touch at most one module.

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(readutil)).

%% ── Dynamic state ─────────────────────────────────────────────────────────────

:- dynamic failed/3.      % failed(Level, Component, Reason)
:- dynamic satisfied/1.   % satisfied(Goal): already true, no action needed
:- dynamic build_rule/3.  % build_rule(Goal, Deps, Cmds)

%% ── Module contract ──────────────────────────────────────────────────────────
%% Feature modules add clauses to these predicates — the whole interface.
%% Facts may be gated rule clauses whose body fails when inapplicable (XXIII).
%% candidate/2 clause order is preference rank: a domain's candidates must
%% all live in ONE module. advisory/3 names human-only steps (XXIV);
%% demotion_reason/3 explains a candidate's failed viability with evidence.

:- multifile binary_pkg/2, deb_install/1, deb_source/3, apt_repo/3,
             pkg_repo/2, opt_install/3, opt_install_deps/2, desktop_fix/3,
             config_patch/4, hardening_check/3, service_check/3,
             service_deps/2, user_tool/3, user_tool_deps/2,
             user_config/3, user_config_deps/2,
             candidate/2, viable/2, dm_installed/1, dm_session_check/2,
             dm_session_fix/2, active_display_manager/1,
             saved_session_is_x11/0, session_rule/2,
             demotion_reason/3, advisory/3.
:- discontiguous binary_pkg/2, deb_install/1, deb_source/3, apt_repo/3,
             pkg_repo/2, opt_install/3, opt_install_deps/2, desktop_fix/3,
             config_patch/4, hardening_check/3, service_check/3,
             service_deps/2, user_tool/3, user_tool_deps/2,
             user_config/3, user_config_deps/2,
             candidate/2, viable/2, dm_installed/1, dm_session_check/2,
             dm_session_fix/2, active_display_manager/1,
             saved_session_is_x11/0, session_rule/2,
             demotion_reason/3, advisory/3.

%% ── Environment (helpers available to every module) ──────────────────────────

downloads_dir(D) :-
    ( getenv('DOWNLOADS_DIR', D) -> true
    ; getenv('HOME', H), atom_concat(H, '/Downloads', D) ).

run_as_user(U) :-
    ( getenv('RUN_AS_USER', U) -> true
    ; getenv('SUDO_USER',   U) -> true
    ; getenv('USER',        U) ).

%% user_home(-H) — home of the real user, stable even when run under sudo
%% (where $HOME would be /root).
user_home(H) :-
    run_as_user(U),
    format(atom(H), '/home/~w', [U]).

%% project_dir(-D) — the repo root, sensed from POST's own location
%% (post/ is one level below it, XIX) rather than assumed: the tree works
%% from any clone path.
:- dynamic project_dir/1.
:- prolog_load_context(directory, PostDir),
   file_directory_name(PostDir, Root),
   assertz(project_dir(Root)).

%% os_release(+Key, -Value) — read /etc/os-release directly; environment
%% variables are not a reliable carrier for it (login shells don't export
%% UBUNTU_CODENAME).
os_release(Key, Value) :-
    read_file_to_string('/etc/os-release', S, []),
    split_string(S, "\n", "", Lines),
    format(atom(Prefix), '~w=', [Key]),
    member(L, Lines),
    string_concat(Prefix, V0, L),
    split_string(V0, "", "\"", [V1]),
    atom_string(Value, V1), !.

ubuntu_codename(C) :-
    ( os_release('UBUNTU_CODENAME', C) -> true
    ; getenv('UBUNTU_CODENAME', C)     -> true
    ; C = noble ).

%% ubuntu_ver(-V) — VERSION_ID without the dot (26.04 → 2604), the form
%% NVIDIA's CUDA repo paths use.
ubuntu_ver(V) :-
    os_release('VERSION_ID', VId),
    atomic_list_concat(Parts, '.', VId),
    atomic_list_concat(Parts, '', V).

%% Shared hardware gate (used by platform/nvidia and desktop/lomiri).
%% Story-local gates (has_bmc, has_plx_switch, GA104GL) live in their module.
has_nvidia :- shell_ok("lspci 2>/dev/null | grep -qi nvidia").

%% ── Display (→ stderr) ───────────────────────────────────────────────────────

section(Num, Title) :-
    format(user_error, '~n\033[1m-- ~w ~w ~`-t~55|\033[0m~n', [Num, Title]).

post_ok(Level, Comp, Detail) :-
    format(user_error, '\033[32m[ OK ]\033[0m  ~w/~w ~`.t~45|~w~n', [Level, Comp, Detail]).

post_warn(Level, Comp, Detail) :-
    format(user_error, '\033[33m[WARN]\033[0m  ~w/~w ~`.t~45|~w~n', [Level, Comp, Detail]).

post_fail(Level, Comp, Detail) :-
    format(user_error, '\033[31m[FAIL]\033[0m  ~w/~w ~`.t~45|~w~n', [Level, Comp, Detail]).

post_skip(Goal, Reason) :-
    format(user_error, '\033[33m[SKIP]\033[0m  ~w ~`.t~45|~w~n', [Goal, Reason]).

%% ── Shell helper ─────────────────────────────────────────────────────────────

shell_ok(Cmd) :-
    atomic_list_concat([Cmd, '>/dev/null 2>&1'], ' ', Silent),
    shell(Silent, 0).

%% ── Selection mechanism ──────────────────────────────────────────────────────
%% Generalizes the plasma-widget sentinel lesson: never trust the assumed
%% option. Candidates are declared in preference order (clause order = rank),
%% each must survive live heuristic probes, and the first survivor wins —
%% pure Prolog backtracking. Installed alternates are held standby-ready so
%% switching is a greeter choice, not a repair.

select(Domain, Choice) :- candidate(Domain, Choice), viable(Domain, Choice), !.

%% ── Diagnostics ──────────────────────────────────────────────────────────────

diagnose(internet) :-
    section('01', 'INTERNET'),
    ( shell_ok("ip link show | grep -v lo | grep -q 'state UP'")
    -> assert(satisfied(internet_ok)),
       post_ok(internet, ethernet, 'link up')
    ;  assert(failed(internet, ethernet, no_link)),
       post_fail(internet, ethernet, 'no link — check cable')
    ),
    ( shell_ok("resolvectl status 2>/dev/null | grep -q 'DNS Servers'")
    -> post_ok(internet, dns, configured)
    ;  post_warn(internet, dns, 'not configured via resolvectl')
    ).

diagnose(packages) :-
    section('02', 'PACKAGES'),
    forall(binary_pkg(Bin, Pkg), (
        ( access_file(Bin, exist)
        -> post_ok(packages, Pkg, installed)
        ;  assert(failed(packages, Bin, missing)),
           post_fail(packages, Pkg, missing)
        )
    )),
    forall(opt_install(Name, Bin, _), (
        ( access_file(Bin, exist)
        -> post_ok(packages, Name, installed)
        ;  assert(failed(packages, Bin, missing)),
           post_fail(packages, Name, missing)
        )
    )).

diagnose(repos) :-
    findall(RepoName,
        ( failed(packages, Bin, missing), binary_pkg(Bin, Pkg), pkg_repo(Pkg, RepoName) ),
        Repos0),
    sort(Repos0, Repos),
    ( Repos = [] -> true
    ;  section('03', 'REPOS'),
       forall(member(RepoName, Repos), (
           apt_repo(RepoName, CheckCmd, _),
           ( shell_ok(CheckCmd)
           -> assert(satisfied(repo_ready(RepoName))),
              post_ok(repos, RepoName, present)
           ;  assert(failed(repos, RepoName, missing)),
              post_fail(repos, RepoName, missing)
           )
       ))
    ).

diagnose(hardening) :-
    section('04', 'HARDENING'),
    forall(hardening_check(Name, CheckCmd, _), (
        ( shell_ok(CheckCmd)
        -> post_ok(hardening, Name, applied)
        ;  assert(failed(hardening, Name, missing)),
           post_fail(hardening, Name, missing)
        )
    )).

diagnose(patches) :-
    section('05', 'PATCHES'),
    forall(config_patch(Name, Guard, CheckCmd, _), (
        ( access_file(Guard, exist)
        -> ( shell_ok(CheckCmd)
           -> post_ok(patches, Name, applied)
           ;  assert(failed(patches, Name, missing)),
              post_fail(patches, Name, missing)
           )
        ;  true
        )
    )).

%% Session health is judged by processes, not env vars: GDM's Wayland
%% greeter leaks XDG_SESSION_TYPE=wayland into the user environment even
%% when the session it launched is genuine X11 Plasma.
diagnose(desktop) :-
    section('06', 'DESKTOP'),
    ( shell_ok("pgrep -x startplasma-x11"), shell_ok("pgrep -x Xorg")
    ->  post_ok(desktop, session_type, 'plasma-x11'),
        % This process inherits the invoking terminal's environment: if it
        % still carries Wayland vars, GUI apps launched from that terminal
        % will pick the Wayland backend and die. No root fix exists for an
        % already-running shell — the terminal must be replaced.
        ( ( getenv('WAYLAND_DISPLAY', _) ; getenv('XDG_SESSION_TYPE', wayland) )
        ->  post_warn(desktop, terminal_env,
                'this terminal carries stale Wayland vars — close it and launch apps from a fresh one')
        ;   post_ok(desktop, terminal_env, clean)
        )
    ;   shell_ok("pgrep -x kwin_wayland")
    ->  post_ok(desktop, session_type, 'plasma-wayland')
    ;   shell_ok("pgrep -x kwin_x11")
    ->  % kwin_x11 without real Xorg: Wayland session fell back — Alt+Tab broken
        ( saved_session_is_x11
        ->  assert(satisfied(session_fixed(wayland_x11_mismatch))),
            post_warn(desktop, session_type,
                'X11 default recorded — log out and log back in to Plasma (X11)')
        ;   assert(failed(desktop, session_type, wayland_x11_mismatch)),
            post_fail(desktop, session_type,
                'kwin_x11 running without Xorg — broken Wayland fallback, Alt+Tab broken')
        )
    ;   post_ok(desktop, session_type, 'no plasma session')
    ).

diagnose(user_tools) :-
    section('07', 'USER TOOLS'),
    getenv('HOME', Home),
    forall(user_tool(Name, Rel, _), (
        atomic_list_concat([Home, '/', Rel], Sentinel),
        ( access_file(Sentinel, exist)
        -> post_ok(user_tools, Name, installed),
           assert(satisfied(user_tool_ready(Name)))
        ;  assert(failed(user_tools, Name, missing)),
           post_fail(user_tools, Name, missing)
        )
    )).

diagnose(services) :-
    section('08', 'SERVICES'),
    forall(service_check(Name, CheckCmd, _), (
        ( shell_ok(CheckCmd)
        -> post_ok(services, Name, applied),
           assert(satisfied(service_ready(Name)))
        ;  assert(failed(services, Name, missing)),
           post_fail(services, Name, missing)
        )
    )),
    % Human-only steps (XXIV): modules name them via advisory/3.
    forall(advisory(services, Comp, Msg), post_warn(services, Comp, Msg)).

diagnose(user_config) :-
    section('10', 'USER CONFIG'),
    forall(user_config(Name, CheckCmd, _), (
        ( shell_ok(CheckCmd)
        -> post_ok(user_config, Name, applied),
           assert(satisfied(user_config_applied(Name)))
        ;  assert(failed(user_config, Name, missing)),
           post_fail(user_config, Name, missing)
        )
    )).

%% Which options won the backtracking, and are the losers standby-ready?
diagnose(selection) :-
    section('09', 'SELECTION'),
    ( active_display_manager(Active) -> true ; Active = none ),
    ( select(display_manager, Best)  -> true ; Best = none ),
    format(atom(DmDetail), 'active ~w, preferred ~w', [Active, Best]),
    post_ok(selection, display_manager, DmDetail),
    forall(( candidate(display_manager, DM), dm_installed(DM) ), (
        ( dm_session_check(DM, Check), shell_ok(Check)
        -> post_ok(selection, DM, 'standby-ready (plasmax11 recorded)')
        ;  assert(failed(selection, DM, standby)),
           post_fail(selection, DM, 'plasmax11 not recorded — standby fix queued')
        )
    )),
    ( select(session, S)
    -> post_ok(selection, session, S)
    ;  post_warn(selection, session, 'no viable session candidate')
    ),
    forall(candidate(session, Sess), (
        ( viable(session, Sess) -> true
        ;  demotion_reason(session, Sess, Why)
        -> post_warn(selection, Sess, Why)
        ;  post_warn(selection, Sess, 'not viable — session file missing')
        )
    )).

%% ── Rule generation ──────────────────────────────────────────────────────────

generate_rules :-
    gen_download_rules,
    gen_repo_rules,
    gen_package_rule,
    gen_opt_install_rules,
    gen_desktop_fix_rules,
    gen_patch_rules,
    gen_session_fix_rules,
    gen_hardening_rules,
    gen_service_rules,
    gen_selection_rules,
    gen_user_tool_rules,
    gen_user_config_rules,
    gen_top_rule.

%% Fixes run as the real user with their session bus, via a quoted heredoc
%% so quoting inside the raw fix survives the root pipe unmodified.
gen_user_config_rules :-
    run_as_user(User),
    forall(
        failed(user_config, Name, missing),
        ( user_config(Name, _, RawCmd),
          format(atom(Cmd),
              "sudo -u ~w XDG_RUNTIME_DIR=/run/user/$(id -u ~w) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u ~w)/bus bash <<'POST_USER_EOF'~n~w~nPOST_USER_EOF",
              [User, User, User, RawCmd]),
          ( user_config_deps(Name, Deps) -> true ; Deps = [] ),
          assert(build_rule(user_config_applied(Name), Deps, [Cmd]))
        )
    ).

gen_selection_rules :-
    forall(
        ( failed(selection, DM, standby), dm_session_fix(DM, FixCmd) ),
        assert(build_rule(dm_standby(DM), [], [FixCmd]))
    ).

gen_service_rules :-
    forall(
        ( failed(services, Name, missing), service_check(Name, _, FixCmd) ),
        ( ( service_deps(Name, Deps) -> true ; Deps = [packages_installed] ),
          assert(build_rule(service_ready(Name), Deps, [FixCmd]))
        )
    ).

gen_opt_install_rules :-
    forall(
        ( failed(packages, Bin, missing), opt_install(Name, Bin, Cmd) ),
        ( ( opt_install_deps(Name, Deps) -> true ; Deps = [internet_ok] ),
          assert(build_rule(opt_installed(Name), Deps, [Cmd]))
        )
    ).

gen_download_rules :-
    downloads_dir(DDir),
    forall(
        ( failed(packages, Bin, missing), deb_source(Bin, URL, Fname) ),
        ( atomic_list_concat([DDir, '/', Fname], Path),
          ( access_file(Path, exist)
          -> assert(satisfied(downloaded(Path)))
          ;  format(atom(Cmd), 'curl -fsSL ~w -o ~w', [URL, Path]),
             assert(build_rule(downloaded(Path), [internet_ok], [Cmd]))
          )
        )
    ).

gen_repo_rules :-
    forall(
        ( failed(repos, RepoName, missing), apt_repo(RepoName, _, AddCmd) ),
        assert(build_rule(repo_ready(RepoName), [internet_ok], [AddCmd]))
    ).

gen_package_rule :-
    downloads_dir(DDir),
    findall(Pkg,
        ( failed(packages, Bin, missing), binary_pkg(Bin, Pkg), \+ deb_install(Bin) ),
        RegPkgs),
    findall(Path,
        ( failed(packages, Bin, missing), deb_install(Bin),
          deb_source(Bin, _, Fname),
          atomic_list_concat([DDir, '/', Fname], Path) ),
        DebPaths),
    findall(downloaded(P), member(P, DebPaths), DebDeps),
    findall(repo_ready(R),
        ( member(Pkg, RegPkgs), pkg_repo(Pkg, R) ),
        RepoDeps0),
    sort(RepoDeps0, RepoDeps),
    append(RegPkgs, DebPaths, All),
    ( All \= []
    -> atomic_list_concat(['apt install -y' | All], ' ', InstallCmd),
       append([package_lists_fresh | DebDeps], [], InstDeps),
       assert(build_rule(packages_installed, InstDeps, [InstallCmd])),
       append([internet_ok | RepoDeps], [], UpdateDeps),
       assert(build_rule(package_lists_fresh, UpdateDeps, ['apt-get update']))
    ;  assert(build_rule(packages_installed, [], []))
    ).

gen_desktop_fix_rules :-
    forall(
        ( failed(packages, Bin, missing), desktop_fix(Bin, File, Expr) ),
        ( format(atom(Cmd), "sed -i '~w' ~w", [Expr, File]),
          assert(build_rule(desktop_fixed(File), [packages_installed], [Cmd]))
        )
    ).

%% Patches for currently-failing checks; patches for guards being installed this run.
%% A guard arriving via apt waits on packages_installed; one arriving via an
%% opt_install waits on that specific install.
gen_patch_rules :-
    forall(config_patch(Name, Guard, _, FixCmd), (
        ( failed(patches, Name, missing)
        -> assert(build_rule(patch_applied(Name), [], [FixCmd]))
        ;  failed(packages, Guard, missing), guard_install_dep(Guard, Dep)
        -> assert(build_rule(patch_applied(Name), [Dep], [FixCmd]))
        ;  true
        )
    )).

guard_install_dep(Guard, packages_installed)   :- binary_pkg(Guard, _), !.
guard_install_dep(Guard, opt_installed(Name))  :- opt_install(Name, Guard, _).

gen_session_fix_rules :-
    forall(
        ( failed(desktop, session_type, Name), session_rule(Name, FixCmd) ),
        assert(build_rule(session_fixed(Name), [], [FixCmd]))
    ).

gen_hardening_rules :-
    forall(
        ( failed(hardening, Name, missing), hardening_check(Name, _, FixCmd) ),
        assert(build_rule(hardening_applied(Name), [], [FixCmd]))
    ).

gen_user_tool_rules :-
    run_as_user(User),
    forall(
        failed(user_tools, Name, missing),
        ( user_tool(Name, _, RawCmd),
          format(atom(Cmd), "sudo -u ~w -i bash -c '~w'", [User, RawCmd]),
          ( user_tool_deps(Name, Deps) -> true ; Deps = [user_tool_ready(uv)] ),
          assert(build_rule(user_tool_ready(Name), Deps, [Cmd]))
        )
    ).

gen_top_rule :-
    findall(desktop_fixed(F),
        ( failed(packages, Bin, missing), desktop_fix(Bin, F, _) ),
        PkgFixDeps),
    findall(patch_applied(N),
        ( config_patch(N, Guard, _, _),
          ( failed(patches, N, missing)
          ; failed(packages, Guard, missing), guard_install_dep(Guard, _)
          )
        ),
        PatchDeps0),
    sort(PatchDeps0, PatchDeps),
    findall(opt_installed(N),
        ( failed(packages, Bin2, missing), opt_install(N, Bin2, _) ),
        OptDeps),
    findall(session_fixed(N),    failed(desktop, session_type, N),  SessionDeps),
    findall(hardening_applied(N), failed(hardening, N, missing),    HardeningDeps),
    findall(service_ready(N),    failed(services, N, missing),      ServiceDeps),
    findall(dm_standby(N),       failed(selection, N, standby),     StandbyDeps),
    findall(user_tool_ready(N),  failed(user_tools, N, missing),    ToolDeps),
    findall(user_config_applied(N), failed(user_config, N, missing), UserCfgDeps),
    flatten([packages_installed, PkgFixDeps, PatchDeps, OptDeps,
             SessionDeps, HardeningDeps, ServiceDeps, StandbyDeps,
             ToolDeps, UserCfgDeps], Deps),
    sort(Deps, UniqDeps),
    assert(build_rule(system_ready, UniqDeps, [])).

%% ── Planner (topological, propagates blocked) ─────────────────────────────────

collect(Goal, Vis0, Vis0, ok([])) :- memberchk(Goal, Vis0), !.
collect(Goal, Vis0, [Goal|Vis0], ok([])) :- satisfied(Goal), !.
collect(Goal, Vis0, Vis1, Result) :-
    build_rule(Goal, Deps, GoalCmds), !,
    collect_deps(Deps, Vis0, Vis2, DepsResult),
    ( DepsResult = blocked
    -> Vis1 = Vis2, Result = blocked
    ;  DepsResult = ok(DepCmds),
       Vis1 = [Goal|Vis2],
       append(DepCmds, GoalCmds, Cmds),
       Result = ok(Cmds)
    ).
collect(Goal, Vis0, Vis0, blocked) :-
    post_skip(Goal, 'no rule — dependency unachievable').

collect_deps([], Vis, Vis, ok([])).
collect_deps([H|T], Vis0, Vis2, Result) :-
    collect(H, Vis0, Vis1, HResult),
    ( HResult = blocked
    -> Vis2 = Vis1, Result = blocked
    ;  HResult = ok(HCmds),
       collect_deps(T, Vis1, Vis2, TResult),
       ( TResult = blocked
       -> Result = blocked
       ;  TResult = ok(TCmds),
          append(HCmds, TCmds, AllCmds),
          Result = ok(AllCmds)
       )
    ).

%% ── Feature modules ──────────────────────────────────────────────────────────
%% One file per revocable decision, grouped into the arenas of this build
%% (base, platform, net, desktop, dev, agents, project). Dropping a file in
%% is adding a capability; deleting it revokes the decision. Loaded sorted
%% so runs are reproducible.

:- prolog_load_context(directory, Dir),
   atomic_list_concat([Dir, '/features/*/*.pl'], Pat),
   expand_file_name(Pat, Files),
   (  Files == []
   -> print_message(error, format('POST: no feature modules under ~w/features', [Dir]))
   ;  true
   ),
   sort(Files, Sorted),
   load_files(Sorted, [silent(true)]).

%% ── Entry point ──────────────────────────────────────────────────────────────

main :-
    set_stream(user_error, buffer(false)),
    maplist(diagnose, [internet, packages, repos, hardening, patches, desktop,
                       user_tools, services, selection, user_config]),
    nl(user_error),
    generate_rules,
    collect(system_ready, [], _, Result),
    ( Result = ok([])
    -> format(user_error, '\033[32mSystem is up to date.\033[0m~n', [])
    ; Result = ok(Cmds)
    -> catch(maplist(writeln, Cmds), error(io_error(_,_),_), true)
    ; format(user_error,
        '\033[31mFix blocked — resolve unachievable dependencies first.\033[0m~n', [])
    ).

:- initialization(main, main).
