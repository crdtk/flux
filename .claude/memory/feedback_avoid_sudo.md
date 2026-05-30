---
name: Avoid sudo — try without first
description: Always design Makefile targets and shell commands to run without sudo; only escalate when the specific operation requires root
type: feedback
originSessionId: 742e51d0-dbf3-40f5-8c69-aaf265a29e95
---
Default to non-root. Before writing a target that uses sudo or expects `sudo make`, ask: does this specific operation actually require root?

**Why:** `/mnt/backup` is `chmod 1777` — any user can create subdirs and set permissions on dirs they own. Syncthing API is a local HTTP call. Most setup tasks in this project can run as the user. Reaching for sudo by default adds unnecessary friction and breaks the principle of least privilege.

**How to apply:**
- Use a local sentinel (e.g. `$(REAL_HOME)/.config/...`) instead of `/etc/` unless the operation genuinely writes to a system path
- `mkdir` + `chmod` on user-owned or world-writable paths: no sudo
- Syncthing REST API calls: no sudo
- `touch $@` on a local sentinel: no sudo
- Only use sudo/root when writing to `/etc/`, `/usr/`, modifying fstab, running `apt`, or similar privileged ops
- When a target mixes root and non-root steps, split it into two targets rather than sudo-ing the whole thing
