%% desktop/audio — PipeWire serves ALSA/PulseAudio clients; the real
%% PulseAudio daemon package is also installed and must never answer.
%%
%% Failure mode seen 2026-08-05: clients got ECONNREFUSED on
%% $XDG_RUNTIME_DIR/pulse/native while pipewire-pulse held a healthy
%% listener on that very path — an ORPHANED listener: something (a
%% client-autospawned real pulseaudio) unlinked and re-bound the socket
%% file, then died, leaving a dead file over a live-but-unreachable
%% bind. Restarting pipewire-pulse.service (tried five times) can never
%% fix it — only pipewire-pulse.socket re-binds the path.

%% Prevention (root): libpulse defaults to autospawn=yes and the
%% pulseaudio package ships an enable-autospawn snippet. Later
%% client.conf.d files win, so 99-crucible pins it off.
service_check(pulse_no_autospawn, Check, Fix) :-
    shell_ok("test -x /usr/bin/pulseaudio"),
    Check = "grep -qs '^autospawn = no' /etc/pulse/client.conf.d/99-crucible-no-autospawn.conf",
    Fix = "mkdir -p /etc/pulse/client.conf.d && printf 'autospawn = no\\n' > /etc/pulse/client.conf.d/99-crucible-no-autospawn.conf".

%% Repair (user session): probe the socket for a real answer; on
%% refusal, re-bind the path via the socket unit, then the service.
user_config(pulse_socket_answers, Check, Fix) :-
    shell_ok("test -x /usr/bin/pipewire-pulse"),
    Check = "pactl info >/dev/null 2>&1",
    Fix = "systemctl --user restart pipewire-pulse.socket pipewire-pulse.service".
