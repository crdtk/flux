# Tailscale — user half: obtain and store the auth key the system half consumes.
# Interactive and user-space (needs the user's browser/session), so it cannot live in
# the root branch. TAILSCALE_CONF is the contract with system.mk, defined there (the
# */system.mk glob is parsed before */user.mk).
# USER_FILES += $(TAILSCALE_CONF)

# $(TAILSCALE_CONF): | $(PROJECTS)
# 	@-xdg-open https://login.tailscale.com/admin/settings/keys
# 	@printf '>>> Auth key (Ctrl+C to abort): '
# 	@read -r KEY; \
# 	  if [ -n "$$KEY" ]; then printf '%s\n' "tailscale_auth_key=$$KEY" > $@; printf '>>> Saved to $@\n'; \
# 	  else printf '>>> No key entered — still pending, run make again to retry\n'; fi
