#!/usr/bin/env python3
"""PostToolUse hook: validate Makefile / .mk files against the constitution.

Norton-style diagnostic: Check → Score → Gate → Report

Principles enforced:
  p3  — No $(shell ...) in recipes (decide at parse time)
  p4  — No exit / set -e in recipes (sense, warn, continue)
  p5  — .PHONY reserved for {system, user, clean, all}
  p6  — No dot-targets; use real file targets or ifeq in recipe body
  p7  — No $< after order-only |
  p8  — No sudo in recipes (branch via IS_ROOT gate)
  p9  — Dependents before prerequisites; variable locality ≤ 6 lines
  p10 — .PHONY opens its section
  p12 — jq over python3/awk for structured data
  p14 — Intermediates not promoted to accumulators
  p20 — One real recipe line per target ($(file) and echo/printf lines excluded)
  p21 — No nested $(MAKE)
  p22 — No && lumping between non-echo commands; use prerequisite chains instead

Complexity score (lower is better):
  +max(0, real_lines-1) per target     p20 recipe weight ($(file), echo, printf excluded)
  +locality_distance per variable      p9 locality
  +3 per python3-for-JSON usage        p12 wrong tool
  -1 per jq usage in recipes           p12 right tool reward
  +2 per extra .PHONY beyond allowed   p5 phony bloat
  +5 per dot-target                    p6 dot-target smell
  +1 per && between non-echo commands  p22 decomposition pressure
  WARN ≥ 20 · CRITICAL ≥ 50

p20 + p22 together favour dependency chain decomposition: the only way to satisfy
both is a single atomic command per target (with optional trailing && echo status).
"""

import json, sys, re, os

WARN_THRESHOLD     = 20
CRITICAL_THRESHOLD = 50


def load(path):
    with open(path) as f:
        return f.readlines()


def strip_comments(lines):
    result = []
    for l in lines:
        if l.startswith('\t'):
            result.append(l)
        else:
            result.append(re.sub(r'(?<!\$)#.*', '', l).rstrip() + '\n')
    return result


def resolve_continuations(lines):
    joined, src_map = [], []
    buf, start_line = '', 1
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


# ── Structural checks (violations only) ───────────────────────────────────────

def p3_no_shell_in_recipes(lines):
    out = []
    for i, l in enumerate(lines, 1):
        if l.startswith('\t') and re.search(r'\$\(shell\s', l):
            out.append(f"L{i} p3 — $(shell ...) in recipe, move to parse-time variable: {l.rstrip()}")
    return out


def p4_no_exit_in_recipes(lines):
    out = []
    for i, l in enumerate(lines, 1):
        if not l.startswith('\t'):
            continue
        if re.search(r'\bexit\s+["\'$]?\d', l):
            out.append(f"L{i} p4 — 'exit N' in recipe, warn instead: {l.rstrip()}")
        if re.search(r'\bset\s+-[euo]', l):
            out.append(f"L{i} p4 — 'set -e' in recipe, don't fail: {l.rstrip()}")
    return out


def p7_no_autovar_after_orderonly(lines):
    targets_with_orderonly = set()
    for l in lines:
        m = re.match(r'^([^#\t\s].*?):.*\|', l)
        if m:
            targets_with_orderonly.add(m.group(1).strip().split()[0])
    current_target, out = None, []
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
        if not l.startswith('\t'):
            continue
        if re.match(r'\t\s*@?\s*(echo|printf|#)', l):
            continue
        if re.search(r'\bsudo\b', l):
            out.append(f"L{i} p8 — sudo in recipe: {l.rstrip()}")
    return out


def p9_dependents_before_prereqs(lines, logical_lines, src_map):
    def is_comment_or_empty(l):
        return not l.strip() or l.strip().startswith('#')

    target_lineno = {}
    for idx, l in enumerate(logical_lines):
        if is_comment_or_empty(l):
            continue
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
        prereqs = m.group(2).split('|')[0].split()
        for prereq in prereqs:
            if prereq in target_lineno and target_lineno[prereq] < src_map[idx]:
                out.append(
                    f"L{src_map[idx]} p9 — prerequisite '{prereq}' (L{target_lineno[prereq]}) "
                    f"before dependent '{target}': swap order"
                )
    return out


def p10_phony_opens_section(lines):
    out = []
    for i, l in enumerate(lines, 1):
        m = re.match(r'^\.PHONY:\s*(.*)', l)
        if not m:
            continue
        phony_targets = m.group(1).split()
        for j in range(i, len(lines)):
            next_line = lines[j]
            if not next_line.strip() or next_line.strip().startswith('#'):
                continue
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


def p21_no_nested_make(lines):
    out = []
    for i, l in enumerate(lines, 1):
        if l.startswith('\t') and '$(MAKE)' in l:
            out.append(f"L{i} p21 — nested $(MAKE) in recipe: {l.rstrip()}")
    return out


def p14_no_intermediates_in_accumulators(lines, logical_lines, src_map):
    ACCUMULATORS = {'MANAGEMENT', 'HARDENING', 'INSTALL', 'COMPUTE',
                    'STORAGE', 'DISPLAY_CONFIG', 'DEB_URLS', 'PKG_APPS', 'USER_FILES'}
    accumulator_entries = set()
    current_add = None
    for l in lines:
        m = re.match(
            r'^(MANAGEMENT|HARDENING|INSTALL|COMPUTE|STORAGE|DISPLAY_CONFIG|DEB_URLS|PKG_APPS|USER_FILES)'
            r'\s*\+?=\s*(.*)', l)
        if m:
            current_add = m.group(1)
            vals = m.group(2).strip()
            if vals and not vals.endswith('\\'):
                for v in vals.split():
                    accumulator_entries.add(v.rstrip('\\'))
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
    for idx, l in enumerate(logical_lines):
        m = re.match(r'^([^#\t\s].*?):(\s*[^=].*)', l)
        if not m:
            continue
        target = m.group(1).strip()
        if '$' in target:
            continue
        if target in accumulator_entries:
            prereqs = m.group(2).split('|')[0].split()
            for p in prereqs:
                if p.startswith('/') and p in accumulator_entries:
                    out.append(
                        f"L{src_map[idx]} p14 — '{p}' is a prerequisite of '{target}' "
                        f"(also in accumulator) — intermediates don't belong in accumulators"
                    )
    return out


# ── Scored checks (violations + numeric penalty) ──────────────────────────────

_MAKE_BUILTINS = {
    '.PHONY', '.DEFAULT', '.PRECIOUS', '.SECONDARY', '.SUFFIXES',
    '.DELETE_ON_ERROR', '.IGNORE', '.SILENT', '.EXPORT_ALL_VARIABLES',
    '.NOTPARALLEL', '.ONESHELL', '.POSIX', '.INTERMEDIATE', '.NOTINTERMEDIATE',
}

def p6_dot_targets(lines):
    """Returns (violations, count). Penalty = 5 per dot-target.
    Dot-targets look like file targets but produce nothing, bypassing Make's
    dependency tracking. Use a real file target (or sentinel) instead, or an
    ifeq condition in the recipe body of a parent target.
    Make built-in specials (.PHONY, .DEFAULT, etc.) are excluded."""
    violations, count = [], 0
    for i, l in enumerate(lines, 1):
        m = re.match(r'^(\.[a-zA-Z][^:\s]*):', l)
        if m and m.group(1) not in _MAKE_BUILTINS:
            violations.append(
                f"L{i} p6 — dot-target '{m.group(1)}': use a real file target or ifeq in recipe body"
            )
            count += 1
    return violations, count


def p5_phony_discipline(lines):
    """Returns (violations, penalty). Penalty = 2 per extra .PHONY beyond allowed."""
    ALLOWED = {'all', 'system', 'user', 'clean'}
    violations, penalty = [], 0
    for i, l in enumerate(lines, 1):
        m = re.match(r'^\.PHONY:\s*(.*)', l)
        if not m:
            continue
        for t in m.group(1).split():
            if t not in ALLOWED:
                violations.append(f"L{i} p5 — non-aggregate .PHONY '{t}': convert to real file target or ifeq in recipe body")
                penalty += 2
    return violations, penalty


def p9_variable_locality(lines):
    """Returns (violations, total_distance). Penalty = total_distance."""
    var_defs = {}
    for i, l in enumerate(lines, 1):
        m = re.match(r'^([A-Z][A-Z0-9_a-z]+)\s*:=', l)
        if m:
            var_defs[m.group(1)] = i

    violations, total_distance = [], 0
    for name, def_line in var_defs.items():
        first_use = None
        for i, l in enumerate(lines, 1):
            if i <= def_line:
                continue
            if re.search(r'\$\([\s]*' + re.escape(name) + r'[\s]*\)', l) or \
               re.search(r'\$\{[\s]*' + re.escape(name) + r'[\s]*\}', l):
                first_use = i
                break
            if re.match(r'[^#\t]', l) and f'$({name})' in l:
                first_use = i
                break
        if first_use:
            dist = first_use - def_line
            total_distance += dist
            if dist > 6:
                violations.append(
                    f"L{def_line} p9 — '{name}' defined, first used L{first_use} ({dist} lines away)"
                )
    return violations, total_distance


def p12_tool_hygiene(lines):
    """Returns (violations, wrong_count, jq_count).
    Penalty = 3*wrong_count - jq_count."""
    violations, wrong_count, jq_count = [], 0, 0
    for i, l in enumerate(lines, 1):
        if not l.startswith('\t'):
            continue
        if re.search(r'\bpython3\b.*\bjson\b', l, re.IGNORECASE):
            violations.append(f"L{i} p12 — python3 for JSON, use jq: {l.rstrip()}")
            wrong_count += 1
        if re.search(r'\bjq\b', l):
            jq_count += 1
    return violations, wrong_count, jq_count


def p20_recipe_weight(lines):
    """Returns (violations, penalty, target_count).
    Penalty = Σ max(0, shell_lines - 1) per target.
    $(file ...) lines are Make functions (not shell commands) and are excluded."""
    violations, total_penalty, target_count = [], 0, 0
    current_target, current_start, recipe_buf = None, 0, []

    _EXEMPT = {'all', 'system', 'user', 'clean'}

    def flush():
        nonlocal total_penalty, target_count
        if not current_target:
            return
        if current_target in _EXEMPT:
            return
        target_count += 1
        # $(file ...) is a Make function; echo/printf are status reporting — neither counts
        substantive = [l for l in recipe_buf
                       if l.strip()
                       and not re.match(r'\t\s*\$\(file\b', l)
                       and not re.match(r'\t\s*@?\s*(echo|printf)\b', l)]
        excess = max(0, len(substantive) - 1)
        if excess:
            total_penalty += excess
            violations.append(
                f"L{current_start} p20 — '{current_target}' has {len(substantive)} recipe lines "
                f"(+{excess}): simplify (XX)"
            )

    for i, l in enumerate(lines, 1):
        if l.startswith('\t'):
            if current_target is not None:
                recipe_buf.append(l)
        else:
            flush()
            m = re.match(r'^([^#\t\s][^:=\s]*)\s*:', l)
            if m and not re.match(r'^[A-Z_a-z][A-Z_a-z0-9]*\s*[\+:?]?=', l):
                current_target = m.group(1).strip()
                current_start  = i
                recipe_buf     = []
            else:
                current_target = None
                recipe_buf     = []
    flush()
    return violations, total_penalty, target_count


def p22_ampersand_lumping(lines):
    """Returns (violations, count). Penalty = +1 per && connecting non-echo commands.
    cmd && echo/printf is exempt — status reporting is not decomposable into a prereq.
    Every other && is a signal of a missing prerequisite chain."""
    violations, count = [], 0
    for i, l in enumerate(lines, 1):
        if not l.startswith('\t'):
            continue
        stripped = re.sub(r'"[^"]*"', '""', l)
        stripped = re.sub(r"'[^']*'", "''", stripped)
        parts = re.split(r'&&', stripped)
        n = 0
        for j in range(len(parts) - 1):
            following = parts[j + 1].strip().lstrip('@')
            if not re.match(r'(echo|printf)\b', following):
                n += 1
        if n:
            count += n
            violations.append(
                f"L{i} p22 — {n} && lump{'s' if n > 1 else ''}: decompose into prerequisite chain"
            )
    return violations, count


# ── Report ─────────────────────────────────────────────────────────────────────

def format_report(short_path, checks, score, extra_violations):
    gate = ("OK" if score < WARN_THRESHOLD
            else "WARN" if score < CRITICAL_THRESHOLD
            else "CRITICAL")

    lines = [f"━━━ {short_path} ━━━"]
    label_w = max(len(name) for name, _, _ in checks) + 2
    for name, viol, detail in checks:
        icon = "[✓]" if not viol else "[!]"
        lines.append(f"  {(name + ' ').ljust(label_w)} {icon}  {detail}")
    lines.append(f"  {'─' * 44}")
    lines.append(f"  Score {score}  [{gate}]   (warn ≥ {WARN_THRESHOLD}, critical ≥ {CRITICAL_THRESHOLD})")

    all_viol = [v for _, viol, _ in checks for v in viol] + extra_violations
    if all_viol:
        lines.append("")
        for v in all_viol:
            lines.append(f"  • {v}")

    return "\n".join(lines)


# ── Main ───────────────────────────────────────────────────────────────────────

def main():
    data      = json.load(sys.stdin)
    file_path = (data.get('tool_input', {}).get('file_path', '') or
                 data.get('tool_response', {}).get('filePath', ''))

    if not (file_path.endswith('Makefile') or file_path.endswith('.mk')):
        sys.exit(0)

    try:
        lines = load(file_path)
    except OSError:
        sys.exit(0)

    logical_lines, src_map = resolve_continuations(lines)

    # Scored checks
    p5_viol,  p5_pen            = p5_phony_discipline(lines)
    p6_viol,  p6_count          = p6_dot_targets(lines)
    p9_viol,  p9_dist           = p9_variable_locality(lines)
    p12_viol, p12_wrong, p12_jq = p12_tool_hygiene(lines)
    p20_viol, p20_pen, n_tgts   = p20_recipe_weight(lines)
    p22_viol, p22_count         = p22_ampersand_lumping(lines)

    score = max(0, p20_pen + p9_dist + 3 * p12_wrong - p12_jq + p5_pen + 5 * p6_count + p22_count)

    checks = [
        ("p20 Recipe weight",
         p20_viol,
         f"{n_tgts} targets · {p20_pen} excess lines"),
        ("p22 && lumping",
         p22_viol,
         f"0 lumps" if not p22_count else f"{p22_count} && lump{'s' if p22_count != 1 else ''}"),
        ("p9  Locality",
         p9_viol,
         f"{len(p9_viol)} violation{'s' if len(p9_viol) != 1 else ''} · {p9_dist} lines total"),
        ("p12 Tool hygiene",
         p12_viol,
         f"{p12_wrong} wrong · {p12_jq} jq"),
        ("p5  PHONY discipline",
         p5_viol,
         "OK" if not p5_viol else f"{len(p5_viol)} extra beyond {{system,user,clean}}"),
        ("p6  Dot-targets",
         p6_viol,
         "OK" if not p6_viol else f"{p6_count} dot-target{'s' if p6_count != 1 else ''}"),
    ]

    # Structural checks (no score contribution, but must be clean)
    extra = []
    extra.extend(p3_no_shell_in_recipes(lines))
    extra.extend(p4_no_exit_in_recipes(lines))
    extra.extend(p7_no_autovar_after_orderonly(lines))
    extra.extend(p8_no_sudo_in_recipes(lines))
    extra.extend(p9_dependents_before_prereqs(lines, logical_lines, src_map))
    extra.extend(p10_phony_opens_section(lines))
    extra.extend(p14_no_intermediates_in_accumulators(lines, logical_lines, src_map))
    extra.extend(p21_no_nested_make(lines))

    short_path = os.path.relpath(file_path)
    report     = format_report(short_path, checks, score, extra)

    print(json.dumps({"systemMessage": report}))


if __name__ == '__main__':
    main()
