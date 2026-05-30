---
name: Always use Makefile workflow
description: All actions must go through Makefile targets — no ad-hoc bash, no direct file downloads, no raw curl/wget outside make
type: feedback
originSessionId: 742e51d0-dbf3-40f5-8c69-aaf265a29e95
---
Every action — install, download, configure, build — must be a Makefile target. Then invoke it with `make <target>`. Never run the underlying commands as ad-hoc Bash.

**Why:** Keeps every operation traceable, repeatable, and reviewable. Direct bash commands leave no record, can't be replayed, and bypass the dependency graph that makes Make idempotent.

**How to apply:**
- To download a file: write a file target with `curl`/`wget` in the recipe, then `make <target>`
- To install something: write the install target, then `make <target>`
- To clean up: extend the `clean` target, then `make clean`
- To inspect state (read-only): direct Bash is fine — `lsblk`, `ping`, `cat`, `grep`, etc.
- To diagnose a build error: read the output, fix the Makefile, re-run `make`
- Never run `curl`, `wget`, `apt install`, `cmake`, `cp` directly in Bash as a workaround
