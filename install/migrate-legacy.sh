#!/usr/bin/env bash
# Read-only legacy profile migration planner.
set -uo pipefail

LEGACY_ROOT="${HOME}/.vscode-ai-bootstrap"
TARGET_ROOT="${HOME}/.assured-arc"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --legacy-profile-root) LEGACY_ROOT="$2"; shift 2 ;;
    --target-profile-root) TARGET_ROOT="$2"; shift 2 ;;
    *) echo 'Usage: install/migrate-legacy.sh [--legacy-profile-root PATH] [--target-profile-root PATH]' >&2; exit 1 ;;
  esac
done
command -v python3 >/dev/null 2>&1 || { echo 'FAIL COMMAND python3'; exit 1; }
python3 - "$LEGACY_ROOT" "$TARGET_ROOT" <<'PY'
import hashlib, json, os, re, sys
legacy, target = map(lambda value: os.path.abspath(os.path.expanduser(value)), sys.argv[1:])
path = os.path.join(legacy, 'state.json')
healthy = True
def check(ok, label, detail=''):
    global healthy
    print(('PASS' if ok else 'FAIL') + ' ' + label + ((': ' + detail) if detail else ''))
    healthy = healthy and ok
if not os.path.isfile(path):
    check(False, 'LEGACY STATE', 'not found')
    raise SystemExit(1)
try: state = json.load(open(path, encoding='utf-8-sig'))
except (OSError, json.JSONDecodeError):
    check(False, 'LEGACY STATE JSON', 'invalid')
    raise SystemExit(1)
schema = state.get('schema')
check(schema in (2, 3, 4), 'LEGACY SCHEMA', str(schema))
if isinstance(schema, int) and schema >= 3:
    checksum = path + '.sha256'
    try: valid = os.path.isfile(checksum) and open(checksum, encoding='ascii').read().strip().lower() == hashlib.sha256(open(path, 'rb').read()).hexdigest()
    except OSError: valid = False
    check(valid, 'LEGACY CHECKSUM')
if not healthy: raise SystemExit(1)
paths = [item.get('target') for item in state.get('managed', [])] + state.get('created', [])
paths += [value for item in state.get('backups', []) for value in (item.get('target'), item.get('backup'))]
paths += [state.get('settings', {}).get('target'), state.get('mcp', {}).get('target'), state.get('copilotCli', {}).get('root'), state.get('copilotCli', {}).get('settings', {}).get('target'), state.get('copilotCli', {}).get('mcp', {}).get('target')]
paths += [state.get(key) for key in ('profileRoot', 'copilotRoot', 'vscodeUserDirectory', 'vaultPath')]
check(all(not value or os.path.isabs(str(value)) for value in paths), 'OWNERSHIP PATHS', 'absolute')
managed = state.get('managed', [])
print(f"PASS OWNED COMPONENTS: {len(managed)} managed entries; {len(state.get('extensions', []))} extensions")
ids = state.get('mcp', {}).get('serverIds', []) + state.get('copilotCli', {}).get('mcp', {}).get('serverIds', [])
safe = sorted(set(value for value in ids if re.fullmatch(r'[A-Za-z0-9._-]+', str(value))))
print('PASS OWNED MCP IDS: ' + (', '.join(safe) if safe else 'none'))
conflict = os.path.isdir(target) and bool(os.listdir(target))
check(not conflict, 'TARGET CONFLICT', 'target is not empty' if conflict else 'none')
if healthy:
    print('NEXT 1: run the matching legacy uninstall script with --profile-root <legacy-profile-root>.')
    print('NEXT 2: bash install/assured-arc.sh --profile Full --profile-root <target-profile-root>')
raise SystemExit(0 if healthy else 1)
PY