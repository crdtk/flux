---
name: Consult Primary Sources That Are Already in the Project
description: When a manual, datasheet, or spec document has been added to the project, consult it before answering any domain question that document covers — do not fall back on generic knowledge
type: feedback
originSessionId: 742e51d0-dbf3-40f5-8c69-aaf265a29e95
---
When the user has placed a primary source document in the project (manual, datasheet, BOM, spec sheet, vendor PDF, converted Markdown of the same), **that document is the authoritative reference for anything it covers**. Before answering any question about the subject, grep or read the document.

**Why:** In the Crucible project, the user converted the ASRock Rack E3C256D4I-2T manual to Markdown, then asked a few turns later where to install a single SODIMM. I answered "DDR4_A1" from generic DDR3-era habit without checking. The manual's section 2.5 Table "Recommended Memory Configuration" shows clearly that single-DIMM goes in DDR4_A2 or B2 (DDR4 daisy-chain topology, not DDR3 T-topology). The user had to catch my error. A single `grep` on the already-converted manual would have found the right answer in seconds.

**How to apply:**

1. **When a user adds a primary source to the project** (converts a PDF, drops a datasheet, adds a manual, saves a BOM), treat that document as *the* default reference for its subject going forward.
2. **Before answering domain questions, grep the project for primary sources** on that subject. If one exists, consult it first, not last.
3. **Do not let the age of the conversion matter** — a manual converted three turns ago is just as authoritative as one converted now.
4. **Do not compartmentalize tasks** — "I already processed that document in task N" doesn't mean the document stops being relevant in task N+1.
5. **When generic knowledge conflicts with project-local sources, the local source wins.** Generic pattern-matching (e.g. "populate channel A first") is a starting hypothesis, not a final answer. Verify against the specific platform's documentation.
6. **When no project-local source exists but one is available online** (vendor PDF, product page), fall back to `feedback_always_search.md`'s rule — search online, verify, cite.

**Common traps this prevents:**
- DDR3 vs DDR4 memory population conventions (daisy-chain inverts the slot order)
- CPU-specific pinouts vs socket-generic assumptions
- Platform-specific power-wiring (this board has no 24-pin, uses 4-pin + 8-pin instead — I caught that one because I checked, but only because the connector was visually unusual)
- Vendor-specific BMC defaults (IP, credentials)
- Firmware-generation-specific BIOS option names
- **Connector/power requirements for accessories** — e.g. incorrectly told user MB111VP-B needed SATA power, conflating it with the CableCC SF-056 (which does). MB111VP-B manual was in the project and shows PCIe-powered only. Reading it first would have prevented the error.

**Pairs with:**
- `feedback_always_search.md` — extends the same principle from online search to local primary sources
