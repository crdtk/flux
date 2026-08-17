# Network/Email — CLI mail access goes through thunderbird-cli (`tb`),
# which queries the LIVE mailboxes over the bridge daemon (POST:
# desktop/mail.pl owns the whole chain — npm packages, bridge XPI,
# tb-bridge user service). Ad-hoc questions are tb one-liners, not make
# targets:
#
#   tb search "words" --limit 20            full-text over live mail
#   tb search "" --since 2026-08-17         by date window
#   tb read <id> / tb --help                bodies; all 38 commands
#
# The Gloda SQL catalog that lived here (mail-search / mail-unanswered /
# mail-sql over global-messages-db.sqlite) was deleted 2026-08-17 by the
# no-consumer rule: tb answers the same questions against fresher data
# without the private-schema liability (Gloda's schema dies with
# Panorama) and without the lock that barred queries exactly when
# Thunderbird was running. Git history keeps the SQL if archaeology
# ever needs it.

# The one recurring audit stays encoded (XVII): latest traffic from a
# correspondent, newest first — the human scans for "did I answer the
# last one?". True thread-level unanswered detection needs conversation
# joins tb doesn't expose yet; this target claims only what it does.
# Two extension limits, both verified live 2026-08-17: the query string
# is PLAIN full-text (`from:`/`created:` operator syntax hangs the
# handler until timeout), and result sets much past ~10 do the same —
# limit 10 answers in seconds, 25+ wedges the extension until a
# Thunderbird restart clears it. So: small limit, authorship filter in
# jq, N capped at 10.
## Latest mail from a correspondent via live query: make mail-from FROM=arbeitsrecht-berlin.de [N<=10]
.PHONY: mail-from
mail-from:
	@test -n "$(FROM)" || { echo ">>> usage: make mail-from FROM=domain-or-address [N<=10]"; exit 1; }
	@tb search "$(FROM)" --limit 10 | \
	  jq -r '.data.messages[] | select(.author | test("$(FROM)")) | [.date[:16], .author, .subject, .folder.name] | @tsv' | \
	  sort -r | head -$(or $(N),10) | column -t -s'	'

# Architecture spec (same idiom as demos/vessels/docs/stack.puml).
mk/features/Network/Email/stack.png: mk/features/Network/Email/stack.puml
	plantuml -tpng $<
