#!/usr/bin/env python3
import json, sys, re

data = json.load(sys.stdin)
file_path = (data.get('tool_input', {}).get('file_path', '') or
             data.get('tool_response', {}).get('filePath', ''))

if not (file_path.endswith('Makefile') or file_path.endswith('.mk')):
    sys.exit(0)

try:
    with open(file_path) as f:
        lines = f.readlines()
except OSError:
    sys.exit(0)

violations = []

for i, line in enumerate(lines, 1):
    if not re.match(r'\t', line) or line.strip().startswith('#'):
        continue
    # Principle 8: no sudo in recipes
    if re.search(r'\bsudo\b', line):
        violations.append(f"L{i} p8 — sudo in recipe: {line.rstrip()}")
    # Principle 21: no nested $(MAKE)
    if '$(MAKE)' in line:
        violations.append(f"L{i} p21 — nested $(MAKE): {line.rstrip()}")

# Principle 9: dependents before prerequisites
target_lineno = {}
for i, line in enumerate(lines, 1):
    m = re.match(r'^([^#\t\s][^\s:=][^:=]*?):\s*[^=]', line)
    if not m:
        m = re.match(r'^([^#\t\s][^:=]?):\s*[^=]', line)
    if not m:
        continue
    t = m.group(1).strip()
    if not t or '%' in t or '$' in t or re.search(r'\s', t) or t.startswith('.'):
        continue
    target_lineno[t] = i

for i, line in enumerate(lines, 1):
    m = re.match(r'^([^#\t\s][^:=]*?):\s*([^=].+)', line)
    if not m:
        continue
    target = m.group(1).strip()
    if '%' in target or '$' in target or target.startswith('.'):
        continue
    prereqs = m.group(2).split('|')[0].split()
    for prereq in prereqs:
        if prereq in target_lineno and target_lineno[prereq] < i:
            violations.append(
                f"L{i} p9 — prerequisite '{prereq}' (L{target_lineno[prereq]}) "
                f"before dependent '{target}': swap order"
            )

if violations:
    print(json.dumps({
        "systemMessage": "Constitution violations:\n" +
                         "\n".join(f"  • {v}" for v in violations)
    }))
