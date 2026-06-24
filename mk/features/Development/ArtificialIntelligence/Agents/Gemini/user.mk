# Gemini CLI — Google's agentic coding CLI, installed as an npm global into ~/.local.
# Gated on npm (from the root branch); warns and continues if it's not there yet (IV).
USER_FILES += $(USER_HOME)/.local/bin/gemini

$(USER_HOME)/.local/bin/gemini:
	mkdir -p $(dir $@)
	@command -v npm >/dev/null 2>&1 \
	  && npm install --prefix $(USER_HOME)/.local -g @google/gemini-cli \
	  || echo ">>> WARNING: npm not found — skipping gemini (sudo make installs npm; make again picks it up)"
