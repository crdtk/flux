---
name: Inline .PHONY Declarations
description: Co-locate .PHONY declarations with each target instead of consolidating at the top of the Makefile
type: feedback
originSessionId: 742e51d0-dbf3-40f5-8c69-aaf265a29e95
---
In Makefiles, place `.PHONY: <target>` immediately above each phony target instead of using a single consolidated `.PHONY:` line at the top.

**Why:** User's hardware project Makefile uses workflow ordering — definitions and targets in the order they're used, not conventional "all variables first, all targets last". A consolidated `.PHONY` line at the top forces you to maintain a separate list and creates drift (stale entries for removed targets, missing entries for new ones). Inline `.PHONY` keeps each target's phony-ness visible at the point of use.

**Pattern:**
```makefile
# Instead of:
.PHONY: all clean install copy

all: copy
clean:
	rm -rf build/
install:
	cp ...
copy:
	cp ...

# Use:
.PHONY: all
all: copy

.PHONY: clean
clean:
	rm -rf build/

.PHONY: install
install:
	cp ...

.PHONY: copy
copy:
	cp ...
```

**How to apply:**
1. When creating new phony targets, add `.PHONY: <name>` immediately above
2. When removing targets, the `.PHONY` declaration goes with it (no stale leftovers)
3. File targets (real files Make builds) get NO `.PHONY` declaration
4. Pattern rules (`%.o:`) get NO `.PHONY` declaration
5. Don't consolidate inline declarations into a single top-of-file line — defeats the purpose
