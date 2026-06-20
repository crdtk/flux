# Resilient monitors as one tiny autostart per output — each Exec is a plain kscreen-doctor
# call (no pipeline, no quotes, no $), so there's zero escaping to get wrong. One file per
# connected output, derived at make-time from kscreen-doctor's JSON. KScreen keeps the
# arrangement (we only enable, never reposition). User-space — no root.
# NOTE: this is a make-time snapshot of what's plugged in — move a cable to a new port and
# re-run make. (Use `.outputs[].name` instead of select(.connected) to cover every port.)
DISPLAY_OUTPUTS := $(shell kscreen-doctor --json 2>/dev/null | jq -r '.outputs[] | select(.connected) | .name')
USER_FILES += $(foreach o,$(DISPLAY_OUTPUTS),$(USER_HOME)/.config/autostart/enable-$(o).desktop)

define ENABLE_OUTPUT_DESKTOP
[Desktop Entry]
Type=Application
Name=Enable monitor $*
Exec=kscreen-doctor output.$*.enable
OnlyShowIn=KDE;
endef

# Each output's autostart entry — written, and applied now (no-op if that port is empty).
$(USER_HOME)/.config/autostart/enable-%.desktop: | $(USER_HOME)/.config/autostart
	$(file >$@,$(ENABLE_OUTPUT_DESKTOP))
	@kscreen-doctor output.$*.enable >/dev/null 2>&1 || true

$(USER_HOME)/.config/autostart:
	mkdir -p $@
