#!/usr/bin/env bash
# Remove package-managed Assured Arc assets on macOS or Linux.
set -euo pipefail

PROFILE_ROOT="${HOME}/.assured-arc"
COPILOT_ROOT=""
COPILOT_CLI_ROOT=""
VSCODE_USER_DIR=""
CODE_COMMAND="code"
RESTORE_BACKUPS=false
REMOVE_EXTENSIONS=false
REMOVE_VAULT=false
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage: install/uninstall.sh [options]

  --profile-root PATH    Managed package state directory
  --copilot-root PATH    Expected managed Copilot customization root
  --copilot-cli-root PATH Expected GitHub Copilot CLI home
  --vscode-user-dir PATH Expected VS Code User directory
  --code-command PATH    VS Code command, default: code
  --restore-backups      Restore pre-install settings and MCP configuration
  --remove-extensions    Uninstall extensions recorded in Assured Arc state
  --remove-vault         Remove the default managed vault under profile root
  --dry-run              Print actions without modifying files
  --help                 Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile-root) PROFILE_ROOT="$2"; shift 2 ;;
    --copilot-root) COPILOT_ROOT="$2"; shift 2 ;;
    --copilot-cli-root) COPILOT_CLI_ROOT="$2"; shift 2 ;;
    --vscode-user-dir) VSCODE_USER_DIR="$2"; shift 2 ;;
    --code-command) CODE_COMMAND="$2"; shift 2 ;;
    --restore-backups) RESTORE_BACKUPS=true; shift ;;
    --remove-extensions) REMOVE_EXTENSIONS=true; shift ;;
    --remove-vault) REMOVE_VAULT=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

command -v python3 >/dev/null || { echo 'Python 3 is required to read Assured Arc state.' >&2; exit 1; }
PROFILE_ROOT="$(python3 - "$PROFILE_ROOT" <<'PY'
import os, sys
print(os.path.abspath(os.path.expanduser(sys.argv[1])))
PY
)"
STATE_PATH="${PROFILE_ROOT}/state.json"
if [[ -z "$COPILOT_ROOT" ]]; then COPILOT_ROOT="${PROFILE_ROOT}/copilot"; fi
COPILOT_ROOT="$(python3 -c 'import os,sys; print(os.path.abspath(os.path.expanduser(sys.argv[1])))' "$COPILOT_ROOT")"
if [[ -z "$COPILOT_CLI_ROOT" ]]; then COPILOT_CLI_ROOT="${COPILOT_HOME:-${HOME}/.copilot}"; fi
COPILOT_CLI_ROOT="$(python3 -c 'import os,sys; print(os.path.abspath(os.path.expanduser(sys.argv[1])))' "$COPILOT_CLI_ROOT")"
if [[ -z "$VSCODE_USER_DIR" ]]; then
  if [[ "$(uname -s)" == Darwin ]]; then VSCODE_USER_DIR="${HOME}/Library/Application Support/Code/User"; else VSCODE_USER_DIR="${HOME}/.config/Code/User"; fi
fi
VSCODE_USER_DIR="$(python3 -c 'import os,sys; print(os.path.abspath(os.path.expanduser(sys.argv[1])))' "$VSCODE_USER_DIR")"

run() {
  if [[ "$DRY_RUN" == true ]]; then
    printf '[dry run]'; printf ' %q' "$@"; printf '\n'
  else
    "$@"
  fi
}

assert_no_symlink_path() {
  python3 - "$1" <<'PY'
from pathlib import Path
import os, sys
path = Path(os.path.abspath(sys.argv[1]))
parts = path.parts
current = Path(parts[0])
for part in parts[1:]:
    current /= part
    if current.is_symlink():
        raise SystemExit(f'Refusing to modify path through symbolic link: {current}')
PY
}

assert_no_symlink_path "$PROFILE_ROOT"
assert_no_symlink_path "$STATE_PATH"
[[ -f "$STATE_PATH" ]] || { echo "Assured Arc state not found: $STATE_PATH" >&2; exit 1; }
python3 - "$STATE_PATH" <<'PY'
import hashlib, json, os, sys
path = sys.argv[1]
state = json.load(open(path, encoding='utf-8'))
if state.get('schema', 0) >= 3:
  hash_path = path + '.sha256'
  if not os.path.isfile(hash_path): raise SystemExit(f'Assured Arc state integrity file not found: {hash_path}')
  expected = open(hash_path, encoding='ascii').read().strip().lower()
  actual = hashlib.sha256(open(path, 'rb').read()).hexdigest()
  if expected != actual: raise SystemExit('Assured Arc state integrity validation failed. No managed paths were changed.')
PY

RUNTIME_DIR="$(mktemp -d)"
trap 'rm -rf "$RUNTIME_DIR"' EXIT
python3 - "$STATE_PATH" "$RUNTIME_DIR" <<'PY'
import json, os, sys
state, output = sys.argv[1:]
data = json.load(open(state, encoding='utf-8'))
for name in ('managed', 'backups', 'extensions'):
    with open(os.path.join(output, name + '.json'), 'w', encoding='utf-8') as f:
        json.dump(data.get(name, []), f)
PY

mapfile -t MANAGED < <(python3 - "$RUNTIME_DIR/managed.json" <<'PY'
import json, sys
for item in json.load(open(sys.argv[1])):
    print(item.get('kind','') + '\t' + item.get('target',''))
PY
)

assert_owned_absolute_path() {
  local path="$1" label="$2"
  [[ -z "$path" ]] && return
  [[ "$path" == /* ]] || { echo "$label path is relative and cannot be trusted: $path" >&2; return 1; }
  assert_no_symlink_path "$path"
}

path_within() {
  python3 - "$1" "$2" <<'PY'
import os, sys
path, root = map(os.path.realpath, sys.argv[1:])
try: ok = os.path.commonpath((path, root)) == root
except ValueError: ok = False
raise SystemExit(0 if ok else 1)
PY
}

IFS=$'\t' read -r STATE_PROFILE STATE_COPILOT STATE_VAULT < <(python3 - "$STATE_PATH" <<'PY'
import json, sys
state = json.load(open(sys.argv[1], encoding='utf-8'))
print('\t'.join(str(state.get(key, '')) for key in ('profileRoot', 'copilotRoot', 'vaultPath')))
PY
)
if [[ -z "$STATE_PROFILE" ]]; then STATE_PROFILE="$PROFILE_ROOT"; fi
assert_owned_absolute_path "$STATE_PROFILE" 'Recorded profile root'
[[ "$STATE_PROFILE" == "$PROFILE_ROOT" ]] || { echo 'Recorded profile root does not match requested profile.' >&2; exit 1; }
assert_owned_absolute_path "$COPILOT_ROOT" 'Selected Copilot root'
if [[ -n "$STATE_COPILOT" && "$STATE_COPILOT" != "$COPILOT_ROOT" ]]; then echo 'Recorded Copilot root does not match selected Copilot root.' >&2; exit 1; fi

IFS=$'\t' read -r CLI_ENABLED STATE_CLI_ROOT CLI_SETTINGS_TARGET CLI_MCP_TARGET < <(python3 - "$STATE_PATH" <<'PY'
import json, sys
cli = json.load(open(sys.argv[1], encoding='utf-8')).get('copilotCli', {})
print('\t'.join((str(cli.get('enabled', False)).lower(), cli.get('root', ''), cli.get('settings', {}).get('target', ''), cli.get('mcp', {}).get('target', ''))))
PY
)
if [[ "$CLI_ENABLED" == true ]]; then
  assert_owned_absolute_path "$COPILOT_CLI_ROOT" 'Selected Copilot CLI root'
  [[ -z "$STATE_CLI_ROOT" || "$STATE_CLI_ROOT" == "$COPILOT_CLI_ROOT" ]] || { echo 'Recorded Copilot CLI root does not match selected Copilot CLI root.' >&2; exit 1; }
  assert_owned_absolute_path "$CLI_SETTINGS_TARGET" 'Copilot CLI settings target'
  assert_owned_absolute_path "$CLI_MCP_TARGET" 'Copilot CLI MCP target'
  [[ -z "$CLI_SETTINGS_TARGET" || "$CLI_SETTINGS_TARGET" == "${COPILOT_CLI_ROOT}/settings.json" ]] || { echo 'Copilot CLI settings target does not match selected root.' >&2; exit 1; }
  [[ -z "$CLI_MCP_TARGET" || "$CLI_MCP_TARGET" == "${COPILOT_CLI_ROOT}/mcp-config.json" ]] || { echo 'Copilot CLI MCP target does not match selected root.' >&2; exit 1; }
fi

MCP_TARGET="$(python3 - "$STATE_PATH" <<'PY'
import json, sys
print(json.load(open(sys.argv[1], encoding='utf-8')).get('mcp', {}).get('target', ''))
PY
)"
SETTINGS_TARGET="$(python3 - "$STATE_PATH" <<'PY'
import json, sys
print(json.load(open(sys.argv[1], encoding='utf-8')).get('settings', {}).get('target', ''))
PY
)"
assert_owned_absolute_path "$SETTINGS_TARGET" 'Settings ownership target'
assert_owned_absolute_path "$MCP_TARGET" 'MCP ownership target'
[[ -z "$SETTINGS_TARGET" || "$SETTINGS_TARGET" == "${VSCODE_USER_DIR}/settings.json" ]] || { echo 'Settings ownership target does not match selected VS Code user directory.' >&2; exit 1; }
[[ -z "$MCP_TARGET" || "$MCP_TARGET" == "${VSCODE_USER_DIR}/mcp.json" ]] || { echo 'MCP ownership target does not match selected VS Code user directory.' >&2; exit 1; }
for record in "${MANAGED[@]}"; do
  kind="${record%%$'\t'*}"
  target="${record#*$'\t'}"
  case "$kind" in
    skill|skill-registry|instruction|agent|prompt|agent-harness|tool-policy|hook-script|hook-config)
      path_within "$target" "$COPILOT_ROOT" || { echo "Managed $kind target is outside the selected Copilot root: $target" >&2; exit 1; } ;;
    cli-agent|cli-instruction|cli-hook-config)
      path_within "$target" "$COPILOT_CLI_ROOT" || { echo "Managed $kind target is outside the selected Copilot CLI root: $target" >&2; exit 1; } ;;
    mcp-runtime|mcp-template)
      path_within "$target" "${STATE_PROFILE}/mcp" || { echo "Managed $kind target is outside the recorded MCP root: $target" >&2; exit 1; } ;;
    vault)
      [[ "$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$target")" == "$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$STATE_VAULT")" ]] || { echo "Managed vault target does not match recorded ownership: $target" >&2; exit 1; } ;;
    settings|mcp|cli-settings|cli-mcp) ;;
    *) echo "Unknown managed target kind in state: $kind" >&2; exit 1 ;;
  esac
  [[ "$kind" == "settings" || "$kind" == "mcp" || "$kind" == "cli-settings" || "$kind" == "cli-mcp" ]] && continue
  [[ "$kind" == "vault" && "$REMOVE_VAULT" != true ]] && continue
  assert_owned_absolute_path "$target" 'Managed target'
done
if [[ "$REMOVE_VAULT" == true && -n "$STATE_VAULT" ]]; then assert_owned_absolute_path "$STATE_VAULT" 'Recorded vault'; fi
if [[ "$RESTORE_BACKUPS" == true ]]; then
  mapfile -t PREFLIGHT_BACKUPS < <(python3 - "$RUNTIME_DIR/backups.json" <<'PY'
import json, sys
for item in json.load(open(sys.argv[1])):
    print(item.get('target','') + '\t' + item.get('backup',''))
PY
)
  for record in "${PREFLIGHT_BACKUPS[@]}"; do
    backup_target="${record%%$'\t'*}"
    backup_source="${record#*$'\t'}"
    assert_owned_absolute_path "$backup_target" 'Backup target'
    assert_owned_absolute_path "$backup_source" 'Backup source'
    path_within "$backup_source" "${STATE_PROFILE}/backups" || { echo "Backup source is outside the recorded backup root: $backup_source" >&2; exit 1; }
    python3 - "$STATE_PATH" "$backup_target" <<'PY'
import json, os, sys
state_path, target = sys.argv[1:]
state = json.load(open(state_path, encoding='utf-8'))
owned = {item.get('target', '') for item in state.get('managed', [])}
settings = state.get('settings', {}).get('target', '')
mcp = state.get('mcp', {}).get('target', '')
cli = state.get('copilotCli', {})
cli_settings = cli.get('settings', {}).get('target', '')
cli_mcp = cli.get('mcp', {}).get('target', '')
owned.update(item for item in (settings, mcp, cli_settings, cli_mcp) if item)
normalized = {os.path.realpath(item) for item in owned}
if os.path.realpath(target) not in normalized:
    raise SystemExit(f'Backup target is not owned by this installer state: {target}')
PY
  done
fi

if [[ "$RESTORE_BACKUPS" != true ]]; then
  if [[ "$DRY_RUN" == true ]]; then
  echo '[dry run] remove package-owned customization location entries'
  else
  python3 - "$STATE_PATH" <<'PY'
import json, os, sys
state = json.load(open(sys.argv[1], encoding='utf-8'))
settings = state.get('settings', {})
target = settings.get('target', '')

def read_jsonc(path):
  text = open(path, encoding='utf-8').read()
  output, i, string, escaped, line, block = [], 0, False, False, False, False
  while i < len(text):
    char = text[i]; nxt = text[i + 1] if i + 1 < len(text) else ''
    if line:
      if char in '\r\n': line = False; output.append(char)
    elif block:
      if char == '*' and nxt == '/': block = False; i += 1
    elif string:
      output.append(char)
      if escaped: escaped = False
      elif char == '\\': escaped = True
      elif char == '"': string = False
    elif char == '"': string = True; output.append(char)
    elif char == '/' and nxt == '/': line = True; i += 1
    elif char == '/' and nxt == '*': block = True; i += 1
    else: output.append(char)
    i += 1
  text = ''.join(output)
  output, i, string, escaped = [], 0, False, False
  while i < len(text):
    char = text[i]
    if string:
      output.append(char)
      if escaped: escaped = False
      elif char == '\\': escaped = True
      elif char == '"': string = False
    elif char == '"': string = True; output.append(char)
    elif char == ',':
      cursor = i + 1
      while cursor < len(text) and text[cursor].isspace(): cursor += 1
      if cursor >= len(text) or text[cursor] not in '}]': output.append(char)
    else: output.append(char)
    i += 1
  return json.loads(''.join(output))

if target and os.path.exists(target):
  try:
    config = read_jsonc(target)
  except Exception as exc:
    raise SystemExit(f'Cannot safely remove managed settings locations from malformed JSON: {target}. Package assets and state were preserved. {exc}')
  for entry in settings.get('locationEntries', []):
    if entry.get('added', True) is False: continue
    value = config.get(entry.get('setting'))
    if isinstance(value, dict): value.pop(entry.get('path'), None)
  with open(target, 'w', encoding='utf-8') as stream:
    json.dump(config, stream, indent=2); stream.write('\n')
PY
  fi
  if [[ "$DRY_RUN" == true ]]; then
    echo '[dry run] remove package-owned MCP server and input entries'
  else
    python3 - "$STATE_PATH" <<'PY'
import json, os, sys
state = json.load(open(sys.argv[1], encoding='utf-8'))
mcp = state.get('mcp', {})
target = mcp.get('target', '')
def read_jsonc(path):
    text = open(path, encoding='utf-8').read()
    output, i, string, escaped, line, block = [], 0, False, False, False, False
    while i < len(text):
        char = text[i]; nxt = text[i + 1] if i + 1 < len(text) else ''
        if line:
            if char in '\r\n': line = False; output.append(char)
        elif block:
            if char == '*' and nxt == '/': block = False; i += 1
        elif string:
            output.append(char)
            if escaped: escaped = False
            elif char == '\\': escaped = True
            elif char == '"': string = False
        elif char == '"': string = True; output.append(char)
        elif char == '/' and nxt == '/': line = True; i += 1
        elif char == '/' and nxt == '*': block = True; i += 1
        else: output.append(char)
        i += 1
    text = ''.join(output)
    output, i, string, escaped = [], 0, False, False
    while i < len(text):
        char = text[i]
        if string:
            output.append(char)
            if escaped: escaped = False
            elif char == '\\': escaped = True
            elif char == '"': string = False
        elif char == '"': string = True; output.append(char)
        elif char == ',':
            cursor = i + 1
            while cursor < len(text) and text[cursor].isspace(): cursor += 1
            if cursor >= len(text) or text[cursor] not in '}]': output.append(char)
        else: output.append(char)
        i += 1
    return json.loads(''.join(output))
if target and os.path.exists(target):
    try:
        config = read_jsonc(target)
    except Exception as exc:
        raise SystemExit(f'Cannot safely remove managed MCP entries from malformed JSON: {target}. Managed MCP runtime and state were preserved. {exc}')
    servers = config.get('servers', {})
    for item in mcp.get('serverIds', []): servers.pop(item, None)
    managed_inputs = set(mcp.get('inputIds', []))
    config['inputs'] = [item for item in config.get('inputs', []) if item.get('id') not in managed_inputs]
    with open(target, 'w', encoding='utf-8') as stream:
        json.dump(config, stream, indent=2); stream.write('\n')
PY
  fi
  if [[ "$DRY_RUN" == true ]]; then
    echo '[dry run] remove package-owned Copilot CLI settings and MCP entries'
  else
    python3 - "$STATE_PATH" <<'PY'
import json, os, re, sys
state = json.load(open(sys.argv[1], encoding='utf-8'))
cli = state.get('copilotCli', {})
def read_jsonc(path):
    text = open(path, encoding='utf-8-sig').read()
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    text = re.sub(r'^\s*//.*$', '', text, flags=re.M)
    text = re.sub(r',\s*([}\]])', r'\1', text)
    return json.loads(text) if text.strip() else {}
settings = cli.get('settings', {})
target = settings.get('target', '')
if target and os.path.exists(target):
    try: data = read_jsonc(target)
    except Exception as exc: raise SystemExit(f'Cannot safely remove managed Copilot CLI settings from malformed JSON: {target}. Package assets and state were preserved. {exc}')
    removed = {os.path.normcase(os.path.abspath(item.get('path',''))) for item in settings.get('skillDirectoryEntries', []) if item.get('added', True)}
    data['skillDirectories'] = [item for item in data.get('skillDirectories', []) if os.path.normcase(os.path.abspath(item)) not in removed]
    with open(target, 'w', encoding='utf-8') as stream: json.dump(data, stream, indent=2); stream.write('\n')
mcp = cli.get('mcp', {})
target = mcp.get('target', '')
if target and os.path.exists(target):
    try: data = read_jsonc(target)
    except Exception as exc: raise SystemExit(f'Cannot safely remove managed Copilot CLI MCP entries from malformed JSON: {target}. Package assets and state were preserved. {exc}')
    servers = data.get('mcpServers', {})
    for item in mcp.get('serverIds', []): servers.pop(item, None)
    with open(target, 'w', encoding='utf-8') as stream: json.dump(data, stream, indent=2); stream.write('\n')
PY
  fi
fi

for record in "${MANAGED[@]}"; do
  kind="${record%%$'\t'*}"
  target="${record#*$'\t'}"
  [[ "$kind" == "settings" || "$kind" == "mcp" || "$kind" == "cli-settings" || "$kind" == "cli-mcp" ]] && continue
  [[ "$kind" == "vault" && "$REMOVE_VAULT" != true ]] && continue
  [[ -z "$target" || ! -e "$target" ]] && continue
  assert_no_symlink_path "$target"
  run rm -rf "$target"
done

if [[ "$REMOVE_VAULT" == true && -n "$STATE_VAULT" && -d "$STATE_VAULT" ]]; then
  assert_no_symlink_path "$STATE_VAULT"
  run rm -rf "$STATE_VAULT"
fi

if [[ "$RESTORE_BACKUPS" == true ]]; then
  mapfile -t BACKUPS < <(python3 - "$RUNTIME_DIR/backups.json" <<'PY'
import json, sys
for item in reversed(json.load(open(sys.argv[1]))):
    print(item.get('target','') + '\t' + item.get('backup',''))
PY
)
  for record in "${BACKUPS[@]}"; do
    target="${record%%$'\t'*}"
    backup="${record#*$'\t'}"
    [[ -e "$backup" ]] || { echo "Backup missing: $backup" >&2; continue; }
    assert_no_symlink_path "$target"
    assert_no_symlink_path "$backup"
    if [[ -e "$target" ]]; then run rm -rf "$target"; fi
    run mkdir -p "$(dirname "$target")"
    run cp -a "$backup" "$target"
  done
else
  echo 'Existing VS Code and Copilot CLI settings and unrelated MCP entries were preserved. Package-owned entries were removed.'
fi

if [[ "$REMOVE_EXTENSIONS" == true ]]; then
  if command -v "$CODE_COMMAND" >/dev/null; then
    python3 - "$RUNTIME_DIR/extensions.json" <<'PY' | while IFS= read -r extension; do
import json, sys
for extension in json.load(open(sys.argv[1])): print(extension)
PY
      run "$CODE_COMMAND" --uninstall-extension "$extension"
    done
  else
    echo "VS Code command '$CODE_COMMAND' not found; extension uninstall skipped." >&2
  fi
fi

if [[ "$DRY_RUN" != true ]]; then
  assert_no_symlink_path "$STATE_PATH"
  rm -f "$STATE_PATH"
  rm -f "${STATE_PATH}.sha256"
fi
echo 'Uninstall completed.'
