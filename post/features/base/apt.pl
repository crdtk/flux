%% base/apt — package-manager self-healing. apt refuses all installs
%% while dpkg sits in an interrupted state (seen 2026-08-10: an aborted
%% purge left journal files in /var/lib/dpkg/updates and the next POST
%% pass's apt batch died with "dpkg was interrupted"). Sense the journal
%% directory; the fix is dpkg's own recovery. gen_package_rule makes the
%% apt batch depend on this repair whenever it is pending, so recovery
%% always precedes installs in the emitted plan.

hardening_check(dpkg_consistent,
    "test -z \"$(ls /var/lib/dpkg/updates 2>/dev/null)\"",
    "dpkg --configure -a").
