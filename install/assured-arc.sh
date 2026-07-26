#!/usr/bin/env bash
# Install Assured Arc on macOS or Linux.
# Requires Bash, Python 3, and the VS Code `code` command when extensions are enabled.
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE_ROOT="${HOME}/.assured-arc"
VAULT_PATH=""
VSCODE_USER_DIR=""
COPILOT_ROOT=""
COPILOT_CLI_ROOT=""
CONFIG_PATH="${REPO_ROOT}/config/assured-arc.example.json"
CODE_COMMAND="code"
COPILOT_CLI_COMMAND="copilot"
DRY_RUN=false
INSTALL_COPILOT_CLI=false
SKIP_EXTENSIONS=false
SKIP_VAULT=false
INSTALL_MCP=true
FORCE_SETTINGS=false
NO_BACKUP=false
PROFILE_ROOT_SET=false
VAULT_PATH_SET=false
SKIP_EXTENSIONS_SET=false
SKIP_VAULT_SET=false
INSTALL_MCP_SET=false
INSTALL_COPILOT_CLI_SET=false
FORCE_SETTINGS_SET=false

usage() {
  cat <<'EOF'
Usage: install/assured-arc.sh [options]

  --profile-root PATH    Managed package state directory
  --vault-path PATH      Destination for the optional vault template
  --vscode-user-dir PATH Isolated VS Code User directory, useful for testing
  --copilot-root PATH    Isolated Copilot profile directory, useful for testing
  --copilot-cli-root PATH Isolated GitHub Copilot CLI home, useful for testing
  --config PATH          Assured Arc JSON configuration
  --code-command PATH    VS Code command, default: code
  --copilot-cli-command PATH GitHub Copilot CLI command, default: copilot
  --dry-run              Print actions without modifying files
  --install-copilot-cli  Install agents, instructions, hooks, and MCP for Copilot CLI
  --skip-extensions      Do not install VS Code extensions
  --skip-vault           Do not create the vault template
  --skip-mcp             Do not install the reviewed Context7, Sequential Thinking, and arXiv MCP profile
  --install-mcp          Compatibility alias; MCP installation is already enabled by default
  --force-settings       Replace conflicting template settings
  --no-backup            Do not back up changed files
  --help                 Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile-root) PROFILE_ROOT="$2"; PROFILE_ROOT_SET=true; shift 2 ;;
    --vault-path) VAULT_PATH="$2"; VAULT_PATH_SET=true; shift 2 ;;
    --vscode-user-dir) VSCODE_USER_DIR="$2"; shift 2 ;;
    --copilot-root) COPILOT_ROOT="$2"; shift 2 ;;
    --copilot-cli-root) COPILOT_CLI_ROOT="$2"; shift 2 ;;
    --config) CONFIG_PATH="$2"; shift 2 ;;
    --code-command) CODE_COMMAND="$2"; shift 2 ;;
    --copilot-cli-command) COPILOT_CLI_COMMAND="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --install-copilot-cli) INSTALL_COPILOT_CLI=true; INSTALL_COPILOT_CLI_SET=true; shift ;;
    --skip-extensions) SKIP_EXTENSIONS=true; SKIP_EXTENSIONS_SET=true; shift ;;
    --skip-vault) SKIP_VAULT=true; SKIP_VAULT_SET=true; shift ;;
    --skip-mcp) INSTALL_MCP=false; INSTALL_MCP_SET=true; shift ;;
    --install-mcp) INSTALL_MCP=true; INSTALL_MCP_SET=true; shift ;;
    --force-settings) FORCE_SETTINGS=true; FORCE_SETTINGS_SET=true; shift ;;
    --no-backup) NO_BACKUP=true; shift ;;
    --help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -f "$CONFIG_PATH" ]] || { echo "Configuration not found: $CONFIG_PATH" >&2; exit 1; }
command -v python3 >/dev/null || { echo 'Python 3 is required for safe JSON merging.' >&2; exit 1; }
mapfile -t CONFIG_VALUES < <(python3 - "$CONFIG_PATH" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding='utf-8'))
keys = ('profileRoot', 'vaultPath', 'installCopilotCli', 'installExtensions', 'installMcp', 'installVault', 'forceSettings')
def value(key):
  item = data.get(key, '')
  return str(item).lower() if isinstance(item, bool) else str(item or '')
for key in keys: print(value(key))
PY
)
CONFIG_PROFILE="${CONFIG_VALUES[0]:-}"
CONFIG_VAULT="${CONFIG_VALUES[1]:-}"
CONFIG_COPILOT_CLI="${CONFIG_VALUES[2]:-}"
CONFIG_EXTENSIONS="${CONFIG_VALUES[3]:-}"
CONFIG_MCP="${CONFIG_VALUES[4]:-}"
CONFIG_VAULT_ENABLED="${CONFIG_VALUES[5]:-}"
CONFIG_FORCE="${CONFIG_VALUES[6]:-}"
if [[ "$PROFILE_ROOT_SET" != true && -n "$CONFIG_PROFILE" ]]; then PROFILE_ROOT="$CONFIG_PROFILE"; fi
if [[ "$VAULT_PATH_SET" != true && -n "$CONFIG_VAULT" ]]; then VAULT_PATH="$CONFIG_VAULT"; fi
if [[ "$INSTALL_COPILOT_CLI_SET" != true && "$CONFIG_COPILOT_CLI" == true ]]; then INSTALL_COPILOT_CLI=true; fi
if [[ "$SKIP_EXTENSIONS_SET" != true && "$CONFIG_EXTENSIONS" == false ]]; then SKIP_EXTENSIONS=true; fi
if [[ "$INSTALL_MCP_SET" != true && "$CONFIG_MCP" == false ]]; then INSTALL_MCP=false; fi
if [[ "$SKIP_VAULT_SET" != true && "$CONFIG_VAULT_ENABLED" == false ]]; then SKIP_VAULT=true; fi
if [[ "$FORCE_SETTINGS_SET" != true && "$CONFIG_FORCE" == true ]]; then FORCE_SETTINGS=true; fi

run() {
  if [[ "$DRY_RUN" == true ]]; then
    printf '[dry run]'; printf ' %q' "$@"; printf '\n'
  else
    "$@"
  fi
}

step=0
total=10
progress() {
  step=$((step + 1))
  printf '[%d/%d] %s\n' "$step" "$total" "$1"
}

if [[ -z "$VSCODE_USER_DIR" ]]; then
  if [[ "$(uname -s)" == "Darwin" ]]; then
    VSCODE_USER_DIR="${HOME}/Library/Application Support/Code/User"
  else
    VSCODE_USER_DIR="${HOME}/.config/Code/User"
  fi
fi
if [[ -z "$VAULT_PATH" ]]; then VAULT_PATH="${PROFILE_ROOT}/vault"; fi
absolute_path() {
  python3 - "$1" <<'PY'
import os, sys
print(os.path.abspath(os.path.expanduser(sys.argv[1])))
PY
}
PROFILE_ROOT="$(absolute_path "$PROFILE_ROOT")"
VSCODE_USER_DIR="$(absolute_path "$VSCODE_USER_DIR")"
if [[ -z "$COPILOT_ROOT" ]]; then COPILOT_ROOT="${PROFILE_ROOT}/copilot"; fi
COPILOT_ROOT="$(absolute_path "$COPILOT_ROOT")"
if [[ -z "$COPILOT_CLI_ROOT" ]]; then COPILOT_CLI_ROOT="${COPILOT_HOME:-${HOME}/.copilot}"; fi
COPILOT_CLI_ROOT="$(absolute_path "$COPILOT_CLI_ROOT")"
VAULT_PATH="$(absolute_path "$VAULT_PATH")"
STATE_PATH="${PROFILE_ROOT}/state.json"
BACKUP_ROOT="${PROFILE_ROOT}/backups/$(date +%Y%m%d-%H%M%S)-$$"
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

preflight_install_plan() {
  local source relative
  assert_no_symlink_path "$PROFILE_ROOT"
  assert_no_symlink_path "$STATE_PATH"
  assert_no_symlink_path "$BACKUP_ROOT"
  assert_no_symlink_path "$VSCODE_USER_DIR"
  assert_no_symlink_path "${VSCODE_USER_DIR}/settings.json"
  assert_no_symlink_path "${VSCODE_USER_DIR}/mcp.json"
  assert_no_symlink_path "$COPILOT_ROOT"
  assert_no_symlink_path "${COPILOT_ROOT}/skill-registry.json"
  assert_no_symlink_path "${COPILOT_ROOT}/agent-harness.json"
  assert_no_symlink_path "${COPILOT_ROOT}/tool-policy.json"
  assert_no_symlink_path "${COPILOT_ROOT}/hooks/agent-harness.json"
  assert_no_symlink_path "${COPILOT_ROOT}/hooks/harness-event.ps1"
  assert_no_symlink_path "${COPILOT_ROOT}/hooks/harness_event.py"
  for source in "${REPO_ROOT}"/.github/skills/*; do
    [[ -d "$source" ]] || continue
    assert_no_symlink_path "${COPILOT_ROOT}/skills/$(basename "$source")"
  done
  while IFS= read -r instruction; do
    [[ -n "$instruction" ]] || continue
    assert_no_symlink_path "${COPILOT_ROOT}/instructions/${instruction}"
  done < <(python3 - "${REPO_ROOT}/config/instructions.json" <<'PY'
import json, sys
for item in json.load(open(sys.argv[1], encoding='utf-8'))['instructions']: print(item)
PY
)
  for source in "${REPO_ROOT}"/.github/agents/*.agent.md; do
    [[ -f "$source" ]] || continue
    assert_no_symlink_path "${COPILOT_ROOT}/agents/$(basename "$source")"
  done
  for source in "${REPO_ROOT}"/.github/prompts/*.prompt.md; do
    [[ -f "$source" ]] || continue
    assert_no_symlink_path "${COPILOT_ROOT}/prompts/$(basename "$source")"
  done
  if [[ "$INSTALL_COPILOT_CLI" == true ]]; then
    assert_no_symlink_path "$COPILOT_CLI_ROOT"
    assert_no_symlink_path "${COPILOT_CLI_ROOT}/settings.json"
    assert_no_symlink_path "${COPILOT_CLI_ROOT}/mcp-config.json"
    assert_no_symlink_path "${COPILOT_CLI_ROOT}/hooks/assured-arc.json"
    while IFS= read -r instruction; do
      [[ -n "$instruction" ]] || continue
      assert_no_symlink_path "${COPILOT_CLI_ROOT}/instructions/${instruction}"
    done < <(python3 - "${REPO_ROOT}/config/instructions.json" <<'PY'
import json, sys
for item in json.load(open(sys.argv[1], encoding='utf-8'))['instructions']: print(item)
PY
)
    for source in "${REPO_ROOT}"/.github/agents/*.agent.md; do
      [[ -f "$source" ]] || continue
      assert_no_symlink_path "${COPILOT_CLI_ROOT}/agents/$(basename "$source")"
    done
  fi
  if [[ "$INSTALL_MCP" == true ]]; then
    local arxiv_version
    arxiv_version="$(python3 - "${REPO_ROOT}/config/mcp-servers.json" <<'PY'
import json, sys
print(next(item['version'] for item in json.load(open(sys.argv[1], encoding='utf-8'))['servers'] if item['id'] == 'arxiv'))
PY
)"
    assert_no_symlink_path "${PROFILE_ROOT}/mcp/arxiv-${arxiv_version}"
  else
    assert_no_symlink_path "${PROFILE_ROOT}/mcp/mcp.json.example"
  fi
  if [[ "$SKIP_VAULT" != true ]]; then
    assert_no_symlink_path "$VAULT_PATH"
    while IFS= read -r -d '' source; do
      relative="${source#${REPO_ROOT}/vault-template/}"
      assert_no_symlink_path "${VAULT_PATH}/${relative}"
    done < <(find "${REPO_ROOT}/vault-template" -type f -print0)
    assert_no_symlink_path "${VAULT_PATH}/assured-arc.code-workspace"
  fi
}
RUNTIME_STATE_DIR="$(mktemp -d)"
trap 'rm -rf "$RUNTIME_STATE_DIR"' EXIT
MANAGED_FILE="${RUNTIME_STATE_DIR}/managed.tsv"
BACKUP_FILE="${RUNTIME_STATE_DIR}/backups.tsv"
CREATED_FILE="${RUNTIME_STATE_DIR}/created.txt"
EXTENSIONS_FILE="${RUNTIME_STATE_DIR}/extensions.txt"
MCP_SERVERS_FILE="${RUNTIME_STATE_DIR}/mcp-servers.txt"
MCP_INPUTS_FILE="${RUNTIME_STATE_DIR}/mcp-inputs.txt"
SETTINGS_LOCATIONS_FILE="${RUNTIME_STATE_DIR}/settings-locations.tsv"
SETTINGS_TEMPLATE="${RUNTIME_STATE_DIR}/user-settings.json"
CLI_MCP_SERVERS_FILE="${RUNTIME_STATE_DIR}/cli-mcp-servers.txt"
CLI_SKILL_DIRECTORIES_FILE="${RUNTIME_STATE_DIR}/cli-skill-directories.tsv"
PREVIOUS_TARGETS_FILE="${RUNTIME_STATE_DIR}/previous-targets.txt"
PREVIOUS_MCP_TARGET=""
PREVIOUS_CLI_MCP_TARGET=""
: > "$MANAGED_FILE"
: > "$BACKUP_FILE"
: > "$CREATED_FILE"
: > "$EXTENSIONS_FILE"
: > "$MCP_SERVERS_FILE"
: > "$MCP_INPUTS_FILE"
: > "$SETTINGS_LOCATIONS_FILE"
: > "$CLI_MCP_SERVERS_FILE"
: > "$CLI_SKILL_DIRECTORIES_FILE"
if [[ -f "$STATE_PATH" ]]; then
  python3 - "$STATE_PATH" "$MCP_SERVERS_FILE" "$MCP_INPUTS_FILE" "$CLI_MCP_SERVERS_FILE" "$CLI_SKILL_DIRECTORIES_FILE" "$PROFILE_ROOT" "$COPILOT_ROOT" "$VSCODE_USER_DIR" "$VAULT_PATH" "$COPILOT_CLI_ROOT" > "$PREVIOUS_TARGETS_FILE" <<'PY'
import hashlib, json, os, sys
state, servers, inputs, cli_servers, cli_skills, profile, copilot, vscode_user, vault, cli_root = sys.argv[1:]
data = json.load(open(state, encoding='utf-8'))
if data.get('schema', 0) >= 3:
    hash_path = state + '.sha256'
    if not os.path.isfile(hash_path): raise SystemExit(f'Assured Arc state integrity file not found: {hash_path}')
    expected = open(hash_path, encoding='ascii').read().strip().lower()
    actual = hashlib.sha256(open(state, 'rb').read()).hexdigest()
    if expected != actual: raise SystemExit('Assured Arc state integrity validation failed. No prior ownership was imported.')
for name, requested in (('profileRoot', profile), ('copilotRoot', copilot), ('vscodeUserDirectory', vscode_user), ('vaultPath', vault)):
    saved = data.get(name)
    if saved and os.path.realpath(saved) != os.path.realpath(requested):
        raise SystemExit(f'This profile cannot migrate {name}. Uninstall the existing profile first.')
mcp = data.get('mcp', {})
open(servers, 'w', encoding='utf-8').write(''.join(f'{item}\n' for item in mcp.get('serverIds', [])))
open(inputs, 'w', encoding='utf-8').write(''.join(f'{item}\n' for item in mcp.get('inputIds', [])))
cli = data.get('copilotCli', {})
if cli.get('enabled') and cli.get('root') and os.path.realpath(cli['root']) != os.path.realpath(cli_root):
    raise SystemExit('This profile cannot migrate the Copilot CLI root. Uninstall the existing profile first.')
open(cli_servers, 'w', encoding='utf-8').write(''.join(f'{item}\n' for item in cli.get('mcp', {}).get('serverIds', [])))
open(cli_skills, 'w', encoding='utf-8').write(''.join(f"{item.get('path','')}\t{str(item.get('added', True)).lower()}\n" for item in cli.get('settings', {}).get('skillDirectoryEntries', [])))
print(mcp.get('target', ''))
print(cli.get('mcp', {}).get('target', ''))
print(str(cli.get('enabled', False)).lower())
PY
  mapfile -t PREVIOUS_TARGETS < "$PREVIOUS_TARGETS_FILE"
  PREVIOUS_MCP_TARGET="${PREVIOUS_TARGETS[0]:-}"
  PREVIOUS_CLI_MCP_TARGET="${PREVIOUS_TARGETS[1]:-}"
  if [[ "${PREVIOUS_TARGETS[2]:-false}" == true ]]; then INSTALL_COPILOT_CLI=true; fi
fi
mkdir_if_needed() { assert_no_symlink_path "$1"; [[ -d "$1" ]] || run mkdir -p "$1"; }
record_created() { printf '%s\n' "$1" >> "$CREATED_FILE"; }

progress 'Resolve configuration'

progress 'Validate prerequisites'
if [[ "$SKIP_EXTENSIONS" != true ]] && ! command -v "$CODE_COMMAND" >/dev/null; then
  echo "VS Code command '$CODE_COMMAND' not found. Install VS Code and enable the code command, or use --skip-extensions." >&2
  exit 1
fi
if [[ "$INSTALL_MCP" == true ]]; then
  for command in node npx uv; do
    command -v "$command" >/dev/null || { echo "$command is required for the reviewed MCP profile. Install it or use --skip-mcp." >&2; exit 1; }
  done
  NODE_MAJOR="$(node --version | sed 's/^v//' | cut -d. -f1)"
  [[ "$NODE_MAJOR" -ge 18 ]] || { echo 'Sequential Thinking MCP requires Node.js 18 or newer.' >&2; exit 1; }
fi
if [[ "$INSTALL_COPILOT_CLI" == true ]] && ! command -v "$COPILOT_CLI_COMMAND" >/dev/null; then
  echo "GitHub Copilot CLI command '$COPILOT_CLI_COMMAND' not found. Install Copilot CLI or omit --install-copilot-cli." >&2
  exit 1
fi

preflight_install_plan

progress 'Create profile and backup location'
if [[ ! -e "$PROFILE_ROOT" ]]; then record_created "$PROFILE_ROOT"; fi
mkdir_if_needed "$PROFILE_ROOT"
if [[ "$NO_BACKUP" != true ]]; then mkdir_if_needed "$BACKUP_ROOT"; fi

backup_item() {
  local target="$1"
  assert_no_symlink_path "$target"
  [[ ! -e "$target" ]] && return
  [[ "$NO_BACKUP" == true ]] && return
  local safe backup
  safe="$(printf '%s' "$target" | tr '/:' '__')"
  backup="${BACKUP_ROOT}/${safe}"
  run mkdir -p "$(dirname "$backup")"
  run cp -a "$target" "$backup"
  printf '%s\t%s\n' "$target" "$backup" >> "$BACKUP_FILE"
}

copy_managed_dir() {
  local source="$1" target="$2" kind="$3"
  [[ -d "$source" ]] || { echo "Package source missing: $source" >&2; exit 1; }
  assert_no_symlink_path "$target"
  if [[ ! -e "$target" ]]; then record_created "$target"; fi
  backup_item "$target"
  run mkdir -p "$(dirname "$target")"
  if [[ "$DRY_RUN" != true ]]; then rm -rf "$target"; cp -a "$source" "$target"; fi
  printf '%s\t%s\n' "$kind" "$target" >> "$MANAGED_FILE"
}

copy_managed_file() {
  local source="$1" target="$2" kind="$3"
  assert_no_symlink_path "$target"
  if [[ ! -e "$target" ]]; then record_created "$target"; fi
  backup_item "$target"
  run mkdir -p "$(dirname "$target")"
  run cp "$source" "$target"
  printf '%s\t%s\n' "$kind" "$target" >> "$MANAGED_FILE"
}

render_settings_template() {
  local agent_root="${COPILOT_ROOT}/agents"
  if [[ "$INSTALL_COPILOT_CLI" == true ]]; then agent_root="${COPILOT_CLI_ROOT}/agents"; fi
  python3 - "${REPO_ROOT}/config/user-settings.json" "$SETTINGS_TEMPLATE" "$COPILOT_ROOT" "$agent_root" "$SETTINGS_LOCATIONS_FILE" <<'PY'
import json, os, sys
source, target, root, agent_root, locations_file = sys.argv[1:]
data = json.load(open(source, encoding='utf-8'))
locations = {
    'chat.agentFilesLocations': agent_root,
    'chat.promptFilesLocations': os.path.join(root, 'prompts'),
    'chat.agentSkillsLocations': os.path.join(root, 'skills'),
    'chat.instructionsFilesLocations': os.path.join(root, 'instructions'),
    'chat.hookFilesLocations': os.path.join(root, 'hooks', 'agent-harness.json'),
}
home = os.path.abspath(os.path.expanduser('~'))
with open(locations_file, 'w', encoding='utf-8') as locations_stream:
    for setting, path in locations.items():
        absolute = os.path.abspath(path)
        try:
            under_home = os.path.commonpath((home, absolute)) == home
        except ValueError:
            under_home = False
        normalized = ('~/' + os.path.relpath(absolute, home).replace('\\', '/')) if under_home else absolute.replace('\\', '/')
        data.setdefault(setting, {})[normalized] = True
        locations_stream.write(f'{setting}\t{normalized}\n')
with open(target, 'w', encoding='utf-8') as stream:
    json.dump(data, stream, indent=2)
    stream.write('\n')
PY
}

install_agent_harness() {
  local harness_template hook_template harness_target hook_target powershell_target python_target trace_directory tool_policy_target
  harness_template="${RUNTIME_STATE_DIR}/agent-harness.json"
  hook_template="${RUNTIME_STATE_DIR}/agent-harness-hooks.json"
  harness_target="${COPILOT_ROOT}/agent-harness.json"
  tool_policy_target="${COPILOT_ROOT}/tool-policy.json"
  hook_target="${COPILOT_ROOT}/hooks/agent-harness.json"
  powershell_target="${COPILOT_ROOT}/hooks/harness-event.ps1"
  python_target="${COPILOT_ROOT}/hooks/harness_event.py"
  trace_directory="${PROFILE_ROOT}/harness-runs"

  python3 - "${REPO_ROOT}/config/agent-harness.json" "$harness_template" "$COPILOT_ROOT" "$tool_policy_target" "$COPILOT_CLI_ROOT" "$INSTALL_COPILOT_CLI" <<'PY'
import json, os, sys
source, target, root, tool_policy, cli_root, install_cli = sys.argv[1:]
data = json.load(open(source, encoding='utf-8'))
registry = os.path.abspath(os.path.join(root, 'skill-registry.json')).replace('\\', '/')
skills = os.path.abspath(os.path.join(root, 'skills')).replace('\\', '/')
data['skillRouting']['catalogs'] = ['~/.copilot/skill-registry.json', registry]
data['skillRouting']['fallbackLocations'] = ['~/.copilot/skills', skills, '.github/skills', '.claude/skills']
data['protectedRoots'] = [os.path.abspath(root).replace('\\', '/'), os.path.abspath(os.path.dirname(root)).replace('\\', '/')]
if install_cli.lower() == 'true': data['protectedRoots'].append(os.path.abspath(cli_root).replace('\\', '/'))
data['toolPolicy']['path'] = os.path.abspath(tool_policy).replace('\\', '/')
with open(target, 'w', encoding='utf-8') as stream:
    json.dump(data, stream, indent=2)
    stream.write('\n')
PY
  copy_managed_file "$harness_template" "$harness_target" agent-harness
  copy_managed_file "${REPO_ROOT}/config/tool-policy.json" "$tool_policy_target" tool-policy
  copy_managed_file "${REPO_ROOT}/hooks/harness-event.ps1" "$powershell_target" hook-script
  copy_managed_file "${REPO_ROOT}/hooks/harness_event.py" "$python_target" hook-script
  if [[ "$DRY_RUN" != true ]]; then chmod 700 "$python_target"; fi

  python3 - "${REPO_ROOT}/.github/hooks/agent-harness.json.example" "$hook_template" "$harness_target" "$trace_directory" "$powershell_target" "$python_target" "$tool_policy_target" <<'PY'
import json, sys
source, target, harness, traces, powershell, python, tool_policy = sys.argv[1:]
data = json.load(open(source, encoding='utf-8'))
for event_name, hooks in data['hooks'].items():
    for hook in hooks:
        hook['command'] = f'python3 "{python}"'
        hook['windows'] = f'pwsh -NoProfile -ExecutionPolicy Bypass -File "{powershell}"'
        hook['linux'] = f'python3 "{python}"'
        hook['osx'] = f'python3 "{python}"'
        hook['env']['ASSURED_ARC_HARNESS_CONFIG'] = harness
        hook['env']['ASSURED_ARC_HARNESS_TRACE_DIR'] = traces
        hook['env']['ASSURED_ARC_HARNESS_TOOL_POLICY'] = tool_policy
with open(target, 'w', encoding='utf-8') as stream:
    json.dump(data, stream, indent=2)
    stream.write('\n')
PY
  copy_managed_file "$hook_template" "$hook_target" hook-config
}

copy_cli_managed_file() {
  local source="$1" target="$2" kind="$3"
  local owned=false
  if [[ -f "$STATE_PATH" ]]; then
    owned="$(python3 - "$STATE_PATH" "$target" "$kind" <<'PY'
import json, os, sys
state, target, kind = sys.argv[1:]
data = json.load(open(state, encoding='utf-8'))
print(str(any(item.get('kind') == kind and os.path.normcase(os.path.abspath(item.get('target',''))) == os.path.normcase(os.path.abspath(target)) for item in data.get('managed', []))).lower())
PY
)"
  fi
  if [[ -e "$target" && "$owned" != true && "$FORCE_SETTINGS" != true ]]; then
    echo "Copilot CLI file conflicts with an existing unmanaged file: $target. Rerun with --force-settings only after reviewing its contents." >&2
    return 1
  fi
  copy_managed_file "$source" "$target" "$kind"
}

install_copilot_cli_profile() {
  local settings_target skills_directory instruction source target hook_template hook_target
  settings_target="${COPILOT_CLI_ROOT}/settings.json"
  skills_directory="${COPILOT_ROOT}/skills"
  assert_no_symlink_path "$settings_target"
  if [[ ! -e "$settings_target" ]]; then record_created "$settings_target"; fi
  backup_item "$settings_target"
  if [[ "$DRY_RUN" == true ]]; then
    echo "[dry run] register managed skills in Copilot CLI settings at $settings_target"
  else
    mkdir -p "$(dirname "$settings_target")"
    python3 - "$settings_target" "$skills_directory" "$CLI_SKILL_DIRECTORIES_FILE" <<'PY'
import json, os, sys
target, skills, entries = sys.argv[1:]
data = json.load(open(target, encoding='utf-8-sig')) if os.path.exists(target) and open(target, encoding='utf-8-sig').read().strip() else {}
directories = list(data.get('skillDirectories', []))
skills = os.path.abspath(skills)
present = any(os.path.normcase(os.path.abspath(item)) == os.path.normcase(skills) for item in directories)
if not present: directories.append(skills)
data['skillDirectories'] = directories
with open(entries, 'w', encoding='utf-8') as stream: stream.write(f'{skills}\t{str(not present).lower()}\n')
with open(target, 'w', encoding='utf-8') as stream: json.dump(data, stream, indent=2); stream.write('\n')
PY
  fi
  printf 'cli-settings\t%s\n' "$settings_target" >> "$MANAGED_FILE"

  while IFS= read -r instruction; do
    [[ -n "$instruction" ]] || continue
    source="${REPO_ROOT}/.github/instructions/${instruction}"
    target="${COPILOT_CLI_ROOT}/instructions/${instruction}"
    copy_cli_managed_file "$source" "$target" cli-instruction
  done < <(python3 - "${REPO_ROOT}/config/instructions.json" <<'PY'
import json, sys
for item in json.load(open(sys.argv[1], encoding='utf-8'))['instructions']: print(item)
PY
)
  for source in "${REPO_ROOT}"/.github/agents/*.agent.md; do
    [[ -f "$source" ]] || continue
    copy_cli_managed_file "$source" "${COPILOT_CLI_ROOT}/agents/$(basename "$source")" cli-agent
  done

  hook_template="${RUNTIME_STATE_DIR}/copilot-cli-hooks.json"
  hook_target="${COPILOT_CLI_ROOT}/hooks/assured-arc.json"
  python3 - "${REPO_ROOT}/.github/hooks/copilot-cli-harness.json.example" "$hook_template" "${COPILOT_ROOT}/agent-harness.json" "${PROFILE_ROOT}/harness-runs" "${COPILOT_ROOT}/hooks/harness-event.ps1" "${COPILOT_ROOT}/hooks/harness_event.py" "${COPILOT_ROOT}/tool-policy.json" <<'PY'
import json, sys
source, target, harness, traces, powershell, python, tool_policy = sys.argv[1:]
data = json.load(open(source, encoding='utf-8'))
for event_name, hooks in data['hooks'].items():
    for hook in hooks:
        hook['bash'] = f'python3 "{python}"'
        hook['powershell'] = f'pwsh -NoProfile -ExecutionPolicy Bypass -File "{powershell}"'
        hook['env'].update({
            'ASSURED_ARC_HARNESS_CONFIG': harness,
            'ASSURED_ARC_HARNESS_TRACE_DIR': traces,
            'ASSURED_ARC_HARNESS_TOOL_POLICY': tool_policy,
            'ASSURED_ARC_HARNESS_HOST': 'copilot-cli',
            'ASSURED_ARC_HARNESS_EVENT': event_name,
        })
with open(target, 'w', encoding='utf-8') as stream: json.dump(data, stream, indent=2); stream.write('\n')
PY
  copy_cli_managed_file "$hook_template" "$hook_target" cli-hook-config
}

merge_json_defaults() {
  local target="$1" template="$2" force="$3" arxiv_entry="${4:-}"
  assert_no_symlink_path "$target"
  if [[ ! -e "$target" ]]; then record_created "$target"; fi
  backup_item "$target"
  if [[ "$DRY_RUN" == true ]]; then echo "[dry run] merge JSON $template -> $target"; return; fi
  mkdir -p "$(dirname "$target")"
  python3 - "$target" "$template" "$force" "$arxiv_entry" "$MCP_SERVERS_FILE" "$MCP_INPUTS_FILE" "$PREVIOUS_MCP_TARGET" <<'PY'
import json, os, re, sys
path, template, force, arxiv_entry, server_file, input_file, previous_target = sys.argv[1:]
force = force.lower() == 'true'
def read(path):
    if not os.path.exists(path): return {}
    text = open(path, encoding='utf-8').read()
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    text = re.sub(r'^\s*//.*$', '', text, flags=re.M)
    text = re.sub(r',\s*([}\]])', r'\1', text)
    return json.loads(text) if text.strip() else {}
def merge(existing, defaults):
    for key, value in defaults.items():
        if key not in existing:
            existing[key] = value
        elif isinstance(existing[key], dict) and isinstance(value, dict):
            merge(existing[key], value)
        elif force:
            existing[key] = value
merge_data = read(path)
defaults = read(template)
if arxiv_entry:
    if previous_target and not os.path.isabs(previous_target):
        raise SystemExit('The saved MCP ownership target is relative and cannot be trusted. Restore or remove this profile before reinstalling.')
    if previous_target and os.path.normcase(os.path.abspath(previous_target)) != os.path.normcase(os.path.abspath(path)):
        raise SystemExit(f'This profile owns MCP entries in {previous_target} and cannot migrate them to {path}. Uninstall the existing profile first.')
    defaults['servers']['arxiv']['command'] = arxiv_entry
    owned_servers = set(line.strip() for line in open(server_file, encoding='utf-8') if line.strip())
    owned_inputs = set(line.strip() for line in open(input_file, encoding='utf-8') if line.strip())
    existing_servers = merge_data.setdefault('servers', {})
    existing_inputs = list(merge_data.get('inputs', []))
    existing_input_ids = {item.get('id') for item in existing_inputs}
    conflicts = [f'server:{key}' for key in defaults['servers'] if key in existing_servers and key not in owned_servers and not force]
    conflicts += [f"input:{item['id']}" for item in defaults.get('inputs', []) if item['id'] in existing_input_ids and item['id'] not in owned_inputs and not force]
    if conflicts:
        raise SystemExit('MCP configuration conflicts with existing IDs: ' + ', '.join(conflicts) + '. Rerun with --force-settings only after reviewing replacements.')
    for key, value in defaults['servers'].items():
        existing_servers[key] = value
        owned_servers.add(key)
    for item in defaults.get('inputs', []):
        existing_inputs = [current for current in existing_inputs if current.get('id') != item['id']]
        existing_inputs.append(item)
        owned_inputs.add(item['id'])
    merge_data['inputs'] = existing_inputs
    open(server_file, 'w', encoding='utf-8').write(''.join(f'{item}\n' for item in sorted(owned_servers)))
    open(input_file, 'w', encoding='utf-8').write(''.join(f'{item}\n' for item in sorted(owned_inputs)))
else:
    merge(merge_data, defaults)
with open(path, 'w', encoding='utf-8') as f: json.dump(merge_data, f, indent=2); f.write('\n')
PY
}

merge_copilot_cli_mcp() {
  local target="${COPILOT_CLI_ROOT}/mcp-config.json" template="${REPO_ROOT}/mcp/copilot-cli.mcp.json.example"
  assert_no_symlink_path "$target"
  if [[ ! -e "$target" ]]; then record_created "$target"; fi
  backup_item "$target"
  if [[ "$DRY_RUN" == true ]]; then echo "[dry run] merge Copilot CLI MCP $template -> $target"; return; fi
  mkdir -p "$(dirname "$target")"
  python3 - "$target" "$template" "$FORCE_SETTINGS" "$ARXIV_ENTRY" "$CLI_MCP_SERVERS_FILE" "$PREVIOUS_CLI_MCP_TARGET" <<'PY'
import json, os, re, sys
path, template, force, arxiv_entry, server_file, previous_target = sys.argv[1:]
force = force.lower() == 'true'
def read(path):
    if not os.path.exists(path): return {}
    text = open(path, encoding='utf-8-sig').read()
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    text = re.sub(r'^\s*//.*$', '', text, flags=re.M)
    text = re.sub(r',\s*([}\]])', r'\1', text)
    return json.loads(text) if text.strip() else {}
if previous_target and not os.path.isabs(previous_target):
    raise SystemExit('The saved Copilot CLI MCP ownership target is relative and cannot be trusted.')
if previous_target and os.path.normcase(os.path.abspath(previous_target)) != os.path.normcase(os.path.abspath(path)):
    raise SystemExit(f'This profile owns Copilot CLI MCP entries in {previous_target} and cannot migrate them to {path}. Uninstall the existing profile first.')
data = read(path)
defaults = read(template)
defaults['mcpServers']['arxiv']['command'] = arxiv_entry
owned = set(line.strip() for line in open(server_file, encoding='utf-8') if line.strip())
servers = data.setdefault('mcpServers', {})
conflicts = [f'server:{key}' for key in defaults['mcpServers'] if key in servers and key not in owned and not force]
if conflicts: raise SystemExit('Copilot CLI MCP configuration conflicts with existing IDs: ' + ', '.join(conflicts) + '. Rerun with --force-settings only after reviewing replacements.')
for key, value in defaults['mcpServers'].items():
    servers[key] = value
    owned.add(key)
open(server_file, 'w', encoding='utf-8').write(''.join(f'{item}\n' for item in sorted(owned)))
with open(path, 'w', encoding='utf-8') as stream: json.dump(data, stream, indent=2); stream.write('\n')
PY
  printf 'cli-mcp\t%s\n' "$target" >> "$MANAGED_FILE"
}

install_arxiv_mcp() {
  local version target tool_dir bin_dir entry marker
  version="$(python3 - "${REPO_ROOT}/config/mcp-servers.json" <<'PY'
import json, sys
servers = json.load(open(sys.argv[1], encoding='utf-8'))['servers']
print(next(item['version'] for item in servers if item['id'] == 'arxiv'))
PY
)"
  target="${PROFILE_ROOT}/mcp/arxiv-${version}"
  tool_dir="${target}/tools"
  bin_dir="${target}/bin"
  entry="${bin_dir}/arxiv-mcp-server"
  marker="${target}/.assured-arc-version"
  if [[ -x "$entry" && -f "$marker" && "$(tr -d '\r\n' < "$marker")" == "$version" ]]; then
    echo "arXiv MCP already installed: $version"
    printf 'mcp-runtime\t%s\n' "$target" >> "$MANAGED_FILE"
    ARXIV_ENTRY="$entry"
    return
  fi
  if [[ ! -e "$target" ]]; then record_created "$target"; else backup_item "$target"; fi
  if [[ "$DRY_RUN" == true ]]; then
    echo "[dry run] install arXiv MCP $version into $target"
  else
    UV_TOOL_DIR="$tool_dir" UV_TOOL_BIN_DIR="$bin_dir" uv tool install --force --quiet "arxiv-mcp-server==$version"
    [[ -x "$entry" ]] || { echo "Unable to install arXiv MCP $version" >&2; return 1; }
    printf '%s\n' "$version" > "$marker"
  fi
  printf 'mcp-runtime\t%s\n' "$target" >> "$MANAGED_FILE"
  ARXIV_ENTRY="$entry"
}

rollback() {
  local status="$1" line="$2"
  trap - ERR
  echo "Assured Arc installation failed at line ${line}. Rolling back package-managed changes." >&2
  if [[ "$DRY_RUN" != true ]]; then
    local remove_profile=false
    while IFS= read -r target; do
      if [[ "$target" == "$PROFILE_ROOT" ]]; then
        remove_profile=true
        continue
      fi
      [[ -n "$target" && -e "$target" ]] && rm -rf "$target" || true
    done < <(python3 - "$CREATED_FILE" <<'PY'
import sys
try:
    values = [line.rstrip('\n') for line in open(sys.argv[1], encoding='utf-8') if line.strip()]
except FileNotFoundError:
    values = []
for value in reversed(values): print(value)
PY
)
    while IFS=$'\t' read -r target backup; do
      [[ -n "$target" && -e "$target" ]] && rm -rf "$target" || true
      if [[ -n "$backup" && -e "$backup" ]]; then
        mkdir -p "$(dirname "$target")"
        cp -a "$backup" "$target"
      fi
    done < <(python3 - "$BACKUP_FILE" <<'PY'
import sys
try:
    values = [line.rstrip('\n') for line in open(sys.argv[1], encoding='utf-8') if line.strip()]
except FileNotFoundError:
    values = []
for value in reversed(values): print(value)
PY
)
    if command -v "$CODE_COMMAND" >/dev/null; then
      while IFS= read -r extension; do
        [[ -n "$extension" ]] || continue
        echo "Removing extension installed during failed Assured Arc installation: $extension" >&2
        "$CODE_COMMAND" --uninstall-extension "$extension" || true
      done < "$EXTENSIONS_FILE"
    fi
    if [[ "$remove_profile" == true && -e "$PROFILE_ROOT" ]]; then rm -rf "$PROFILE_ROOT"; fi
  fi
  exit "$status"
}

trap 'rollback $? $LINENO' ERR

progress 'Configure VS Code settings'
render_settings_template
if [[ "$DRY_RUN" != true ]]; then
  python3 - "${VSCODE_USER_DIR}/settings.json" "$SETTINGS_LOCATIONS_FILE" "$STATE_PATH" "$INSTALL_COPILOT_CLI" <<'PY'
import json, os, re, sys
settings_path, locations_path, state_path, install_cli = sys.argv[1:]
if os.path.exists(settings_path):
  text = open(settings_path, encoding='utf-8').read()
  text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
  text = re.sub(r'^\s*//.*$', '', text, flags=re.M)
  text = re.sub(r',\s*([}\]])', r'\1', text)
  existing = json.loads(text) if text.strip() else {}
else:
  existing = {}
rows = []
for line in open(locations_path, encoding='utf-8'):
  if not line.strip(): continue
  setting, path = line.rstrip('\n').split('\t', 1)
  was_present = isinstance(existing.get(setting), dict) and path in existing[setting]
  rows.append((setting, path, 'false' if was_present else 'true'))
if install_cli.lower() == 'true' and os.path.exists(state_path):
  state = json.load(open(state_path, encoding='utf-8'))
  desired = {path for setting, path, _ in rows if setting == 'chat.agentFilesLocations'}
  for item in state.get('settings', {}).get('locationEntries', []):
    if item.get('setting') == 'chat.agentFilesLocations' and item.get('added', True) and item.get('path') not in desired:
      value = existing.get('chat.agentFilesLocations')
      if isinstance(value, dict): value.pop(item.get('path'), None)
  with open(settings_path, 'w', encoding='utf-8') as stream: json.dump(existing, stream, indent=2); stream.write('\n')
with open(locations_path, 'w', encoding='utf-8') as stream:
  for row in rows: stream.write('\t'.join(row) + '\n')
PY
fi
merge_json_defaults "${VSCODE_USER_DIR}/settings.json" "$SETTINGS_TEMPLATE" "$FORCE_SETTINGS"
printf 'settings\t%s\n' "${VSCODE_USER_DIR}/settings.json" >> "$MANAGED_FILE"

progress 'Install managed agents, skills, and instructions'
for source in "${REPO_ROOT}"/.github/skills/*; do
  [[ -d "$source" ]] || continue
  copy_managed_dir "$source" "${COPILOT_ROOT}/skills/$(basename "$source")" skill
done
copy_managed_file "${REPO_ROOT}/config/skill-registry.json" "${COPILOT_ROOT}/skill-registry.json" skill-registry
while IFS= read -r instruction; do
  [[ -n "$instruction" ]] || continue
  source="${REPO_ROOT}/.github/instructions/${instruction}"
  [[ -f "$source" ]] || { echo "Instruction manifest entry not found: $instruction" >&2; exit 1; }
  copy_managed_file "$source" "${COPILOT_ROOT}/instructions/${instruction}" instruction
done < <(python3 - "${REPO_ROOT}/config/instructions.json" <<'PY'
import json, sys
for item in json.load(open(sys.argv[1], encoding='utf-8'))['instructions']: print(item)
PY
)
for source in "${REPO_ROOT}"/.github/agents/*.agent.md; do
  [[ -f "$source" ]] || continue
  copy_managed_file "$source" "${COPILOT_ROOT}/agents/$(basename "$source")" agent
done
for source in "${REPO_ROOT}"/.github/prompts/*.prompt.md; do
  [[ -f "$source" ]] || continue
  copy_managed_file "$source" "${COPILOT_ROOT}/prompts/$(basename "$source")" prompt
done
install_agent_harness

progress 'Configure GitHub Copilot CLI'
if [[ "$INSTALL_COPILOT_CLI" == true ]]; then
  install_copilot_cli_profile
else
  echo 'Copilot CLI personal-profile installation skipped. Repository agents and skills remain CLI-compatible.'
fi

progress 'Install VS Code extensions'
if [[ "$SKIP_EXTENSIONS" == true ]]; then
  echo 'Extension installation skipped.'
else
  INSTALLED_EXTENSIONS="$("$CODE_COMMAND" --list-extensions)"
  python3 - "${REPO_ROOT}/config/extensions.json" <<'PY' | while IFS=$'\t' read -r extension install; do
import json, sys
for extension in json.load(open(sys.argv[1]))['extensions']:
    print(extension['id'] + '\t' + str(extension.get('install', True)).lower())
PY
    if [[ "$install" == false ]]; then
      echo "Extension capability provided by VS Code: $extension"
      continue
    fi
    if printf '%s\n' "$INSTALLED_EXTENSIONS" | grep -Fxi -q "$extension"; then
      echo "Extension already installed: $extension"
      continue
    fi
    run "$CODE_COMMAND" --install-extension "$extension"
    if [[ "$DRY_RUN" != true ]]; then printf '%s\n' "$extension" >> "$EXTENSIONS_FILE"; fi
  done
fi

progress 'Configure reviewed MCP profile'
if [[ "$INSTALL_MCP" == true ]]; then
  install_arxiv_mcp
  merge_json_defaults "${VSCODE_USER_DIR}/mcp.json" "${REPO_ROOT}/mcp/mcp.json.example" "$FORCE_SETTINGS" "$ARXIV_ENTRY"
  printf 'mcp\t%s\n' "${VSCODE_USER_DIR}/mcp.json" >> "$MANAGED_FILE"
  if [[ "$INSTALL_COPILOT_CLI" == true ]]; then merge_copilot_cli_mcp; fi
else
  copy_managed_file "${REPO_ROOT}/mcp/mcp.json.example" "${PROFILE_ROOT}/mcp/mcp.json.example" mcp-template
  copy_managed_file "${REPO_ROOT}/mcp/copilot-cli.mcp.json.example" "${PROFILE_ROOT}/mcp/copilot-cli.mcp.json.example" mcp-template
  echo 'MCP installation skipped. The reviewed template was copied for reference.'
fi

progress 'Create optional Obsidian vault template'
if [[ "$SKIP_VAULT" == true ]]; then
  echo 'Vault template installation skipped.'
else
  if [[ ! -d "$VAULT_PATH" ]]; then record_created "$VAULT_PATH"; run mkdir -p "$VAULT_PATH"; printf 'vault\t%s\n' "$VAULT_PATH" >> "$MANAGED_FILE"; fi
  while IFS= read -r -d '' source; do
    relative="${source#${REPO_ROOT}/vault-template/}"
    target="${VAULT_PATH}/${relative}"
    if [[ ! -e "$target" ]]; then
      record_created "$target"
      run mkdir -p "$(dirname "$target")"
      run cp "$source" "$target"
    fi
  done < <(find "${REPO_ROOT}/vault-template" -type f -print0)
  workspace="${VAULT_PATH}/assured-arc.code-workspace"
  if [[ ! -e "$workspace" ]]; then
    record_created "$workspace"
    if [[ "$DRY_RUN" == true ]]; then echo "[dry run] create $workspace"; else
      python3 - "$workspace" <<'PY'
import json, sys
json.dump({'folders': [{'path': '.'}], 'settings': {'files.exclude': {'local-only': True}}}, open(sys.argv[1], 'w'), indent=2)
PY
    fi
  fi
fi

progress 'Write state and complete'
if [[ "$DRY_RUN" != true ]]; then
  MCP_TARGET=""
  CLI_MCP_TARGET=""
  [[ "$INSTALL_MCP" == true ]] && MCP_TARGET="${VSCODE_USER_DIR}/mcp.json"
  [[ "$INSTALL_MCP" == true && "$INSTALL_COPILOT_CLI" == true ]] && CLI_MCP_TARGET="${COPILOT_CLI_ROOT}/mcp-config.json"
  python3 - "$STATE_PATH" "$REPO_ROOT" "$PROFILE_ROOT" "$COPILOT_ROOT" "$VSCODE_USER_DIR" "$VAULT_PATH" "$MANAGED_FILE" "$BACKUP_FILE" "$CREATED_FILE" "$EXTENSIONS_FILE" "$MCP_SERVERS_FILE" "$MCP_INPUTS_FILE" "$MCP_TARGET" "${VSCODE_USER_DIR}/settings.json" "$SETTINGS_LOCATIONS_FILE" "$INSTALL_COPILOT_CLI" "$COPILOT_CLI_ROOT" "$CLI_SKILL_DIRECTORIES_FILE" "$CLI_MCP_SERVERS_FILE" "$CLI_MCP_TARGET" <<'PY'
import datetime, json, os, sys
state_path, repo, profile, copilot_root, vscode_user, vault_path, managed_file, backups_file, created_file, extensions_file, mcp_servers_file, mcp_inputs_file, mcp_target, settings_target, settings_locations_file, install_cli, cli_root, cli_skills_file, cli_servers_file, cli_mcp_target = sys.argv[1:]
def lines(path):
    try: return [line.rstrip('\n').split('\t') for line in open(path, encoding='utf-8') if line.strip()]
    except FileNotFoundError: return []
previous = json.load(open(state_path, encoding='utf-8')) if os.path.exists(state_path) else {}
def unique(items, key):
    result, seen = [], set()
    for item in items:
        marker = key(item)
        if marker not in seen:
            seen.add(marker); result.append(item)
    return result
current_backups = [{'target': target, 'backup': backup} for target, backup in lines(backups_file)]
previous_backups = previous.get('backups', [])
current_created = [target for [target] in lines(created_file)]
all_created = set(previous.get('created', []) + current_created)
managed = unique(previous.get('managed', []) + [{'kind': kind, 'target': target} for kind, target in lines(managed_file)], lambda item: (item['kind'], item['target']))
backups = unique(previous_backups + [item for item in current_backups if item['target'] not in all_created], lambda item: item['target'])
created = unique(previous.get('created', []) + current_created, lambda item: item)
extensions = unique(previous.get('extensions', []) + [line.strip() for line in open(extensions_file, encoding='utf-8') if line.strip()], lambda item: item)
previous_mcp = previous.get('mcp', {})
previous_settings = previous.get('settings', {})
previous_cli = previous.get('copilotCli', {})
current_settings = [
  {'setting': setting, 'path': path, 'added': added == 'true'}
  for setting, path, added in lines(settings_locations_file)
]
previous_setting_entries = previous_settings.get('locationEntries', [])
if install_cli.lower() == 'true':
  desired_agent_paths = {item['path'] for item in current_settings if item['setting'] == 'chat.agentFilesLocations'}
  previous_setting_entries = [item for item in previous_setting_entries if not (item.get('setting') == 'chat.agentFilesLocations' and item.get('added', True) and item.get('path') not in desired_agent_paths)]
setting_entries = unique(
  previous_setting_entries + current_settings,
  lambda item: (item['setting'], item['path']),
)
current_cli_skills = [
  {'path': path, 'added': added == 'true'}
  for path, added in lines(cli_skills_file)
]
cli_skill_entries = unique(
  previous_cli.get('settings', {}).get('skillDirectoryEntries', []) + current_cli_skills,
  lambda item: item['path'],
)
state = {
  'schema': 4,
  'createdAt': previous.get('createdAt', datetime.datetime.now(datetime.timezone.utc).isoformat()),
  'updatedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
  'repositoryRoot': repo,
  'profileRoot': profile,
  'copilotRoot': os.path.abspath(copilot_root),
  'vscodeUserDirectory': os.path.abspath(vscode_user),
  'vaultPath': os.path.abspath(vault_path),
  'managed': managed,
  'backups': backups,
  'created': created,
  'extensions': extensions,
  'settings': {
    'target': os.path.abspath(settings_target),
    'locationEntries': setting_entries,
  },
  'mcp': {
    'target': mcp_target or previous_mcp.get('target', ''),
    'serverIds': [line.strip() for line in open(mcp_servers_file, encoding='utf-8') if line.strip()],
    'inputIds': [line.strip() for line in open(mcp_inputs_file, encoding='utf-8') if line.strip()],
  },
  'copilotCli': {
    'enabled': install_cli.lower() == 'true' or previous_cli.get('enabled', False),
    'root': os.path.abspath(cli_root),
    'settings': {
      'target': os.path.abspath(os.path.join(cli_root, 'settings.json')) if (install_cli.lower() == 'true' or previous_cli.get('enabled', False)) else '',
      'skillDirectoryEntries': cli_skill_entries,
    },
    'mcp': {
      'target': cli_mcp_target or previous_cli.get('mcp', {}).get('target', ''),
      'serverIds': [line.strip() for line in open(cli_servers_file, encoding='utf-8') if line.strip()],
    },
  },
}
temporary = state_path + f'.tmp-{os.getpid()}'
with open(temporary, 'w', encoding='utf-8') as stream:
    json.dump(state, stream, indent=2); stream.write('\n')
os.replace(temporary, state_path)
import hashlib
with open(state_path, 'rb') as stream: digest = hashlib.sha256(stream.read()).hexdigest()
with open(state_path + '.sha256', 'w', encoding='ascii') as stream: stream.write(digest + '\n')
PY
  if ! python3 - "$STATE_PATH" "$BACKUP_FILE" <<'PY'
import json, os, shutil, sys
state_path, backups_file = sys.argv[1:]
retained = {item['backup'] for item in json.load(open(state_path, encoding='utf-8')).get('backups', [])}
for line in open(backups_file, encoding='utf-8'):
    if not line.strip(): continue
    _, backup = line.rstrip('\n').split('\t', 1)
    if backup in retained or not os.path.exists(backup): continue
    shutil.rmtree(backup) if os.path.isdir(backup) else os.remove(backup)
PY
  then
    echo 'Warning: installation succeeded, but transient backup cleanup failed.' >&2
  fi
  rmdir "$BACKUP_ROOT" 2>/dev/null || true
fi
trap - ERR
rm -f "$MANAGED_FILE" "$BACKUP_FILE" "$CREATED_FILE" "$EXTENSIONS_FILE" "$MCP_SERVERS_FILE" "$MCP_INPUTS_FILE" "$SETTINGS_LOCATIONS_FILE" "$SETTINGS_TEMPLATE" "$CLI_MCP_SERVERS_FILE" "$CLI_SKILL_DIRECTORIES_FILE" "$PREVIOUS_TARGETS_FILE"
echo 'Assured Arc installation completed successfully.'
if [[ "$DRY_RUN" == true ]]; then
  echo 'No changes were made because --dry-run was used.'
fi
