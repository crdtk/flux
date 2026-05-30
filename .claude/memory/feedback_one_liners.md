---
name: Prefer one-liners in Makefiles
description: Always consider one-liner Make syntax before multi-line ifeq/else/endif blocks
type: feedback
originSessionId: 742e51d0-dbf3-40f5-8c69-aaf265a29e95
---
Prefer compact Make expressions over multi-line conditional blocks when the logic fits on one line.

**Why:** User explicitly prefers one-liners — cleaner, less visual noise. Confirmed when replacing ifeq/else/endif `all:` target with `$(if $(filter 0,...),...)`.

**How to apply:**
- `$(if condition,then,else)` instead of ifeq/else/endif when it fits on one line
- `$(or ...)`, `$(and ...)` instead of nested conditionals
- Multi-line ifeq only when the branches are themselves multi-line or hard to read inline
