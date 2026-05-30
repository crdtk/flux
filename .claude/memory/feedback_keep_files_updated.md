---
name: Keep Files Updated for Live Collaboration
description: User reads files as they change and may edit in parallel — keep file state visible and update incrementally so user can follow along and contribute
type: feedback
originSessionId: 742e51d0-dbf3-40f5-8c69-aaf265a29e95
---
The user reads files as they change and may edit them in parallel during a session. Keep file state visible and update incrementally so they can follow along and contribute their own edits.

**Why:** User said "keep the file updated so I can read and contribute" — they're treating this as collaborative real-time editing, not a write-once batch operation.

**How to apply:**
1. After each meaningful change, briefly state WHAT changed and WHERE (file + line range)
2. Do not batch multiple unrelated edits silently — make them visible one at a time
3. Before editing a file, read the latest version (user may have edited since last read)
4. When the user says "go", apply just the previously-discussed change, not a queue of pending changes
5. Pair every edit with a verification step (e.g. dry-run, syntax check, grep) so the user sees the result
6. Combine with `feedback_respect_user_edits.md`: read first, state intent, then act
