#!/usr/bin/env python3
"""Pre-commit hook: validate Makefile / .mk files against the constitution.

Principles enforced (by section number):
  p3 — No $(shell ...) in recipes (decide at parse time)
  p4 — No exit / set -e in recipes (sense, warn, continue)
  p5 — Non-aggregate .PHONY entries (reserve for system, user, clean)
  p7 — No $< after | (order-only voids automatic variables)
  p8 — No sudo in recipes (branch via IS_ROOT gate)
  p9 — Dependents before prerequisites
  p10— .PHONY opens its section (next target follows)
  p14— Intermediates not promoted to accumulators
  p21— No nested $(MAKE)
  p9-locality — Variable defined within 6 lines of first use
"""

import json, sys, re


def load(path):
    with open(path) as f:
        return f.readlines()


def strip_comments(lines):
    """Return lines with comments stripped (but keep recipe lines intact)."""
    result = []
    for l in lines:
        if l.startswith('\t'):
            result.append(l)
        else:
            result.append(re.sub(r'(?<!\$)#.*', '', l).rstrip() + '\n')
    return result


def resolve_continuations(lines):
    """Join lines ending with \\ into single logical lines.
    Returns (logical_lines, source_map) where source_map[i] = original line number start.
    """
    joined = []
    src_map = []
    buf = ''
    start_line = 1
    for i, l in enumerate(lines, 1):
        stripped = l.rstrip('\n')
        if stripped.endswith('\\') and not l.startswith('\t'):
            buf += stripped[:-1] + ' '
        else:
            buf += stripped
            joined.append(buf)
            src_map.append(start_line)
            buf = ''
            start_line = i + 1
    if buf:
        joined.append(buf)
        src_map.append(start_line)
    return joined, src_map


# ---- Check helpers ----

def p3_no_shell_in_recipes(lines):
    """$(shell ...) belongs in parse-time variables, not recipes."""
    out = []
    for i, l in enumerate(lines, 1):
        if l.startswith('\t') and re.search(r'\$\(shell\s', l):
            out.append(f"L{i} p3 — $(shell ...) in recipe, move to parse-time variable: {l.rstrip()}")
    return out


def p4_no_exit_in_recipes(lines):
    """Never exit — sense, act, warn, continue."""
    out = []
    for i, l in enumerate(lines, 1):
        if not l.startswith('\t'):
            continue
        if re.search(r'\bexit\s+["\'$]?\d', l):
            out.append(f"L{i} p4 — 'exit N' in recipe, warn instead: {l.rstrip()}")
        if re.search(r'\bset\s+-[euo]', l):
            out.append(f"L{i} p4 — 'set -e' in recipe, don't fail: {l.rstrip()}")
    return out


def p5_phony_for_aggregate_only(lines):
    """Only system, user, clean, and all should be .PHONY."""
    ALLOWED = {'all', 'system', 'user', 'clean'}
    out = []
    for i, l in enumerate(lines, 1):
        m = re.match(r'^\.PHONY:\s*(.*)', l)
        if not m:
            continue
        targets = m.group(1).split()
        for t in targets:
            if t not in ALLOWED:
                out.append(f"L{i} p5 — non-aggregate .PHONY '{t}', use dot-target instead: {l.rstrip()}")
    return out


def p7_no_autovar_after_orderonly(lines):
    """If target has order-only prereqs (|), don't use $< in its recipe
    because $< only refers to the first normal prereq."""
    # First pass: collect targets with order-only deps
    targets_with_orderonly = set()
    for i, l in enumerate(lines, 1):
        m = re.match(r'^([^#\t\s].*?):.*\|', l)
        if m:
            t = m.group(1).strip().split()[0]
            targets_with_orderonly.add(t)
    # Second pass: check recipes
    current_target = None
    out = []
    for i, l in enumerate(lines, 1):
        if not l.startswith('\t') and ':' in l and not l.startswith('#'):
            m = re.match(r'^([^#\t\s].*?):', l)
            if m:
                current_target = m.group(1).strip().split()[0]
        elif l.startswith('\t') and '$<' in l and current_target in targets_with_orderonly:
            out.append(f"L{i} p7 — '$<' in recipe of '{current_target}' which has order-only deps (| voids $<)")
    return out


def p8_no_sudo_in_recipes(lines):
    out = []
    for i, l in enumerate(lines, 1):
        if l.startswith('\t') and re.search(r'\bsudo\b', l):
            out.append(f"L{i} p8 — sudo in recipe: {l.rstrip()}")
    return out


def p9_dependents_before_prereqs(lines, logical_lines, src_map):
    """Check ordering: dependent targets appear before their prerequisites."""
    def is_comment_or_empty(l):
        return not l.strip() or l.strip().startswith('#')

    target_lineno = {}
    for idx, l in enumerate(logical_lines):
        if is_comment_or_empty(l):
            continue
        # Match target definitions (not variable assignments)
        m = re.match(r'^([^#\t\s][^:=]*?):(\s*[^=]|$)', l)
        if not m:
            m = re.match(r'^([^#\t\s].*?):(\s*[^=]|$)', l)
        if not m:
            continue
        t = m.group(1).strip()
        if not t or '%' in t or '$' in t or re.search(r'\s', t) or t.startswith('.'):
            continue
        target_lineno[t] = src_map[idx]

    out = []
    for idx, l in enumerate(logical_lines):
        if is_comment_or_empty(l):
            continue
        m = re.match(r'^([^#\t\s].*?):(\s*[^=].+)', l)
        if not m:
            continue
        target = m.group(1).strip()
        if '%' in target or '$' in target or target.startswith('.'):
            continue
        # Everything before any | is a normal prerequisite
        prereqs = m.group(2).split('|')[0].split()
        for prereq in prereqs:
            if prereq in target_lineno and target_lineno[prereq] < src_map[idx]:
                out.append(
                    f"L{src_map[idx]} p9 — prerequisite '{prereq}' (L{target_lineno[prereq]}) "
                    f"before dependent '{target}': swap order"
                )
    return out


def p10_phony_opens_section(lines):
    """Next non-blank non-comment line after .PHONY: target should be 'target:'."""
    out = []
    for i, l in enumerate(lines, 1):
        m = re.match(r'^\.PHONY:\s*(.*)', l)
        if not m:
            continue
        phony_targets = m.group(1).split()
        # Look ahead for next non-blank non-comment line
        for j in range(i, len(lines)):
            next_line = lines[j]
            if not next_line.strip():
                continue
            if next_line.strip().startswith('#'):
                continue
            # Found the next substantive line — should be a target definition
            next_m = re.match(r'^([^#\t\s].*?):', next_line)
            if next_m:
                next_target = next_m.group(1).strip().split()[0]
                if next_target not in phony_targets:
                    out.append(
                        f"L{i} p10 — .PHONY: {' '.join(phony_targets)} opened but "
                        f"next target is '{next_target}' (L{j+1})"
                    )
            break
    return out


def p14_no_intermediates_in_accumulators(lines, logical_lines, src_map):
    """Check that a path listed in an accumulator is not just a prerequisite
    of another accumulator entry (intermediates belong as prereqs only)."""
    # Known accumulator variable names
    ACCUMULATORS = {'MANAGEMENT', 'HARDENING', 'INSTALL', 'COMPUTE',
                    'STORAGE', 'DISPLAY_CONFIG', 'DEB_URLS', 'PKG_APPS',
                    'USER_FILES'}
    INCLUDE_DIRS = {'mk/system/', 'mk/user/', 'mk/'}

    # Collect accumulator entries — values added via +=
    accumulator_entries = set()
    current_add = None
    for l in lines:
        m = re.match(r'^(MANAGEMENT|HARDENING|INSTALL|COMPUTE|STORAGE|DISPLAY_CONFIG|DEB_URLS|PKG_APPS|USER_FILES)\s*\+?=\s*(.*)', l)
        if m:
            current_add = m.group(1)
            vals = m.group(2).strip()
            if vals and not vals.endswith('\\'):
                for v in vals.split():
                    accumulator_entries.add(v.rstrip('\\'))
        elif current_add and l.strip().startswith('#') and not l.startswith('\t'):
            pass
        elif current_add and not l.startswith('\t'):
            vals = l.strip()
            if vals.endswith('\\'):
                vals = vals[:-1].strip()
            if vals:
                for v in vals.split():
                    accumulator_entries.add(v.rstrip('\\'))
            if not l.strip().endswith('\\'):
                current_add = None

    out = []
    # Build set of paths that are prerequisites of accumulator entries
    prereqs_of_accumulator = set()
    current_target = None
    current_target_line = 0

    for idx, l in enumerate(logical_lines):
        m = re.match(r'^([^#\t\s].*?):(\s*[^=].*)', l)
        if not m:
            continue
        target = m.group(1).strip()
        if '$' in target:
            continue
        # Check if this target is in an accumulator
        if target in accumulator_entries or any(target.startswith(d) for d in INCLUDE_DIRS):
            prereqs = m.group(2).split('|')[0].split()
            for p in prereqs:
                if p.startswith('/') and p in accumulator_entries:
                    out.append(
                        f"L{src_map[idx]} p14 — '{p}' is a prerequisite of '{target}' "
                        f"(also in accumulator) — intermediates don't belong in accumulators"
                    )
    return out


def p9_variable_locality(lines):
    """Variable defined with := should appear within 6 lines of first use."""
    # Collect := definitions
    var_defs = {}  # name -> line_number
    for i, l in enumerate(lines, 1):
        m = re.match(r'^([A-Z][A-Z0-9_a-z]+)\s*:=', l)
        if m:
            var_defs[m.group(1)] = i

    out = []
    for name, def_line in var_defs.items():
        first_use = None
        for i, l in enumerate(lines, 1):
            # Skip the definition line itself
            if i <= def_line:
                continue
            # Check for $(NAME) or ${NAME} reference
            if re.search(r'\$\([\s]*' + re.escape(name) + r'[\s]*\)', l) or \
               re.search(r'\$\{[\s]*' + re.escape(name) + r'[\s]*\}', l):
                first_use = i
                break
            # Also check bare usage in target definitions: `$(NAME):`
            if re.match(r'[^#\t]', l) and f'$({name})' in l:
                first_use = i
                break
        if first_use and (first_use - def_line) > 6:
            out.append(
                f"L{def_line} p9-locality — '{name}' defined but first used at L{first_use} "
                f"({first_use - def_line} lines away)"
            )
    return out


def p21_no_nested_make(lines):
    out = []
    for i, l in enumerate(lines, 1):
        if l.startswith('\t') and '$(MAKE)' in l:
            out.append(f"L{i} p21 — nested $(MAKE) in recipe: {l.rstrip()}")
    return out


# ---- Main ----

def main():
    data = json.load(sys.stdin)
    file_path = (data.get('tool_input', {}).get('file_path', '') or
                 data.get('tool_response', {}).get('filePath', ''))

    if not (file_path.endswith('Makefile') or file_path.endswith('.mk')):
        sys.exit(0)

    try:
        lines = load(file_path)
    except OSError:
        sys.exit(0)

    logical_lines, src_map = resolve_continuations(lines)

    violations = []

    violations.extend(p3_no_shell_in_recipes(lines))
    violations.extend(p4_no_exit_in_recipes(lines))
    violations.extend(p5_phony_for_aggregate_only(lines))
    violations.extend(p7_no_autovar_after_orderonly(lines))
    violations.extend(p8_no_sudo_in_recipes(lines))
    violations.extend(p9_dependents_before_prereqs(lines, logical_lines, src_map))
    violations.extend(p10_phony_opens_section(lines))
    violations.extend(p14_no_intermediates_in_accumulators(lines, logical_lines, src_map))
    violations.extend(p9_variable_locality(lines))
    violations.extend(p21_no_nested_make(lines))

    if violations:
        print(json.dumps({
            "systemMessage": "Constitution violations:\n" +
                             "\n".join(f"  • {v}" for v in violations)
        }))


if __name__ == '__main__':
    main()
