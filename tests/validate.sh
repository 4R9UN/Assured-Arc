#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for script in "${ROOT}/install/assured-arc.sh" "${ROOT}/install/uninstall.sh"; do
  bash -n "$script"
  echo "PASS shell syntax: $(basename "$script")"
done
python3 -m py_compile "${ROOT}/hooks/harness_event.py" "${ROOT}/tests/harness_contracts.py" "${ROOT}/tests/harness_evaluator.py"
python3 "${ROOT}/tests/harness_contracts.py"
python3 "${ROOT}/tests/harness_evaluator.py" --json

python3 - "$ROOT" <<'PY'
import json, os, sys
root = sys.argv[1]
for rel in [
    'config/extensions.json', 'config/user-settings.json',
    'config/assured-arc.example.json', 'config/instructions.json', 'config/skill-registry.json', 'config/mcp-servers.json', 'mcp/mcp.json.example',
    'mcp/copilot-cli.mcp.json.example',
    'config/agent-harness.json', 'config/tool-policy.json', 'config/harness-evaluation-fixtures.json',
    '.github/hooks/agent-harness.json.example', '.github/hooks/copilot-cli-harness.json.example',
]:
    with open(os.path.join(root, rel), encoding='utf-8') as f: json.load(f)
    print('PASS JSON:', rel)
extensions = json.load(open(os.path.join(root, 'config', 'extensions.json'), encoding='utf-8'))['extensions']
extension_ids = [item['id'] for item in extensions]
if 'github.copilot-chat' not in extension_ids: raise SystemExit('Current built-in Copilot extension is missing')
if 'github.copilot' in extension_ids: raise SystemExit('Deprecated standalone Copilot extension must not be installed')
if next(item for item in extensions if item['id'] == 'github.copilot-chat').get('install') is not False:
    raise SystemExit('Built-in Copilot Chat must be a non-installing capability entry')
if '--install-extension "$extension" --force' in open(os.path.join(root, 'install', 'assured-arc.sh'), encoding='utf-8').read():
    raise SystemExit('Bash installer forces extension replacement')
print('PASS extension safety metadata')
for name in os.listdir(os.path.join(root, '.github', 'skills')):
    skill = os.path.join(root, '.github', 'skills', name, 'SKILL.md')
    if not os.path.isfile(skill): raise SystemExit('Missing skill: ' + skill)
    text = open(skill, encoding='utf-8').read()
    if f'name: {name}' not in text: raise SystemExit('Skill name mismatch: ' + name)
folders = sorted(name for name in os.listdir(os.path.join(root, '.github', 'skills')) if os.path.isdir(os.path.join(root, '.github', 'skills', name)))
registry = json.load(open(os.path.join(root, 'config', 'skill-registry.json'), encoding='utf-8'))
ids = sorted(skill['id'] for skill in registry['skills'])
if folders != ids: raise SystemExit('Skill registry does not match packaged skill folders')
if registry['routing']['maximumDomainSkills'] > 3: raise SystemExit('Skill registry allows excessive context loading')
print('PASS skill metadata')
agent_names = set()
for name in os.listdir(os.path.join(root, '.github', 'agents')):
    if not name.endswith('.agent.md'): continue
    text = open(os.path.join(root, '.github', 'agents', name), encoding='utf-8').read()
    match = __import__('re').search(r'^name:\s*(.+?)\s*$', text, __import__('re').M)
    if match: agent_names.add(match.group(1).strip('"\''))
for name in os.listdir(os.path.join(root, '.github', 'prompts')):
    if not name.endswith('.prompt.md'): continue
    text = open(os.path.join(root, '.github', 'prompts', name), encoding='utf-8').read()
    for field in ('name', 'description', 'argument-hint', 'agent'):
        if not __import__('re').search(rf'^{field}:', text, __import__('re').M): raise SystemExit(f'Prompt {name} is missing {field}')
    agent = __import__('re').search(r'^agent:\s*(.+?)\s*$', text, __import__('re').M).group(1).strip('"\'')
    if agent not in agent_names: raise SystemExit(f'Prompt {name} references unknown agent {agent}')
print('PASS prompt metadata')
inventory = json.load(open(os.path.join(root, 'config', 'mcp-servers.json'), encoding='utf-8'))
template = json.load(open(os.path.join(root, 'mcp', 'mcp.json.example'), encoding='utf-8'))
cli_template = json.load(open(os.path.join(root, 'mcp', 'copilot-cli.mcp.json.example'), encoding='utf-8'))
expected = sorted(('context7', 'sequential-thinking', 'arxiv'))
if sorted(item['id'] for item in inventory['servers']) != expected: raise SystemExit('MCP inventory mismatch')
if sorted(template['servers']) != expected: raise SystemExit('MCP template mismatch')
if sorted(cli_template['mcpServers']) != expected: raise SystemExit('Copilot CLI MCP template mismatch')
if template['servers']['context7']['url'] != 'https://mcp.context7.com/mcp': raise SystemExit('Context7 endpoint mismatch')
if template['servers']['sequential-thinking']['env']['DISABLE_THOUGHT_LOGGING'] != 'true': raise SystemExit('Sequential Thinking logging is enabled')
if template['servers']['arxiv']['command'] != '__ARXIV_MCP_ENTRY__': raise SystemExit('arXiv executable placeholder missing')
inventory_by_id = {item['id']: item for item in inventory['servers']}
for name, server in template['servers'].items():
    if server['type'] == 'stdio' and not server.get('command'): raise SystemExit(f'Stdio command missing: {name}')
    if server['type'] in ('http', 'sse') and not server.get('url', '').startswith('https://'): raise SystemExit(f'Remote MCP is not HTTPS: {name}')
    if inventory_by_id[name]['transport'] != server['type']: raise SystemExit(f'MCP transport mismatch: {name}')
instructions = json.load(open(os.path.join(root, 'config', 'instructions.json'), encoding='utf-8'))['instructions']
if instructions != ['assured-arc-general-agent.instructions.md', 'assured-arc-agent-harness.instructions.md']: raise SystemExit('Global instruction allowlist is not repository neutral')
print('PASS MCP metadata')
PY

PROFILE="$(mktemp -d)/profile"
bash "${ROOT}/install/assured-arc.sh" --dry-run --skip-extensions --skip-vault --skip-mcp --profile-root "$PROFILE"
[[ ! -e "$PROFILE" ]]
echo 'PASS Bash dry run creates no profile directory'

SANDBOX="$(mktemp -d)"
PROFILE="${SANDBOX}/profile"
VSCODE_USER="${SANDBOX}/vscode-user"
COPILOT="${SANDBOX}/copilot"
VAULT="${PROFILE}/vault"
mkdir -p "${VSCODE_USER}/prompts"
printf '%s' 'existing user prompt' > "${VSCODE_USER}/prompts/untouched.prompt.md"
bash "${ROOT}/install/assured-arc.sh" --skip-mcp --skip-extensions --profile-root "$PROFILE" --vault-path "$VAULT" --vscode-user-dir "$VSCODE_USER" --copilot-root "$COPILOT"
[[ -f "${PROFILE}/state.json" ]]
[[ -f "${COPILOT}/skills/assured-arc-development-quality/SKILL.md" ]]
[[ -f "${COPILOT}/skill-registry.json" ]]
[[ -f "${COPILOT}/agents/assured-arc-development.agent.md" ]]
[[ -f "${COPILOT}/prompts/plan-implement-verify.prompt.md" ]]
[[ -f "${COPILOT}/instructions/assured-arc-general-agent.instructions.md" ]]
[[ -f "${COPILOT}/instructions/assured-arc-agent-harness.instructions.md" ]]
[[ "$(find "${COPILOT}/instructions" -maxdepth 1 -type f | wc -l)" -eq 2 ]]
[[ -f "${COPILOT}/agent-harness.json" ]]
[[ -f "${COPILOT}/hooks/agent-harness.json" ]]
[[ "$(cat "${VSCODE_USER}/prompts/untouched.prompt.md")" == 'existing user prompt' ]]
python3 - "${PROFILE}/state.json" "${VSCODE_USER}/settings.json" <<'PY'
import json, sys
state = json.load(open(sys.argv[1], encoding='utf-8'))
settings = json.load(open(sys.argv[2], encoding='utf-8'))
assert state['schema'] == 4
assert len(state['settings']['locationEntries']) == 5
assert len(settings['chat.promptFilesLocations']) == 1
PY
python3 - "${COPILOT}/agent-harness.json" <<'PY'
import json, sys
harness = json.load(open(sys.argv[1], encoding='utf-8'))
assert harness['delegation']['allowedWorkers'] == ['Assured Arc Disposable Scout', 'Assured Arc Disposable Researcher', 'Assured Arc Disposable Implementer', 'Assured Arc Disposable Verifier', 'Assured Arc Disposable Critic']
assert harness['loop']['phases'] == ['contract', 'route', 'delegate', 'act', 'verify', 'repair', 'complete']
assert len(harness['protectedRoots']) == 2
PY
[[ -f "${VAULT}/Home.md" ]]
echo 'PASS Bash isolated install'

bash "${ROOT}/install/assured-arc.sh" --skip-mcp --skip-extensions --profile-root "$PROFILE" --vault-path "$VAULT" --vscode-user-dir "$VSCODE_USER" --copilot-root "$COPILOT"
EXPECTED_SKILLS="$(find "${ROOT}/.github/skills" -mindepth 1 -maxdepth 1 -type d | wc -l)"
[[ "$(find "${COPILOT}/skills" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq "$EXPECTED_SKILLS" ]]
echo 'PASS Bash repeated install remains idempotent'
ALTERNATE_COPILOT="${SANDBOX}/alternate-copilot"
set +e
bash "${ROOT}/install/assured-arc.sh" --skip-mcp --skip-extensions --skip-vault --profile-root "$PROFILE" --vscode-user-dir "$VSCODE_USER" --copilot-root "$ALTERNATE_COPILOT" > "${SANDBOX}/migration.log" 2>&1
MIGRATION_STATUS=$?
set -e
[[ "$MIGRATION_STATUS" -ne 0 ]]
grep -q 'cannot migrate copilotRoot' "${SANDBOX}/migration.log"
echo 'PASS Bash repeat install rejects Copilot root migration'

bash "${ROOT}/install/uninstall.sh" --profile-root "$PROFILE" --copilot-root "$COPILOT" --vscode-user-dir "$VSCODE_USER" --remove-vault
[[ ! -e "${PROFILE}/state.json" ]]
[[ ! -e "${COPILOT}/skills/assured-arc-development-quality" ]]
[[ ! -e "${COPILOT}/skill-registry.json" ]]
[[ ! -e "${COPILOT}/prompts/plan-implement-verify.prompt.md" ]]
[[ ! -e "${COPILOT}/instructions/assured-arc-general-agent.instructions.md" ]]
[[ ! -e "${COPILOT}/agent-harness.json" ]]
[[ "$(cat "${VSCODE_USER}/prompts/untouched.prompt.md")" == 'existing user prompt' ]]
python3 - "${VSCODE_USER}/settings.json" <<'PY'
import json, sys
settings = json.load(open(sys.argv[1], encoding='utf-8'))
assert settings['chat.promptFilesLocations'] == {}
PY
[[ ! -e "$VAULT" ]]
rm -rf "$SANDBOX"
echo 'PASS Bash isolated uninstall'

CLI_SANDBOX="$(mktemp -d)"
CLI_PROFILE="${CLI_SANDBOX}/profile"
CLI_VSCODE="${CLI_SANDBOX}/vscode-user"
CLI_MANAGED="${CLI_SANDBOX}/managed"
CLI_HOME="${CLI_SANDBOX}/cli-home"
CLI_BIN="${CLI_SANDBOX}/bin"
mkdir -p "$CLI_HOME" "$CLI_BIN"
cat > "${CLI_BIN}/copilot" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "${CLI_BIN}/copilot"
python3 - "${CLI_HOME}/settings.json" "${CLI_HOME}/mcp-config.json" "${CLI_SANDBOX}/existing-skills" <<'PY'
import json, sys
settings, mcp, existing = sys.argv[1:]
json.dump({'keep': 'user-value', 'skillDirectories': [existing]}, open(settings, 'w'), indent=2)
json.dump({'mcpServers': {'unrelated': {'type': 'http', 'url': 'https://example.invalid/mcp', 'tools': ['*']}}}, open(mcp, 'w'), indent=2)
PY
PATH="${CLI_BIN}:${PATH}" bash "${ROOT}/install/assured-arc.sh" --install-copilot-cli --skip-mcp --skip-extensions --skip-vault --profile-root "$CLI_PROFILE" --vscode-user-dir "$CLI_VSCODE" --copilot-root "$CLI_MANAGED" --copilot-cli-root "$CLI_HOME"
python3 - "$CLI_SANDBOX" <<'PY'
import json, os, sys
root = sys.argv[1]
state = json.load(open(os.path.join(root, 'profile/state.json'), encoding='utf-8'))
assert state['schema'] == 4 and state['copilotCli']['enabled']
assert os.path.isfile(os.path.join(root, 'cli-home/agents/assured-arc-orchestrator.agent.md'))
assert os.path.isfile(os.path.join(root, 'cli-home/hooks/assured-arc.json'))
settings = json.load(open(os.path.join(root, 'cli-home/settings.json'), encoding='utf-8'))
assert settings['keep'] == 'user-value' and len(settings['skillDirectories']) == 2
vscode = json.load(open(os.path.join(root, 'vscode-user/settings.json'), encoding='utf-8'))
assert list(vscode['chat.agentFilesLocations'])[0].endswith('/cli-home/agents')
PY
PATH="${CLI_BIN}:${PATH}" bash "${ROOT}/install/assured-arc.sh" --install-copilot-cli --skip-mcp --skip-extensions --skip-vault --profile-root "$CLI_PROFILE" --vscode-user-dir "$CLI_VSCODE" --copilot-root "$CLI_MANAGED" --copilot-cli-root "$CLI_HOME" >/dev/null
python3 - "${CLI_HOME}/settings.json" <<'PY'
import json, sys
assert len(json.load(open(sys.argv[1], encoding='utf-8'))['skillDirectories']) == 2
PY
bash "${ROOT}/install/uninstall.sh" --profile-root "$CLI_PROFILE" --vscode-user-dir "$CLI_VSCODE" --copilot-root "$CLI_MANAGED" --copilot-cli-root "$CLI_HOME"
python3 - "$CLI_SANDBOX" <<'PY'
import json, os, sys
root = sys.argv[1]
settings = json.load(open(os.path.join(root, 'cli-home/settings.json'), encoding='utf-8'))
assert settings['keep'] == 'user-value' and len(settings['skillDirectories']) == 1
mcp = json.load(open(os.path.join(root, 'cli-home/mcp-config.json'), encoding='utf-8'))
assert list(mcp['mcpServers']) == ['unrelated']
assert not os.path.exists(os.path.join(root, 'cli-home/agents/assured-arc-orchestrator.agent.md'))
assert not os.path.exists(os.path.join(root, 'cli-home/hooks/assured-arc.json'))
PY
rm -rf "$CLI_SANDBOX"
echo 'PASS Bash Copilot CLI install, repeat, and uninstall lifecycle'

OWNERSHIP_SANDBOX="$(mktemp -d)"
OWNERSHIP_PROFILE="${OWNERSHIP_SANDBOX}/profile"
OWNERSHIP_VSCODE="${OWNERSHIP_SANDBOX}/vscode-user"
OWNERSHIP_COPILOT="${OWNERSHIP_SANDBOX}/copilot"
mkdir -p "$OWNERSHIP_VSCODE"
python3 - "${OWNERSHIP_VSCODE}/settings.json" "${OWNERSHIP_COPILOT}/prompts" <<'PY'
import json, os, sys
target, prompt_path = sys.argv[1:]
prompt_path = os.path.abspath(prompt_path).replace('\\', '/')
with open(target, 'w', encoding='utf-8') as stream:
    json.dump({'chat.promptFilesLocations': {prompt_path: True}, 'preserve': 'user-value'}, stream)
PY
bash "${ROOT}/install/assured-arc.sh" --skip-mcp --skip-extensions --skip-vault --profile-root "$OWNERSHIP_PROFILE" --vscode-user-dir "$OWNERSHIP_VSCODE" --copilot-root "$OWNERSHIP_COPILOT"
python3 - "${OWNERSHIP_PROFILE}/state.json" "${OWNERSHIP_COPILOT}/prompts" <<'PY'
import json, os, sys
state_path, prompt_path = sys.argv[1:]
prompt_path = os.path.abspath(prompt_path).replace('\\', '/')
state = json.load(open(state_path, encoding='utf-8'))
entries = [item for item in state['settings']['locationEntries'] if item['setting'] == 'chat.promptFilesLocations' and item['path'] == prompt_path]
assert len(entries) == 1 and entries[0]['added'] is False
PY
bash "${ROOT}/install/uninstall.sh" --profile-root "$OWNERSHIP_PROFILE" --copilot-root "$OWNERSHIP_COPILOT" --vscode-user-dir "$OWNERSHIP_VSCODE"
python3 - "${OWNERSHIP_VSCODE}/settings.json" "${OWNERSHIP_COPILOT}/prompts" <<'PY'
import json, os, sys
settings_path, prompt_path = sys.argv[1:]
prompt_path = os.path.abspath(prompt_path).replace('\\', '/')
settings = json.load(open(settings_path, encoding='utf-8'))
assert prompt_path in settings['chat.promptFilesLocations']
assert settings['preserve'] == 'user-value'
PY
rm -rf "$OWNERSHIP_SANDBOX"
echo 'PASS Bash uninstall preserves preexisting customization locations'

TAMPER_SANDBOX="$(mktemp -d)"
TAMPER_PROFILE="${TAMPER_SANDBOX}/profile"
TAMPER_VSCODE="${TAMPER_SANDBOX}/vscode-user"
TAMPER_COPILOT="${TAMPER_PROFILE}/copilot"
TAMPER_VICTIM="${TAMPER_SANDBOX}/victim"
mkdir -p "$TAMPER_VICTIM"
printf '%s' keep > "${TAMPER_VICTIM}/keep.txt"
bash "${ROOT}/install/assured-arc.sh" --skip-mcp --skip-extensions --skip-vault --profile-root "$TAMPER_PROFILE" --vscode-user-dir "$TAMPER_VSCODE" --copilot-root "$TAMPER_COPILOT"
python3 - "${TAMPER_PROFILE}/state.json" "$TAMPER_VICTIM" <<'PY'
import json, sys
path, victim = sys.argv[1:]
state = json.load(open(path, encoding='utf-8'))
state['managed'].append({'kind': 'skill', 'target': victim})
with open(path, 'w', encoding='utf-8') as stream: json.dump(state, stream)
PY
set +e
bash "${ROOT}/install/assured-arc.sh" --skip-mcp --skip-extensions --skip-vault --profile-root "$TAMPER_PROFILE" --vscode-user-dir "$TAMPER_VSCODE" --copilot-root "$TAMPER_COPILOT" > "${TAMPER_SANDBOX}/repeat.log" 2>&1
TAMPER_REPEAT_STATUS=$?
set -e
[[ "$TAMPER_REPEAT_STATUS" -ne 0 ]]
grep -q 'state integrity validation failed' "${TAMPER_SANDBOX}/repeat.log"
echo 'PASS Bash repeat install rejects tampered prior state'
set +e
bash "${ROOT}/install/uninstall.sh" --profile-root "$TAMPER_PROFILE" --copilot-root "$TAMPER_COPILOT" --vscode-user-dir "$TAMPER_VSCODE" > "${TAMPER_SANDBOX}/output.log" 2>&1
TAMPER_STATUS=$?
set -e
[[ "$TAMPER_STATUS" -ne 0 ]]
grep -q 'state integrity validation failed' "${TAMPER_SANDBOX}/output.log"
[[ -f "${TAMPER_VICTIM}/keep.txt" ]]
rm -rf "$TAMPER_SANDBOX"
echo 'PASS Bash uninstall rejects tampered state before path mutation'

HOME_PROFILE="${HOME}/.assured-arc-location-test-$$"
HOME_VSCODE="${HOME_PROFILE}/vscode-user"
bash "${ROOT}/install/assured-arc.sh" --skip-mcp --skip-extensions --skip-vault --profile-root "$HOME_PROFILE" --vscode-user-dir "$HOME_VSCODE"
python3 - "${HOME_VSCODE}/settings.json" <<'PY'
import json, sys
settings = json.load(open(sys.argv[1], encoding='utf-8'))
keys = []
for setting in ('chat.agentFilesLocations', 'chat.promptFilesLocations', 'chat.agentSkillsLocations', 'chat.hookFilesLocations'):
    keys.extend(settings[setting])
keys.extend(path for path in settings['chat.instructionsFilesLocations'] if path.startswith('~/.assured-arc-location-test-'))
assert len(keys) == 5 and all(path.startswith('~/') for path in keys)
PY
bash "${ROOT}/install/uninstall.sh" --profile-root "$HOME_PROFILE" --vscode-user-dir "$HOME_VSCODE"
rm -rf "$HOME_PROFILE"
echo 'PASS Bash default global customization locations use supported tilde paths'

ROLLBACK_SANDBOX="$(mktemp -d)"
PROFILE="${ROLLBACK_SANDBOX}/profile"
VSCODE_USER="${ROLLBACK_SANDBOX}/vscode-user"
COPILOT="${ROLLBACK_SANDBOX}/copilot"
INVALID_VAULT="${ROLLBACK_SANDBOX}/vault-file"
printf 'not a directory' > "$INVALID_VAULT"
set +e
bash "${ROOT}/install/assured-arc.sh" --skip-mcp --skip-extensions --profile-root "$PROFILE" --vault-path "$INVALID_VAULT" --vscode-user-dir "$VSCODE_USER" --copilot-root "$COPILOT"
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]]
[[ ! -e "${COPILOT}/skills/assured-arc-development-quality" ]]
[[ ! -e "${VSCODE_USER}/settings.json" ]]
rm -rf "$ROLLBACK_SANDBOX"
echo 'PASS Bash automatic rollback'

LINK_SANDBOX="$(mktemp -d)"
mkdir -p "${LINK_SANDBOX}/vscode-user"
printf '%s' '{"preserve":true}' > "${LINK_SANDBOX}/settings-target.json"
ln -s "${LINK_SANDBOX}/settings-target.json" "${LINK_SANDBOX}/vscode-user/settings.json"
set +e
bash "${ROOT}/install/assured-arc.sh" --skip-mcp --skip-extensions --skip-vault --profile-root "${LINK_SANDBOX}/profile" --vscode-user-dir "${LINK_SANDBOX}/vscode-user" --copilot-root "${LINK_SANDBOX}/copilot" > "${LINK_SANDBOX}/output.log" 2>&1
LINK_STATUS=$?
set -e
[[ "$LINK_STATUS" -ne 0 ]]
grep -q 'symbolic link' "${LINK_SANDBOX}/output.log"
[[ "$(cat "${LINK_SANDBOX}/settings-target.json")" == '{"preserve":true}' ]]
mkdir -p "${LINK_SANDBOX}/real-copilot"
ln -s "${LINK_SANDBOX}/real-copilot" "${LINK_SANDBOX}/linked-copilot"
set +e
bash "${ROOT}/install/assured-arc.sh" --skip-mcp --skip-extensions --skip-vault --profile-root "${LINK_SANDBOX}/parent-profile" --vscode-user-dir "${LINK_SANDBOX}/parent-vscode" --copilot-root "${LINK_SANDBOX}/linked-copilot" > "${LINK_SANDBOX}/parent-output.log" 2>&1
PARENT_LINK_STATUS=$?
set -e
[[ "$PARENT_LINK_STATUS" -ne 0 ]]
grep -q 'symbolic link' "${LINK_SANDBOX}/parent-output.log"
[[ -z "$(find "${LINK_SANDBOX}/real-copilot" -mindepth 1 -print -quit)" ]]
mkdir -p "${LINK_SANDBOX}/real-profile"
ln -s "${LINK_SANDBOX}/real-profile" "${LINK_SANDBOX}/linked-profile"
set +e
bash "${ROOT}/install/assured-arc.sh" --skip-mcp --skip-extensions --skip-vault --profile-root "${LINK_SANDBOX}/linked-profile" --vscode-user-dir "${LINK_SANDBOX}/profile-vscode" --copilot-root "${LINK_SANDBOX}/profile-copilot" > "${LINK_SANDBOX}/profile-output.log" 2>&1
PROFILE_LINK_STATUS=$?
set -e
[[ "$PROFILE_LINK_STATUS" -ne 0 ]]
grep -q 'symbolic link' "${LINK_SANDBOX}/profile-output.log"
mkdir -p "${LINK_SANDBOX}/state-profile"
printf '%s' '{}' > "${LINK_SANDBOX}/state-source.json"
ln -s "${LINK_SANDBOX}/state-source.json" "${LINK_SANDBOX}/state-profile/state.json"
set +e
bash "${ROOT}/install/assured-arc.sh" --skip-mcp --skip-extensions --skip-vault --profile-root "${LINK_SANDBOX}/state-profile" --vscode-user-dir "${LINK_SANDBOX}/state-vscode" --copilot-root "${LINK_SANDBOX}/state-copilot" > "${LINK_SANDBOX}/state-output.log" 2>&1
STATE_LINK_STATUS=$?
set -e
[[ "$STATE_LINK_STATUS" -ne 0 ]]
grep -q 'symbolic link' "${LINK_SANDBOX}/state-output.log"
set +e
bash "${ROOT}/install/uninstall.sh" --profile-root "${LINK_SANDBOX}/linked-profile" > "${LINK_SANDBOX}/uninstall-profile-output.log" 2>&1
UNINSTALL_PROFILE_STATUS=$?
set -e
[[ "$UNINSTALL_PROFILE_STATUS" -ne 0 ]]
grep -q 'symbolic link' "${LINK_SANDBOX}/uninstall-profile-output.log"
mkdir -p "${LINK_SANDBOX}/relative-profile"
printf '%s' '{"schema":2,"managed":[],"backups":[],"extensions":[],"mcp":{"target":"relative-mcp.json","serverIds":["github"],"inputIds":[]}}' > "${LINK_SANDBOX}/relative-profile/state.json"
set +e
bash "${ROOT}/install/uninstall.sh" --profile-root "${LINK_SANDBOX}/relative-profile" > "${LINK_SANDBOX}/relative-output.log" 2>&1
RELATIVE_STATUS=$?
set -e
[[ "$RELATIVE_STATUS" -ne 0 ]]
grep -q 'relative and cannot be trusted' "${LINK_SANDBOX}/relative-output.log"
rm -rf "$LINK_SANDBOX"
echo 'PASS Bash install and uninstall reject linked paths and relative MCP ownership before mutation'

MCP_SANDBOX="$(mktemp -d)"
PROFILE="${MCP_SANDBOX}/profile"
VSCODE_USER="${MCP_SANDBOX}/vscode-user"
COPILOT="${MCP_SANDBOX}/copilot"
FAKE_BIN="${MCP_SANDBOX}/bin"
FAKE_UV_LOG="${MCP_SANDBOX}/uv.log"
mkdir -p "$FAKE_BIN"
cat > "${FAKE_BIN}/node" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == '--version' ]]; then echo 'v20.0.0'; fi
exit 0
SH
cat > "${FAKE_BIN}/npx" <<'SH'
#!/usr/bin/env bash
exit 0
SH
cat > "${FAKE_BIN}/uv" <<'SH'
#!/usr/bin/env bash
[[ -n "${UV_TOOL_BIN_DIR:-}" ]] || exit 1
mkdir -p "$UV_TOOL_BIN_DIR"
printf '#!/usr/bin/env bash\nexit 0\n' > "${UV_TOOL_BIN_DIR}/arxiv-mcp-server"
chmod +x "${UV_TOOL_BIN_DIR}/arxiv-mcp-server"
printf 'install\n' >> "$FAKE_UV_LOG"
SH
cat > "${FAKE_BIN}/copilot" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "${FAKE_BIN}"/*
export FAKE_UV_LOG
ORIGINAL_PATH="$PATH"
export PATH="${FAKE_BIN}:${PATH}"
mkdir -p "$VSCODE_USER"
printf '%s' '{"servers":{"unrelated":{"type":"http","url":"https://example.invalid/mcp"}},"inputs":[]}' > "${VSCODE_USER}/mcp.json"
bash "${ROOT}/install/assured-arc.sh" --skip-extensions --skip-vault --profile-root "$PROFILE" --vscode-user-dir "$VSCODE_USER" --copilot-root "$COPILOT"
ARXIV_ENTRY="$(python3 - "${VSCODE_USER}/mcp.json" <<'PY'
import json, os, sys
data = json.load(open(sys.argv[1], encoding='utf-8'))
assert sorted(data['servers']) == sorted(('context7', 'sequential-thinking', 'arxiv', 'unrelated'))
assert data['servers']['unrelated']['url'] == 'https://example.invalid/mcp'
entry = data['servers']['arxiv']['command']
assert os.path.isfile(entry)
print(entry)
PY
)"
python3 - "${PROFILE}/state.json" <<'PY'
import json, os, sys
state = json.load(open(sys.argv[1], encoding='utf-8'))
assert 'mcp-runtime' in [item['kind'] for item in state['managed']]
assert os.path.isabs(state['mcp']['target'])
PY
echo 'PASS Bash default install configures three reviewed MCP servers and the managed arXiv runtime'
bash "${ROOT}/install/assured-arc.sh" --skip-extensions --skip-vault --profile-root "$PROFILE" --vscode-user-dir "$VSCODE_USER" --copilot-root "$COPILOT"
[[ "$(wc -l < "$FAKE_UV_LOG")" -eq 1 ]]
python3 - "${PROFILE}/state.json" "${VSCODE_USER}/mcp.json" <<'PY'
import json, sys
state = json.load(open(sys.argv[1], encoding='utf-8'))
assert len([item for item in state['backups'] if item['target'] == sys.argv[2]]) == 1
PY
echo 'PASS Bash repeated MCP install reuses the pinned immutable arXiv tool and preserves one original backup'
CLI_MCP_ROOT="${MCP_SANDBOX}/cli-profile"
CLI_MCP_PROFILE="${CLI_MCP_ROOT}/profile"
CLI_MCP_VSCODE="${CLI_MCP_ROOT}/vscode-user"
CLI_MCP_MANAGED="${CLI_MCP_ROOT}/managed"
CLI_MCP_HOME="${CLI_MCP_ROOT}/cli-home"
mkdir -p "$CLI_MCP_VSCODE" "$CLI_MCP_HOME"
printf '%s' '{"mcpServers":{"unrelated":{"type":"http","url":"https://example.invalid/mcp","tools":["*"]}}}' > "${CLI_MCP_HOME}/mcp-config.json"
bash "${ROOT}/install/assured-arc.sh" --install-copilot-cli --skip-extensions --skip-vault --profile-root "$CLI_MCP_PROFILE" --vscode-user-dir "$CLI_MCP_VSCODE" --copilot-root "$CLI_MCP_MANAGED" --copilot-cli-root "$CLI_MCP_HOME"
python3 - "${CLI_MCP_PROFILE}/state.json" "${CLI_MCP_HOME}/mcp-config.json" <<'PY'
import json, os, sys
state = json.load(open(sys.argv[1], encoding='utf-8'))
config = json.load(open(sys.argv[2], encoding='utf-8'))
assert sorted(config['mcpServers']) == sorted(('context7', 'sequential-thinking', 'arxiv', 'unrelated'))
assert config['mcpServers']['unrelated']['url'] == 'https://example.invalid/mcp'
assert os.path.isfile(config['mcpServers']['arxiv']['command'])
assert sorted(state['copilotCli']['mcp']['serverIds']) == sorted(('context7', 'sequential-thinking', 'arxiv'))
PY
bash "${ROOT}/install/uninstall.sh" --profile-root "$CLI_MCP_PROFILE" --vscode-user-dir "$CLI_MCP_VSCODE" --copilot-root "$CLI_MCP_MANAGED" --copilot-cli-root "$CLI_MCP_HOME"
python3 - "${CLI_MCP_HOME}/mcp-config.json" <<'PY'
import json, sys
assert list(json.load(open(sys.argv[1], encoding='utf-8'))['mcpServers']) == ['unrelated']
PY
echo 'PASS Bash Copilot CLI MCP lifecycle preserves unrelated servers'
MOVED_VSCODE="${MCP_SANDBOX}/moved-vscode-user"
set +e
bash "${ROOT}/install/assured-arc.sh" --skip-extensions --skip-vault --profile-root "$PROFILE" --vscode-user-dir "$MOVED_VSCODE" --copilot-root "$COPILOT" > "${MCP_SANDBOX}/move-output.log" 2>&1
MOVE_STATUS=$?
set -e
[[ "$MOVE_STATUS" -ne 0 ]]
grep -q 'cannot migrate' "${MCP_SANDBOX}/move-output.log"
[[ ! -e "${MOVED_VSCODE}/mcp.json" ]]
echo 'PASS Bash MCP ownership cannot migrate to another user configuration'
mv "$VSCODE_USER" "${VSCODE_USER}-real"
ln -s "${VSCODE_USER}-real" "$VSCODE_USER"
set +e
bash "${ROOT}/install/uninstall.sh" --profile-root "$PROFILE" --copilot-root "$COPILOT" --vscode-user-dir "$VSCODE_USER" > "${MCP_SANDBOX}/uninstall-link-output.log" 2>&1
UNINSTALL_LINK_STATUS=$?
set -e
[[ "$UNINSTALL_LINK_STATUS" -ne 0 ]]
grep -q 'symbolic link' "${MCP_SANDBOX}/uninstall-link-output.log"
[[ -f "${PROFILE}/state.json" && -e "${PROFILE}/mcp/arxiv-0.5.1" ]]
rm "$VSCODE_USER"
mv "${VSCODE_USER}-real" "$VSCODE_USER"
python3 - "${VSCODE_USER}/mcp.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding='utf-8'))
text = json.dumps(data, indent=2)
open(sys.argv[1], 'w', encoding='utf-8').write('{\n  // retained user comment\n' + text[1:-1] + ',\n}\n')
PY
bash "${ROOT}/install/uninstall.sh" --profile-root "$PROFILE" --copilot-root "$COPILOT" --vscode-user-dir "$VSCODE_USER"
[[ ! -e "${PROFILE}/mcp/arxiv-0.5.1" ]]
python3 - "${VSCODE_USER}/mcp.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding='utf-8'))
assert list(data['servers']) == ['unrelated']
PY
CONFLICT_ROOT="${MCP_SANDBOX}/conflict"
CONFLICT_PROFILE="${CONFLICT_ROOT}/profile"
CONFLICT_VSCODE="${CONFLICT_ROOT}/vscode-user"
CONFLICT_COPILOT="${CONFLICT_ROOT}/copilot"
mkdir -p "$CONFLICT_VSCODE"
CONFLICT_TEXT='{"servers":{"context7":{"type":"http","url":"https://example.invalid/custom"}},"inputs":[]}'
printf '%s' "$CONFLICT_TEXT" > "${CONFLICT_VSCODE}/mcp.json"
set +e
bash "${ROOT}/install/assured-arc.sh" --skip-extensions --skip-vault --profile-root "$CONFLICT_PROFILE" --vscode-user-dir "$CONFLICT_VSCODE" --copilot-root "$CONFLICT_COPILOT" > "${CONFLICT_ROOT}/output.log" 2>&1
CONFLICT_STATUS=$?
set -e
[[ "$CONFLICT_STATUS" -ne 0 ]]
grep -q 'server:context7' "${CONFLICT_ROOT}/output.log"
[[ "$(cat "${CONFLICT_VSCODE}/mcp.json")" == "$CONFLICT_TEXT" ]]
echo 'PASS Bash MCP conflict is rejected and rolled back'
RESTORE_ROOT="${MCP_SANDBOX}/restore"
RESTORE_PROFILE="${RESTORE_ROOT}/profile"
RESTORE_VSCODE="${RESTORE_ROOT}/vscode-user"
RESTORE_COPILOT="${RESTORE_ROOT}/copilot"
RESTORE_PROMPT="${RESTORE_COPILOT}/prompts/plan-implement-verify.prompt.md"
RESTORE_MCP="${RESTORE_VSCODE}/mcp.json"
ORIGINAL_PROMPT='original user prompt'
ORIGINAL_MCP='{"servers":{"unrelated":{"type":"http","url":"https://example.invalid/original"}},"inputs":[]}'
mkdir -p "$(dirname "$RESTORE_PROMPT")"
mkdir -p "$(dirname "$RESTORE_MCP")"
printf '%s' "$ORIGINAL_PROMPT" > "$RESTORE_PROMPT"
printf '%s' "$ORIGINAL_MCP" > "$RESTORE_MCP"
for _ in 1 2; do
    bash "${ROOT}/install/assured-arc.sh" --skip-extensions --skip-vault --profile-root "$RESTORE_PROFILE" --vscode-user-dir "$RESTORE_VSCODE" --copilot-root "$RESTORE_COPILOT"
done
bash "${ROOT}/install/uninstall.sh" --profile-root "$RESTORE_PROFILE" --copilot-root "$RESTORE_COPILOT" --vscode-user-dir "$RESTORE_VSCODE" --restore-backups
[[ "$(cat "$RESTORE_PROMPT")" == "$ORIGINAL_PROMPT" ]]
[[ "$(cat "$RESTORE_MCP")" == "$ORIGINAL_MCP" ]]
echo 'PASS Bash repeated install preserves and restores original prompt and MCP files'
export PATH="$ORIGINAL_PATH"
rm -rf "$MCP_SANDBOX"
echo 'PASS Bash MCP uninstall removes the managed arXiv runtime'
