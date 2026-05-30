---
name: References Folder Structure
description: How the user organizes reference material in the hardware project — semantic folders by hardware subsystem
type: project
originSessionId: 742e51d0-dbf3-40f5-8c69-aaf265a29e95
---
The user organizes reference material (images, PDFs, ISOs) in `/home/m/Code/hardware/References/` using semantic categories by hardware subsystem, NOT chronologically or by file type.

**Structure:**
- `References/Backup/` — storage hot-swap hardware photos (trays, brackets, caddies)
- `References/Bootstrap/` — OS installation artifacts (Ventoy, Kubuntu ISO)
- `References/Case/` — case visuals and manuals, with per-model subfolders (e.g. `Case/ENTHOO PRO II/`)
- `References/Processor/` — CPU photos and references

**Principles:**
1. Nested subfolders for specific hardware when multiple files exist (e.g. `Case/ENTHOO PRO II/` holds 5 screenshots + manual PDF)
2. Mixed file types allowed per folder (images + PDFs + ISOs together)
3. Original filenames preserved — no renaming to "cleaner" versions

**Why:** User values semantic grouping over file-type separation. A `images/` or `docs/` folder would scatter related material. The subsystem-based layout lets someone open `Case/` and see everything case-related in one place.

**How to apply:**
- When saving new reference material, place it under the matching subsystem folder
- Create a new subfolder like `References/{Subsystem}/{ModelName}/` if multiple files for one specific product
- Do not rename downloaded files (preserve original names)
- Do not create a top-level `images/` or `docs/` — use semantic folders instead
