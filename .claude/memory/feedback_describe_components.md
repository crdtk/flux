---
name: Describe Components Physically, Not Just by Model Number
description: Always explain what a component IS physically when mentioning it, not just its model/part number
type: feedback
originSessionId: 742e51d0-dbf3-40f5-8c69-aaf265a29e95
---
Always describe what a component is physically when first mentioning it — don't assume the user knows what a model number or connector designation means.

**Why:** User explicitly flagged not knowing what "SFF-8611↔SFF-8611 cable" meant after it had been mentioned repeatedly. Model numbers alone are meaningless without physical description.

**How to apply:** When mentioning any connector, cable, adapter, or part:
- Lead with what it IS physically ("a short cable with small square 4-lane PCIe plugs on both ends")
- Then add the model designation in parentheses if needed for precision ("called SFF-8611 or OCuLink x4")
- Never assume prior familiarity with connector naming schemes (SFF-8611, SFF-8612, SFF-8654, MCIO, SlimSAS, etc.)
