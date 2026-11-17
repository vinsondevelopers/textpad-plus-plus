#!/usr/bin/env python3
"""Generate Textpad++ command/menu/shortcut tables from the upstream Notepad++ sources.

Reads (as data only) from a Notepad++ source checkout:
  PowerEditor/src/menuCmdID.h, PowerEditor/src/resource.h  -> command id values
  PowerEditor/src/Notepad_plus.rc (IDR_M30_MENU)          -> menu hierarchy and labels
  PowerEditor/src/Parameters.cpp (winKeyDefs, scintKeyDefs) -> default shortcuts

Writes:
  src/generated/NppCommandIds.h       enum of IDM_*/IDC_* values (same numbers as upstream)
  src/generated/NppMenuTable.inc      flattened menu tree
  src/generated/NppShortcutTable.inc  default Windows shortcuts for menu commands
  src/generated/NppScintKeyTable.inc  default Windows shortcuts for Scintilla commands
  docs/reference/menu_inventory.json  machine-readable inventory used by gen_feature_matrix.py

Usage: python3 -I scripts/gen_reference_tables.py <notepad-plus-plus checkout> <textpad project root>
"""
import json
import re
import sys
from pathlib import Path


def parse_defines(paths):
    raw = {}
    pat = re.compile(r'^\s*#\s*define\s+([A-Za-z_][A-Za-z0-9_]*)\s+(.+?)\s*(?://.*)?$')
    for p in paths:
        for line in p.read_text(encoding='utf-8', errors='replace').splitlines():
            m = pat.match(line)
            if m:
                raw.setdefault(m.group(1), m.group(2).strip())
    values = {}

    def resolve(name, depth=0):
        if name in values:
            return values[name]
        if depth > 50 or name not in raw:
            return None
        expr = raw[name]
        tokens = re.findall(r'[A-Za-z_][A-Za-z0-9_]*', expr)
        sub = expr
        for t in sorted(set(tokens), key=len, reverse=True):
            if re.fullmatch(r'0x[0-9A-Fa-f]+', t):
                continue
            v = resolve(t, depth + 1)
            if v is None:
                return None
            sub = re.sub(r'\b%s\b' % t, str(v), sub)
        if not re.fullmatch(r'[\s0-9xXa-fA-F()+\-*|<>]+', sub):
            return None
        try:
            v = int(eval(sub, {"__builtins__": {}}, {}))  # arithmetic on literals only
        except Exception:
            return None
        values[name] = v
        return v

    for n in raw:
        resolve(n)
    return values


def parse_menu(rc_text):
    start = rc_text.index('IDR_M30_MENU MENU')
    lines = rc_text[start:].splitlines()[1:]
    root = []
    stack = [root]
    depth = 0
    language_popups_seen = 0
    skip_depth = None
    for raw in lines:
        line = raw.split('//')[0].strip() if not raw.strip().startswith('MENUITEM "') else raw.strip()
        if raw.strip().startswith('//'):
            continue
        if not line:
            continue
        if line == 'BEGIN':
            depth += 1
            continue
        if line == 'END':
            depth -= 1
            if depth == 0:
                break
            if skip_depth is not None:
                if depth == skip_depth:
                    skip_depth = None
                continue
            stack.pop()
            continue
        if skip_depth is not None:
            continue
        m = re.match(r'POPUP\s+"((?:[^"]|"")*)"', line)
        if m:
            label = m.group(1)
            if depth == 1 and label == '&Language':
                language_popups_seen += 1
                if language_popups_seen == 1:
                    # First variant is the non-compact list; Notepad++ defaults to the compact one.
                    skip_depth = depth
                    continue
            node = {'type': 'popup', 'label': label, 'children': []}
            stack[-1].append(node)
            stack.append(node['children'])
            continue
        if re.match(r'MENUITEM\s+SEPARATOR', line):
            stack[-1].append({'type': 'separator'})
            continue
        m = re.match(r'MENUITEM\s+"((?:[^"]|"")*)"\s*,\s*([A-Za-z0-9_]+)\s*(?:,\s*(.*))?', line)
        if m:
            stack[-1].append({'type': 'item', 'label': m.group(1), 'id': m.group(2),
                              'flags': (m.group(3) or '').strip()})
    return root


def parse_keydefs(cpp_text, array_name):
    start = cpp_text.index(array_name)
    body = cpp_text[start:cpp_text.index('};', start)]
    return body


def parse_winkeys(cpp_text):
    body = parse_keydefs(cpp_text, 'winKeyDefs[]')
    out = []
    pat = re.compile(r'^\s*\{\s*(VK_[A-Z0-9_]+)\s*,\s*([A-Z0-9_]+)\s*,\s*(true|false)\s*,\s*(true|false)\s*,\s*(true|false)\s*,\s*(nullptr|L"[^"]*")')
    for line in body.splitlines():
        if line.strip().startswith('//'):
            continue
        m = pat.match(line)
        if m:
            name = m.group(6)
            out.append({'vk': m.group(1), 'id': m.group(2), 'ctrl': m.group(3) == 'true',
                        'alt': m.group(4) == 'true', 'shift': m.group(5) == 'true',
                        'name': None if name == 'nullptr' else name[2:-1]})
    return out


def parse_scintkeys(cpp_text):
    body = parse_keydefs(cpp_text, 'scintKeyDefs[]')
    out = []
    pat = re.compile(r'^\s*\{\s*L"([^"]*)"\s*,\s*(SCI_[A-Z0-9_]+)\s*,\s*(true|false)\s*,\s*(true|false)\s*,\s*(true|false)\s*,\s*([A-Z0-9_]+)\s*,\s*([A-Z0-9_]+)')
    for line in body.splitlines():
        if line.strip().startswith('//'):
            continue
        m = pat.match(line)
        if m:
            out.append({'name': m.group(1), 'sci': m.group(2), 'ctrl': m.group(3) == 'true',
                        'alt': m.group(4) == 'true', 'shift': m.group(5) == 'true',
                        'vk': m.group(6), 'menu': m.group(7)})
    return out


def parse_lang_table(sev_text, ids):
    start = sev_text.index('_langNameInfoArray[L_EXTERNAL + 1] = {')
    body = sev_text[start:sev_text.index('};', start)]
    pat = re.compile(r'\{L"([^"]*)",\s*L"([^"]*)",\s*L"([^"]*)",\s*(L_[A-Z0-9_]+),\s*"([^"]*)"\}')
    special = {'L_JAVASCRIPT': 'IDM_LANG_JS', 'L_JS_EMBEDDED': None, 'L_SEARCHRESULT': None, 'L_EXTERNAL': None}
    out = []
    for m in pat.finditer(body):
        name, short, long_, lt, lexer = m.groups()
        idm = special.get(lt, 'IDM_LANG_' + lt[2:])
        out.append({'name': name, 'short': short, 'long': long_, 'langType': lt, 'lexer': lexer,
                    'idm': ids.get(idm, 0) if idm else 0, 'idmName': idm or ''})
    return out


def c_str(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


# Textpad++ shows its own name only: labels never carry the upstream product name, the "?" menu is "Help",
# and the commands that open the upstream project's web sites are left out.
REMOVED_IDS = {'IDM_HOMESWEETHOME', 'IDM_PROJECTPAGE', 'IDM_ONLINEDOCUMENT', 'IDM_FORUM', 'IDM_LANG_UDLCOLLECTION_PROJECT_SITE'}


def rc_label(s):
    # RC uses "" for a literal quote and && for a literal ampersand; & marks the mnemonic.
    s = s.replace('""', '"').replace('Notepad++', 'Textpad++')
    return '&Help' if s == '&?' else s


def main():
    npp = Path(sys.argv[1])
    root = Path(sys.argv[2])
    src = npp / 'PowerEditor' / 'src'
    ids = parse_defines([src / 'menuCmdID.h', src / 'resource.h'])
    rc = (src / 'Notepad_plus.rc').read_text(encoding='utf-8', errors='replace')
    menu = parse_menu(rc)
    params = (src / 'Parameters.cpp').read_text(encoding='utf-8', errors='replace')
    winkeys = parse_winkeys(params)
    scikeys = parse_scintkeys(params)
    sci_ids = parse_defines([npp / 'scintilla' / 'include' / 'Scintilla.h'])

    gen = root / 'src' / 'generated'
    gen.mkdir(parents=True, exist_ok=True)
    header = ('// GENERATED by scripts/gen_reference_tables.py from Notepad++ v8.9.9.1 sources (GPLv3).\n'
              '// Do not edit by hand. Command numbers intentionally match upstream so that\n'
              '// shortcuts.xml / macro files remain compatible.\n')

    used = set()

    def walk(nodes):
        for n in nodes:
            if n['type'] == 'item':
                used.add(n['id'])
            elif n['type'] == 'popup':
                walk(n['children'])
    walk(menu)
    for k in winkeys:
        used.add(k['id'])
    for k in scikeys:
        if k['menu'] != '0':
            used.add(k['menu'])

    enum_names = sorted([n for n in ids if (n.startswith('IDM_') or n.startswith('IDC_')) and ids[n] is not None])
    with open(gen / 'NppCommandIds.h', 'w', encoding='utf-8') as f:
        f.write(header + '#pragma once\n\nnamespace npp {\nenum CommandId : int {\n')
        for n in enum_names:
            f.write(f'    {n} = {ids[n]},\n')
        f.write('};\n} // namespace npp\n')

    flat = []

    def flatten(nodes, depth, path):
        for n in nodes:
            if n['type'] == 'separator':
                flat.append((depth, 2, '', 0, ''))
            elif n['type'] == 'popup':
                flat.append((depth, 1, rc_label(n['label']), 0, ''))
                flatten(n['children'], depth + 1, path + [n['label']])
            else:
                if 'HELP' in n['flags'] and depth == 0:
                    continue  # menubar-end buttons (+, x) are tab-bar extras on Windows
                v = ids.get(n['id'])
                if v is None:
                    raise SystemExit('Unresolved id ' + n['id'])
                if n['id'] not in REMOVED_IDS:
                    flat.append((depth, 0, rc_label(n['label']), v, n['id']))
    # drop the "▼" window-list drop-down popup at the end of the menubar (Windows tab-bar extra)
    menu_clean = [n for n in menu if not (n['type'] == 'popup' and n['label'] == '▼')]
    flatten(menu_clean, 0, [])
    with open(gen / 'NppMenuTable.inc', 'w', encoding='utf-8') as f:
        f.write(header + '// {depth, kind(0=item,1=popup,2=separator), label, commandId, idName}\n')
        for d, k, label, v, name in flat:
            f.write(f'{{{d}, {k}, {c_str(label)}, {v}, {c_str(name)}}},\n')

    with open(gen / 'NppShortcutTable.inc', 'w', encoding='utf-8') as f:
        f.write(header + '// {commandId, vkName, ctrl, alt, shift, extraName}\n')
        for k in winkeys:
            if k['vk'] == 'VK_NULL':
                continue
            v = ids.get(k['id'])
            if v is None:
                continue
            f.write(f'{{{v}, {c_str(k["vk"])}, {str(k["ctrl"]).lower()}, {str(k["alt"]).lower()}, '
                    f'{str(k["shift"]).lower()}, {c_str(k["name"] or "")}}},\n')

    with open(gen / 'NppScintKeyTable.inc', 'w', encoding='utf-8') as f:
        f.write(header + '// {sciMessage, name, vkName, ctrl, alt, shift, menuCommandId}\n')
        last_name = ''
        for k in scikeys:
            sci = sci_ids.get(k['sci'])
            if sci is None:
                continue
            name = k['name'] or last_name
            last_name = name
            menu_id = ids.get(k['menu'], 0) if k['menu'] != '0' else 0
            f.write(f'{{{sci}, {c_str(name)}, {c_str(k["vk"])}, {str(k["ctrl"]).lower()}, '
                    f'{str(k["alt"]).lower()}, {str(k["shift"]).lower()}, {menu_id}}},\n')

    sev = (src / 'ScintillaComponent' / 'ScintillaEditView.cpp').read_text(encoding='utf-8', errors='replace')
    langs = parse_lang_table(sev, ids)
    with open(gen / 'NppLangTable.inc', 'w', encoding='utf-8') as f:
        f.write(header + '// {langsXmlName, shortName, longName, lexerName, menuCommandId}  (upstream ScintillaEditView::_langNameInfoArray)\n')
        for l in langs:
            f.write(f'{{{c_str(l["name"])}, {c_str(l["short"])}, {c_str(l["long"])}, {c_str(l["lexer"])}, {l["idm"]}}},\n')
    inv = {'langs': langs, 'menu': menu_clean, 'ids': {n: ids[n] for n in enum_names},
           'winKeys': winkeys, 'scintKeys': scikeys}
    (root / 'docs' / 'reference').mkdir(parents=True, exist_ok=True)
    (root / 'docs' / 'reference' / 'menu_inventory.json').write_text(json.dumps(inv, indent=1, ensure_ascii=False), encoding='utf-8')
    items = sum(1 for r in flat if r[1] == 0)
    print(f'menu rows={len(flat)} items={items} winKeys={len(winkeys)} scintKeys={len(scikeys)} ids={len(enum_names)}')


if __name__ == '__main__':
    main()
