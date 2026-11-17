#!/usr/bin/env python3
"""Print a compact summary of build/selftest-results.json (data only)."""
import json, sys
try:
    r = json.load(open(sys.argv[1], encoding='utf-8'))
except Exception as e:
    print('no self-test results:', e); sys.exit(1)
fails = [t for t in r['results'] if not t['pass']]
for t in r['results']:
    print(('PASS ' if t['pass'] else 'FAIL ') + t['id'].ljust(26) + t['name'] + ('' if t['pass'] else '  -> ' + t['detail']))
for b in r.get('benchmarks', []):
    print('BENCH %-14s %-48s %9.1f ms (limit %d)' % (b['id'], b['name'], b['ms'], b['limitMs']))
print('\n%d tests, %d failed; %d/%d menu commands implemented' % (len(r['results']), len(fails), len(r['implementedCommands']), r['menuCommandCount']))
