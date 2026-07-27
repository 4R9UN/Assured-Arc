#!/usr/bin/env bash
# Read-only Assured Arc health check.
set -uo pipefail

PROFILE_ROOT="${HOME}/.assured-arc"
if [[ "${1:-}" == "--profile-root" && -n "${2:-}" ]]; then PROFILE_ROOT="$2"; shift 2; fi
[[ $# -eq 0 ]] || { echo 'Usage: install/doctor.sh [--profile-root PATH]' >&2; exit 1; }
healthy=true
check_command() {
  if command -v "$1" >/dev/null 2>&1; then echo "PASS COMMAND $1"; else echo "FAIL COMMAND $1"; healthy=false; fi
}

STATE_PATH="${PROFILE_ROOT}/state.json"
if [[ ! -f "$STATE_PATH" ]]; then
    echo 'PASS STATE: not installed; optional component prerequisites not inferred'
    exit 0
fi
check_command python3
command -v python3 >/dev/null 2>&1 || exit 1
python3 - "$STATE_PATH" <<'PY'
import hashlib, json, os, shutil, sys
path = sys.argv[1]
healthy = True
def check(ok, label, detail=''):
    global healthy
    print(('PASS' if ok else 'FAIL') + ' ' + label + ((': ' + detail) if detail else ''))
    healthy = healthy and ok
try:
    state = json.load(open(path, encoding='utf-8-sig'))
except (OSError, json.JSONDecodeError):
    check(False, 'STATE JSON', 'invalid')
    raise SystemExit(1)
schema = state.get('schema')
check(schema in (2, 3, 4), 'STATE SCHEMA', str(schema))
if isinstance(schema, int) and schema >= 3:
    checksum = path + '.sha256'
    try: valid = os.path.isfile(checksum) and open(checksum, encoding='ascii').read().strip().lower() == hashlib.sha256(open(path, 'rb').read()).hexdigest()
    except OSError: valid = False
    check(valid, 'STATE CHECKSUM')
else:
    check(True, 'STATE CHECKSUM', 'not required by schema')
commands = []
if state.get('extensions'): commands.append('code')
managed = state.get('managed', [])
if state.get('mcp', {}).get('target') or any(item.get('kind') == 'mcp-runtime' for item in managed): commands += ['node', 'npx', 'uv']
if state.get('copilotCli', {}).get('enabled'): commands.append('copilot')
for command in commands: check(shutil.which(command) is not None, 'COMMAND ' + command)
missing = [item for item in managed if not os.path.isabs(str(item.get('target', ''))) or not os.path.exists(item.get('target', ''))]
check(not missing, 'MANAGED FILES', f'{len(managed) - len(missing)}/{len(managed)} present')
runtimes = [item for item in managed if item.get('kind') == 'mcp-runtime']
missing_runtime = [item for item in runtimes if not os.path.exists(item.get('target', ''))]
check(not missing_runtime, 'MCP RUNTIME', f'{len(runtimes) - len(missing_runtime)}/{len(runtimes)} present' if runtimes else 'not recorded')
raise SystemExit(0 if healthy else 1)
PY