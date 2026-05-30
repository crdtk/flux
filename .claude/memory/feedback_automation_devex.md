---
name: Feedback: Exhaust Automation / Target Dependencies
description: Always wire up full dependency chains in Makefiles and scripts so targets are self-sufficient — never leave manual prerequisite steps for the user
type: feedback
originSessionId: 742e51d0-dbf3-40f5-8c69-aaf265a29e95
---
Every target must be self-sufficient. If a target needs files, downloads, or prior steps, declare them as dependencies — not as instructions in a comment or follow-up message.

**Why:** User explicitly called this out after `test-tumbleweed` failed because the download step wasn't wired as a prerequisite. The fix was one line (`test-tumbleweed: $(TUMBLEWEED_DL_DIR)/linux $(TUMBLEWEED_DL_DIR)/initrd`) that should have been there from the start.

**How to apply:** When writing any Make target (or shell script, CI step, etc.), ask: "What does this target need to exist before it can run?" — then declare those as prerequisites. Never assume the user will manually run a prior step. Exhaust all automation options before shipping a target. The standard is: `make <target>` works cold from a clean state with no prior manual steps.
