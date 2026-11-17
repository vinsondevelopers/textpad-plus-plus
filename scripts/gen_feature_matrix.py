#!/usr/bin/env python3
"""Generate docs/FEATURE_MATRIX.md and docs/TEST_RESULTS.md.

Inputs (data only):
  docs/reference/menu_inventory.json   upstream menu tree + default shortcuts (gen_reference_tables.py)
  build/selftest-results.json          in-app acceptance results (make selftest)
  build/unit-results.json              unit test results (make unit)
  scripts/feature_notes.json           hand-maintained notes / status ceilings

Status rules: no handler -> "Not started" (or the note's Blocked/Not started); handler + exercised by a
passing in-app test -> "Verified" (unless the note caps it at Partial); handler only -> "Implemented".

Usage: python3 -I scripts/gen_feature_matrix.py <project root>
"""
import json
import sys
from pathlib import Path

root = Path(sys.argv[1] if len(sys.argv) > 1 else '.')
inv = json.loads((root / 'docs/reference/menu_inventory.json').read_text(encoding='utf-8'))
st = json.loads((root / 'build/selftest-results.json').read_text(encoding='utf-8'))
try:
    ut = json.loads((root / 'build/unit-results.json').read_text(encoding='utf-8'))
except FileNotFoundError:
    ut = {'results': []}
notes = json.loads((root / 'scripts/feature_notes.json').read_text(encoding='utf-8'))

ids = inv['ids']
id_by_value = {}
for k, v in ids.items():
    id_by_value.setdefault(v, k)
implemented = set(st['implementedCommands'])
tests_by_cmd = {}
for t in st['results']:
    for c in t['commands']:
        tests_by_cmd.setdefault(c, []).append((t['id'], t['pass']))

mac_keys = {}
win_keys = {}
for k in inv['winKeys']:
    if k['vk'] == 'VK_NULL':
        continue
    desc = ('Ctrl+' if k['ctrl'] else '') + ('Alt+' if k['alt'] else '') + ('Shift+' if k['shift'] else '') + k['vk'][3:].title().replace('Numpad', 'Num ').replace('Prior', 'PgUp').replace('Next', 'PgDn')
    win_keys.setdefault(k['id'], []).append(desc)

MANUAL = {'File': 'Files', 'Edit': 'Editing', 'Search': 'Searching', 'View': 'Views', 'Encoding': 'Preferences/New Document + Encoding',
          'Language': 'Languages / User Defined Languages', 'Settings': 'Preferences, Style Configurator, Shortcut Mapper', 'Tools': 'Main Menu: Tools',
          'Macro': 'Macros', 'Run': 'Run Menu', 'Plugins': 'Plugins', 'Window': 'Main Menu: Window', '?': 'Main Menu: ?'}
DEPS = {'File': 'DocumentManager, EncodingService, AppKit panels', 'Edit': 'Scintilla, TextOps', 'Search': 'Scintilla target search, Boost.Regex',
        'View': 'Scintilla, AppKit', 'Encoding': 'EncodingService (iconv, built-in CP1252)', 'Language': 'Lexilla, langs/stylers XML',
        'Settings': 'NSUserDefaults, XML', 'Tools': 'CommonCrypto', 'Macro': 'Scintilla macro recording, shortcuts.xml', 'Run': 'NSTask (/bin/sh)',
        'Plugins': '-', 'Window': 'DocumentManager', '?': 'AppKit'}


def esc(s):
    return str(s).replace('|', '\\|').replace('\n', ' ')


def clean(label):
    return label.replace('&&', '\x01').replace('&', '').replace('\x01', '&')


rows = []
counter = {}


def walk(nodes, path):
    for n in nodes:
        if n['type'] == 'popup':
            walk(n['children'], path + [clean(n['label'])])
        elif n['type'] == 'item':
            idname = n['id']
            val = ids.get(idname)
            top = path[0] if path else ''
            counter[top] = counter.get(top, 0) + 1
            fid = 'M-%s-%03d' % (''.join(ch for ch in top.upper() if ch.isalpha())[:4] or 'HELP', counter[top])
            note = notes['commands'].get(idname, {})
            tested = tests_by_cmd.get(val, [])
            passing = sorted({t for t, ok in tested if ok})
            failing = sorted({t for t, ok in tested if not ok})
            has = val in implemented
            if not has:
                status = note.get('status', 'Not started')
                if status not in ('Blocked', 'Not started', 'Removed'):
                    status = 'Not started'
            elif note.get('status') in ('Blocked',):
                status = 'Blocked'
            elif note.get('status') == 'Partial':
                status = 'Partial'
            elif passing and not failing:
                status = 'Verified'
            elif failing:
                status = 'Partial (failing test)'
            else:
                status = 'Implemented'
            label = clean(n['label']).replace('Notepad++', 'Textpad++') if idname not in ('IDM_HOMESWEETHOME', 'IDM_PROJECTPAGE', 'IDM_ONLINEDOCUMENT', 'IDM_FORUM', 'IDM_LANG_UDLCOLLECTION_PROJECT_SITE') else clean(n['label'])
            rows.append({
                'id': fid, 'cat': top, 'path': ' > '.join(path + [label]), 'desc': label,
                'ref': 'Notepad_plus.rc / NppCommands.cpp `%s` (%s); manual: %s*' % (idname, val, MANUAL.get(top, top)),
                'win': ', '.join(win_keys.get(idname, [])) or '-', 'mac': note.get('mac', 'Same command'),
                'deps': DEPS.get(top, '-'), 'status': status, 'tests': ', '.join(passing + failing) or '-',
                'diff': note.get('diff', '-'),
            })


walk(inv['menu'], [])

by_status = {}
for r in rows:
    by_status[r['status']] = by_status.get(r['status'], 0) + 1

out = []
out.append('# Textpad++ Feature Matrix\n')
out.append('Generated by `scripts/gen_feature_matrix.py` from the upstream Notepad++ v8.9.9.1 menu resource '
           '(`PowerEditor/src/Notepad_plus.rc`, `IDR_M30_MENU`), its default shortcut table (`Parameters.cpp` `winKeyDefs`) and the '
           'latest `make test` results (%s, %s). **Do not edit by hand** — edit `scripts/feature_notes.json` and re-run.\n' % (st['date'], st['macOS']))
out.append('Status meanings: **Verified** = a passing automated acceptance test executed the command through the command registry; '
           '**Implemented** = real handler, no automated test yet (manual/dialog-driven); **Partial** = works with documented gaps; '
           '**Blocked** = not possible with the current macOS stack (reason given); **Not started** = shown disabled in the menu.\n')
out.append('\\* Manual section names refer to https://npp-user-manual.org/ and were **not individually cross-checked** in this increment; '
           'command ids, labels and shortcuts were verified against the v8.9.9.1 source.\n')
out.append('## Summary\n')
out.append('| Status | Menu commands |\n|---|---|')
for k in ['Verified', 'Implemented', 'Partial', 'Partial (failing test)', 'Blocked', 'Not started', 'Removed']:
    if k in by_status:
        out.append('| %s | %d |' % (k, by_status[k]))
out.append('| **Total** | **%d** |\n' % len(rows))
feat_status = {}
for f in notes['features']:
    feat_status[f[4]] = feat_status.get(f[4], 0) + 1
out.append('Non-menu features: ' + ', '.join('%s %d' % (k, v) for k, v in sorted(feat_status.items())) + ' (total %d).\n' % len(notes['features']))

out.append('## Menu commands (all %d upstream menu items)\n' % len(rows))
out.append('| ID | Category | Original path | Description | Reference | Shortcut (Windows) | macOS behavior | Dependencies | Status | Test ID | Difference |')
out.append('|---|---|---|---|---|---|---|---|---|---|---|')
for r in rows:
    out.append('| ' + ' | '.join(esc(r[k]) for k in ['id', 'cat', 'path', 'desc', 'ref', 'win', 'mac', 'deps', 'status', 'tests', 'diff']) + ' |')

out.append('\n## Non-menu features (UI, file integrity, sessions, preferences, panels, extensions)\n')
out.append('| ID | Category | Original path | Description | Status | Test ID | Difference |')
out.append('|---|---|---|---|---|---|---|')
for f in notes['features']:
    out.append('| ' + ' | '.join(esc(x) if x else '-' for x in f) + ' |')

out.append('\n## Scintilla key commands (upstream `scintKeyDefs`)\n')
out.append('Editing/navigation commands executed by Scintilla itself. In the macOS shortcut scheme Textpad++ keeps Scintilla Cocoa\'s native '
           'macOS keys (e.g. ⌘← line start, ⌥← word left); in the Windows scheme it assigns the upstream keys below with Ctrl = Control '
           '(SCI_ASSIGNCMDKEY, `src/commands/ScintillaKeys.mm`). Every key can be changed in Settings > Shortcut Mapper > Scintilla commands '
           'and is saved in shortcuts.xml <ScintillaKeys> (T-KEYS-003).\n')
out.append('| Scintilla command | Windows shortcut | Textpad++ |')
out.append('|---|---|---|')
mapped = {'SCI_SELECTIONDUPLICATE': '⌘D', 'SCI_LINECUT': '⌘L', 'SCI_LINEDELETE': '⇧⌘L', 'SCI_LINECOPY': '⇧⌘X', 'SCI_LINETRANSPOSE': '⌘T'}
for k in inv['scintKeys']:
    if k['vk'] == '0':
        continue
    desc = ('Ctrl+' if k['ctrl'] else '') + ('Alt+' if k['alt'] else '') + ('Shift+' if k['shift'] else '') + k['vk'][3:].title()
    name = k['name'] or k['sci']
    mac = mapped.get(k['sci'], 'Scintilla Cocoa native binding' if k['sci'] not in ('SCI_SELECTALL', 'SCI_UNDO', 'SCI_REDO', 'SCI_ZOOMIN', 'SCI_ZOOMOUT', 'SCI_SETZOOM', 'SCI_CLEAR') else 'Menu command')
    if k['sci'] in mapped:
        mac += ' (through the matching Edit menu command)'
    out.append('| %s | %s | %s |' % (name, desc, mac))
(root / 'docs/FEATURE_MATRIX.md').write_text('\n'.join(out) + '\n', encoding='utf-8')

# ---------------------------------------------------------------- TEST_RESULTS.md
tr = ['# Textpad++ Test Results\n',
      'Generated by `scripts/gen_feature_matrix.py` from `build/unit-results.json` and `build/selftest-results.json`.\n',
      '- Run date: %s' % st['date'], '- Machine: macOS %s' % st['macOS'],
      '- Build: `make ARCHS="arm64 x86_64" test` (Command Line Tools clang; universal binary, arm64 slice run natively)\n']
u_fail = [t for t in ut['results'] if not t['pass']]
s_fail = [t for t in st['results'] if not t['pass']]
tr.append('## Summary\n')
tr.append('| Suite | Tests | Passed | Failed |\n|---|---|---|---|')
tr.append('| Unit (core C++: encoding, text ops, hashing) | %d | %d | %d |' % (len(ut['results']), len(ut['results']) - len(u_fail), len(u_fail)))
tr.append('| In-app acceptance (real commands, real Scintilla views, real files) | %d | %d | %d |' % (len(st['results']), len(st['results']) - len(s_fail), len(s_fail)))
try:
    sx = json.loads((root / 'build/selftest-results-x86_64.json').read_text(encoding='utf-8'))
    sx_fail = [t for t in sx['results'] if not t['pass']]
    stale = {t['id'] for t in st['results']} - {t['id'] for t in sx['results']}
    note = (' — **earlier build**, %d current tests not run on x86_64' % len(stale)) if stale else ''
    tr.append('| In-app acceptance, **x86_64 slice under Rosetta 2** (%s%s) | %d | %d | %d |' % (sx['date'], note, len(sx['results']), len(sx['results']) - len(sx_fail), len(sx_fail)))
except FileNotFoundError:
    tr.append('| In-app acceptance, x86_64 slice | not run | - | - |')
tr.append('\nMenu commands with a real handler: **%d / %d**. Commands exercised by passing acceptance tests: **%d**.\n' %
          (len(st['implementedCommands']), st['menuCommandCount'], by_status.get('Verified', 0)))
tr.append('## Unit tests\n')
tr.append('| ID | Test | Result | Detail |\n|---|---|---|---|')
for t in ut['results']:
    tr.append('| %s | %s | %s | %s |' % (t['id'], esc(t['name']), 'PASS' if t['pass'] else '**FAIL**', esc(t['detail']) or '-'))
tr.append('\n## In-app acceptance tests\n')
tr.append('| ID | Test | Result | Time (ms) | Commands exercised | Detail |\n|---|---|---|---|---|---|')
for t in st['results']:
    cmds = ', '.join(id_by_value.get(c, str(c)) for c in t['commands'][:12]) + (' …' if len(t['commands']) > 12 else '')
    tr.append('| %s | %s | %s | %.0f | %s | %s |' % (t['id'], esc(t['name']), 'PASS' if t['pass'] else '**FAIL**', t['ms'], cmds or '-', esc(t['detail']) or '-'))
tr.append('\n## Benchmarks (measured on this machine; not compared with Windows Notepad++)\n')
tr.append('| ID | Scenario | Time (ms) | Limit (ms) | Within limit |\n|---|---|---|---|---|')
for b in st.get('benchmarks', []):
    tr.append('| %s | %s | %.1f | %d | %s |' % (b['id'], esc(b['name']), b['ms'], b['limitMs'], 'yes' if b['pass'] else 'no'))
tr.append('\nNo comparative claim against the Windows reference is made: no Windows baseline was measured in this environment.\n')
(root / 'docs/TEST_RESULTS.md').write_text('\n'.join(tr) + '\n', encoding='utf-8')
print('FEATURE_MATRIX rows=%d %s' % (len(rows), by_status))

# ---------------------------------------------------------------- FEATURE_STATUS.md
# One table: every implemented feature first (menu commands in menu order, then the non-menu features),
# then everything that is not implemented (blocked menu commands, then the gaps listed in feature_notes.json).
done_rows, todo_rows, removed_rows = [], [], []
for r in rows:
    if r['status'] == 'Removed':
        removed_rows.append(('Menu: ' + r['cat'], r['path'].replace('Notepad++', 'upstream'), '-', r['diff']))
        continue
    impl = r['status'] in ('Verified', 'Implemented', 'Partial', 'Partial (failing test)')
    checked = r['tests'] if r['tests'] != '-' else ('no automated test yet' if impl else '-')
    note = r['diff'] if r['diff'] != '-' else (r['mac'] if r['mac'] != 'Same command' else '')
    (done_rows if impl else todo_rows).append(('Menu: ' + r['cat'], r['path'], checked, note))
for f in notes['features']:
    impl = f[4] in ('Verified', 'Implemented', 'Partial')
    (done_rows if impl else todo_rows).append((f[1] + ': ' + f[2], f[3], f[5] or 'no automated test yet', f[6]))
for g in notes.get('gaps', []):
    todo_rows.append((g[0], g[1], '-', g[2]))
fs = ['# Textpad++ Feature Status\n',
      'Generated by `scripts/gen_feature_matrix.py` (with FEATURE_MATRIX.md) from the test results of %s. '
      'Every Notepad++ v8.9.9.1 menu command and every other feature in one table: implemented ones first, '
      'then the ones that are not implemented. "Checked by" names the automated tests that exercise it; '
      '"no automated test yet" means it works but is driven by a dialog or system service the suite cannot open.\n' % st['date'][:10],
      '**%d implemented, %d not implemented, %d removed by request.**\n' % (len(done_rows), len(todo_rows), len(removed_rows)),
      '| # | Status | Area | Feature | Checked by | Notes |', '|---|---|---|---|---|---|']
n = 0
for status, group in (('Implemented', done_rows), ('Not implemented', todo_rows), ('Removed (by request)', removed_rows)):
    for area, feat, checked, note in group:
        n += 1
        fs.append('| %d | %s | %s | %s | %s | %s |' % (n, '**%s**' % status if status != 'Implemented' else status, esc(area), esc(feat), esc(checked), esc(note)))
(root / 'docs/FEATURE_STATUS.md').write_text('\n'.join(fs) + '\n', encoding='utf-8')
print('FEATURE_STATUS implemented=%d not implemented=%d' % (len(done_rows), len(todo_rows)))
