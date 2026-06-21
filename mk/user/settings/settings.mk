include mk/user/settings/plasmoids.mk
include mk/user/settings/panels/panels.mk

$(PROJECTS)/secrets/tailscale.conf: | $(PROJECTS)
	@-xdg-open https://login.tailscale.com/admin/settings/keys
	@printf '>>> Auth key (Ctrl+C to abort): '
	@read -r KEY; \
	  if [ -n "$$KEY" ]; then printf '%s\n' "tailscale_auth_key=$$KEY" > $@; printf '>>> Saved to $@\n'; \
	  else printf '>>> No key entered — still pending, run make again to retry\n'; fi

USER_FILES += $(PROJECTS)/secrets/tailscale.conf
