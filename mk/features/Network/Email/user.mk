# Network/Email — CLI queries over the mail Thunderbird proxies (POST:
# desktop/mail.pl owns install + Gloda pin). This file is the ONLY place
# the Gloda schema may appear: the index is private Thunderbird internals
# with an announced successor (Panorama), so the read path is built to be
# thrown away — a query catalog, one file, read-only. Truth stays in
# Gmail via Thunderbird; nothing here writes.
#
# One pattern rule, queries as data (VI) — a question is a catalog line:
#
#   make mail-search Q="invoice zalando" [N=20]   FTS MATCH over
#     subject/body/author/recipients/attachmentNames (words, "phrases",
#     OR, column:term). Hits, not full messages; freshness lags Gloda's
#     background indexer by minutes.
#   make mail-unanswered FROM=arbeitsrecht-berlin.de [N=20]   threads
#     with mail from FROM and no later message of mine (fromMe) — the
#     open-items audit. Blind to replies sent from other mailboxes.

# Newest profile's index wins if several exist (III — sensed at parse time).
GLODA := $(lastword $(sort $(wildcard $(USER_HOME)/.thunderbird/*/global-messages-db.sqlite)))

# Gloda schema notes: queries read messagesText_content — the FTS3
# shadow table (docid = messages.id; c0body c1subject c2attachmentNames
# c3author c4recipients) — because the virtual table itself demands
# Mozilla's mozporter tokenizer, which stock sqlite3 cannot load (MATCH
# is unpreparable; LIKE over the shadow is a full scan, milliseconds at
# mailbox scale). date is PRTime (µs since epoch); deleted rows linger
# until Gloda compacts them.
GLODA_QUERY_search = SELECT datetime(m.date/1000000,'unixepoch') AS date, t.c3author AS author, f.folderURI AS folder, t.c1subject AS subject FROM messagesText_content t JOIN messages m ON m.id = t.docid LEFT JOIN folderLocations f ON f.id = m.folderID WHERE (t.c1subject LIKE '%$(or $(Q),$(error mail-search: needs Q="words"))%' OR t.c0body LIKE '%$(Q)%' OR t.c3author LIKE '%$(Q)%' OR t.c4recipients LIKE '%$(Q)%') AND m.deleted = 0 ORDER BY m.date DESC LIMIT $(or $(N),20)
# "Answered by me" = a later message in the thread authored by my git
# identity (messages has no fromMe column; authorship is the truth the
# index actually holds — and Sent Mail is indexed, proven 2026-08-14).
ME := $(shell git config --get user.email)
GLODA_QUERY_unanswered = SELECT datetime(MAX(m.date)/1000000,'unixepoch') AS waiting_since, t.c3author AS author, t.c1subject AS subject FROM messagesText_content t JOIN messages m ON m.id = t.docid WHERE t.c3author LIKE '%$(or $(FROM),$(error mail-unanswered: needs FROM=domain-or-address))%' AND m.deleted = 0 GROUP BY m.conversationID HAVING COALESCE((SELECT MAX(r.date) FROM messages r JOIN messagesText_content rt ON rt.docid = r.id WHERE r.conversationID = m.conversationID AND rt.c3author LIKE '%$(ME)%'), 0) < MAX(m.date) ORDER BY 1 LIMIT $(or $(N),20)
# Ad-hoc escape hatch — a question without a catalog edit; still bound
# by the same read-only connection: make mail-sql SQL='SELECT ...'
GLODA_QUERY_sql = $(or $(SQL),$(error mail-sql: needs SQL='SELECT ...'))

# Architecture spec (same idiom as demos/vessels/docs/stack.puml).
mk/features/Network/Email/stack.png: mk/features/Network/Email/stack.puml
	plantuml -tpng $<

mail-%:
	$(if $(GLODA_QUERY_$*),,$(error unknown query '$*' — known: $(patsubst GLODA_QUERY_%,%,$(filter GLODA_QUERY_%,$(.VARIABLES)))))
	@$(if $(GLODA),sqlite3 -box -cmd '.timeout 15000' "file:$(GLODA)?mode=ro" "$(GLODA_QUERY_$*)",echo ">>> no Gloda index — POST advisory gloda_index names the human step")
