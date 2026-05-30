---
name: Respect User Edits
description: Read and understand user's manual file edits before making further changes — never revert simplifications without explicit permission
type: feedback
originSessionId: 742e51d0-dbf3-40f5-8c69-aaf265a29e95
---
When the user manually edits a file I'm working on, read the current state first and understand their intent BEFORE making further changes. Do not revert simplifications or re-add content the user removed.

**Why:** User edited the Makefile to remove multiple ISO declarations (kept only Kubuntu 25.10). When I later added Kubuntu 26.04 Beta, I re-added all the other ISOs they had removed, undoing their deliberate simplification. User had to tell me to stop changing their changes.

**How to apply:**
1. When a system-reminder says a file was modified, READ the full file first
2. State the user's intent in plain language before editing
3. Only add exactly what was requested — do not re-add removed content
4. If additions depend on removed content, ASK before re-adding

**Specific example (Makefile ordering):** User reordered the hardware project Makefile by workflow sequence ("what to do next" at top, "already done" in middle, utilities/cleanup at bottom) instead of conventional "definitions first, targets last". The `all` target points to the current workflow step (e.g. `all: copy` when install is already done). Do not "clean up" back to conventional make layout — the workflow ordering is intentional.
