---
name: Feedback: Always Test Makefile Changes
description: After every Makefile edit, run make -n and make -p to verify parse, variable values, and assembled commands
type: feedback
originSessionId: 742e51d0-dbf3-40f5-8c69-aaf265a29e95
---
After every Makefile change, always run:
1. `make -n <target>` — verify the target parses and assembles the correct command
2. `make -p 2>/dev/null | grep -E '^VAR'` — verify key variable values at parse time

**Why:** Makefile bugs (ordering, empty variables, wrong flags) are invisible until you run it. Dry-run catches them before the user does.

**How to apply:** Do this automatically after every edit, without being asked. It's part of the Makefile skill, not an optional step.
