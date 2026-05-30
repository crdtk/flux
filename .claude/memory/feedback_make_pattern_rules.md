---
name: Make Pattern Rules — Plain vs Static
description: When to use plain `%` pattern rules vs static-pattern rules in Makefiles, and why a regular rule with no pattern leaves `$*` empty
type: feedback
originSessionId: 742e51d0-dbf3-40f5-8c69-aaf265a29e95
---
In GNU Make, **`$*` (the stem) is only populated when the rule contains a pattern**. A regular rule that just lists explicit targets has nothing to match against, so `$*` stays empty in the recipe. If a recipe uses `$*` for an echo or filename derivation, you need one of the two pattern forms below.

**Plain pattern rule** — applies to ANY target matching the pattern:

```makefile
$(MOUNT)/persistence/%.dat: | $(MOUNT)/persistence
	@echo "Creating $* ..."
	dd if=/dev/zero of=$@ bs=1M count=$(PERSISTENCE_SIZE_MB)
	mkfs.ext4 -F -L persistence $@
```

**Static pattern rule** — applies only to a specific target list:

```makefile
$(DAT_FILES): $(MOUNT)/persistence/%.dat: | $(MOUNT)/persistence
	@echo "Creating $* ..."
	... same recipe ...
```

Three colons: `TARGETS: TARGET-PATTERN: PREREQS [| ORDER-ONLY]`. The middle `TARGET-PATTERN` clause is what teaches Make how to extract the stem from each target in the list.

**Decision guide — when to use which:**

- **Plain pattern rule** when nothing else in the Makefile could accidentally request a matching file. Simpler grammar (one colon clause instead of two), more decoupled — adding new targets to a prereq list flows through automatically without touching the rule.
- **Static pattern rule** when you want the safety of "only these specific files trigger this recipe." Make errors with "no rule to make target" for stray requests instead of unintentionally building them. Important when the recipe is destructive or expensive (e.g. creates a 4 GB ext4 image).

**Why:** Pattern rules are fire-and-forget — they match anything that asks. If a typo or future change makes Make request `/somewhere/random.dat`, a plain pattern rule will happily build it. Static-pattern rules constrain the scope to a known finite list.

**How to apply:**

1. **If a recipe references `$*`, the rule must have a pattern.** Regular rules (just `targets: prereqs`) don't compute stems. Symptom: echo prints blank where `$*` should be.
2. **Default to plain pattern rules** unless there's a real risk of stray matches that would do something destructive or expensive.
3. **Keep style consistent with the rest of the file** — if the file already uses plain pattern rules elsewhere (e.g. `$(MOUNT)/%: $(DOWNLOADS_DIR)/%`), match that style for new pattern rules. Don't introduce static-pattern syntax for one rule when the surrounding code uses plain patterns.
4. **Order-only prereqs (`|`) work in both forms** for "this directory must exist but its mtime shouldn't trigger rebuilds."

**Common gotcha that triggered creating this memory:** the user had `$(DAT_FILES): | $(MOUNT)/persistence` (a regular rule, no pattern) and the recipe's `$*` was empty. Two valid fixes: turn it into a static pattern rule by adding a `$(MOUNT)/persistence/%.dat:` middle clause, or simplify to a plain pattern rule by replacing `$(DAT_FILES):` with `$(MOUNT)/persistence/%.dat:`. The user chose plain pattern for consistency with the surrounding `$(MOUNT)/%:` rule.
