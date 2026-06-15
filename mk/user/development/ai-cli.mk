NPM_PKG_claude := @anthropic-ai/claude-code
NPM_PKG_gemini := @google/gemini-cli

USER_FILES += \
    $(USER_HOME)/.local/bin/claude \
    $(USER_HOME)/.local/bin/gemini

$(USER_HOME)/.local/bin/%:
	mkdir -p $(dir $@)
	@command -v npm >/dev/null 2>&1 \
	  && npm install --prefix $(USER_HOME)/.local -g $(NPM_PKG_$*) \
	  || echo ">>> WARNING: npm not found — skipping $* (sudo make installs npm; make again picks it up)"
