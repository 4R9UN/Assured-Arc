[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$failures = [System.Collections.ArrayList]@()
$checks = 0

function Test-Condition {
    param([bool]$Condition, [string]$Message)
    $script:checks++
    if ($Condition) { Write-Host "PASS $Message"; return }
    $script:failures.Add($Message) | Out-Null
    Write-Host "FAIL $Message"
}

function Test-PowerShellSyntax {
    param([string]$Path)
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors) | Out-Null
    Test-Condition -Condition ($errors.Count -eq 0) -Message "PowerShell parses: $([IO.Path]::GetFileName($Path))"
}

$required = @(
    'README.md', 'LICENSE', 'CONTRIBUTING.md', 'SECURITY.md', 'docs/HARNESS.md', 'install.ps1',
    'install/assured-arc.ps1', 'install/uninstall.ps1', 'install/assured-arc.sh', 'install/uninstall.sh',
    'hooks/harness-event.ps1', 'hooks/harness_event.py', 'tests/harness_contracts.py', 'tests/harness_evaluator.py',
    'config/extensions.json', 'config/user-settings.json', 'config/assured-arc.example.json', 'config/instructions.json', 'config/skill-registry.json', 'config/mcp-servers.json',
    'config/agent-harness.json', 'config/tool-policy.json', 'config/harness-evaluation-fixtures.json',
    'mcp/mcp.json.example', 'mcp/copilot-cli.mcp.json.example',
    '.github/hooks/agent-harness.json.example', '.github/hooks/copilot-cli-harness.json.example',
    '.github/instructions/assured-arc-general-agent.instructions.md', '.github/instructions/assured-arc-agent-harness.instructions.md',
    '.github/prompts/plan-implement-verify.prompt.md', '.github/prompts/research-and-decide.prompt.md', '.github/prompts/review-current-change.prompt.md',
    '.github/prompts/parallel-research-synthesize.prompt.md',
    '.github/prompts/multi-agent-change-review.prompt.md', '.github/prompts/evolve-harness-safely.prompt.md',
    'vault-template/Home.md', 'vault-template/_templates/Project Template.md'
)
foreach ($relative in $required) {
    Test-Condition -Condition (Test-Path -LiteralPath (Join-Path $repoRoot $relative)) -Message "Required file exists: $relative"
}

foreach ($relative in @('install.ps1', 'install/assured-arc.ps1', 'install/uninstall.ps1', 'hooks/harness-event.ps1')) {
    Test-PowerShellSyntax -Path (Join-Path $repoRoot $relative)
}

foreach ($relative in @('config/extensions.json', 'config/user-settings.json', 'config/assured-arc.example.json', 'config/instructions.json', 'config/skill-registry.json', 'config/mcp-servers.json', 'config/agent-harness.json', 'config/tool-policy.json', 'config/harness-evaluation-fixtures.json', '.github/hooks/agent-harness.json.example', '.github/hooks/copilot-cli-harness.json.example', 'mcp/mcp.json.example', 'mcp/copilot-cli.mcp.json.example')) {
    try {
        Get-Content -LiteralPath (Join-Path $repoRoot $relative) -Raw | ConvertFrom-Json | Out-Null
        Test-Condition -Condition $true -Message "JSON parses: $relative"
    }
    catch { Test-Condition -Condition $false -Message "JSON parses: $relative" }
}

$extensionManifest = Get-Content -LiteralPath (Join-Path $repoRoot 'config/extensions.json') -Raw | ConvertFrom-Json
$extensionIds = @($extensionManifest.extensions.id)
$powerShellInstaller = Get-Content -LiteralPath (Join-Path $repoRoot 'install/assured-arc.ps1') -Raw
$bashInstaller = Get-Content -LiteralPath (Join-Path $repoRoot 'install/assured-arc.sh') -Raw
Test-Condition -Condition ($extensionIds -contains 'github.copilot-chat') -Message 'Extension manifest includes the current built-in Copilot extension'
Test-Condition -Condition ($extensionIds -notcontains 'github.copilot') -Message 'Extension manifest excludes the deprecated standalone Copilot extension'
Test-Condition -Condition ((@($extensionManifest.extensions | Where-Object id -eq 'github.copilot-chat')[0].install) -eq $false) -Message 'Built-in Copilot Chat is validated as a capability and not installed by the package'
Test-Condition -Condition ($powerShellInstaller -notmatch '''--install-extension''\s+\$id\s+''--force''') -Message 'PowerShell installer does not force extension replacement or downgrade'
Test-Condition -Condition ($bashInstaller -notmatch '--install-extension\s+"\$extension"\s+--force') -Message 'Bash installer does not force extension replacement or downgrade'

$agentNames = [System.Collections.ArrayList]@()
Get-ChildItem -LiteralPath (Join-Path $repoRoot '.github/agents') -Filter '*.agent.md' | ForEach-Object {
    $text = Get-Content -LiteralPath $_.FullName -Raw
    Test-Condition -Condition ($text -match '(?m)^name:') -Message "Agent declares name: $($_.Name)"
    Test-Condition -Condition ($text -match '(?m)^description:') -Message "Agent declares description: $($_.Name)"
    if ($text -match '(?m)^name:\s*(.+?)\s*$') { $agentNames.Add($Matches[1].Trim('"', "'")) | Out-Null }
}

Get-ChildItem -LiteralPath (Join-Path $repoRoot '.github/prompts') -Filter '*.prompt.md' | ForEach-Object {
    $text = Get-Content -LiteralPath $_.FullName -Raw
    Test-Condition -Condition ($text -match '(?m)^name:\s*[a-z0-9-]+\s*$') -Message "Prompt declares slash-command name: $($_.Name)"
    Test-Condition -Condition ($text -match '(?m)^description:') -Message "Prompt declares description: $($_.Name)"
    Test-Condition -Condition ($text -match '(?m)^argument-hint:') -Message "Prompt declares argument hint: $($_.Name)"
    $declaredAgent = if ($text -match '(?m)^agent:\s*(.+?)\s*$') { $Matches[1].Trim('"', "'") } else { '' }
    Test-Condition -Condition ($agentNames -contains $declaredAgent) -Message "Prompt references a packaged agent: $($_.Name)"
}

$skillDirectories = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot '.github/skills') -Directory)
$skillDirectories | ForEach-Object {
    $skill = Join-Path $_.FullName 'SKILL.md'
    $text = Get-Content -LiteralPath $skill -Raw
    Test-Condition -Condition ($text -match "(?m)^name:\s*$([regex]::Escape($_.Name))\s*$") -Message "Skill name matches folder: $($_.Name)"
    Test-Condition -Condition ($text -match '(?m)^description:') -Message "Skill declares description: $($_.Name)"
}
$registry = Get-Content -LiteralPath (Join-Path $repoRoot 'config/skill-registry.json') -Raw | ConvertFrom-Json
$directoryIds = @($skillDirectories.Name | Sort-Object)
$registryIds = @($registry.skills.id | Sort-Object)
Test-Condition -Condition (($directoryIds -join '|') -eq ($registryIds -join '|')) -Message 'Skill registry exactly matches packaged skill folders'
Test-Condition -Condition ($registry.routing.maximumDomainSkills -le 3) -Message 'Skill registry enforces focused domain skill loading'

try {
    & python (Join-Path $repoRoot 'tests/harness_contracts.py') | Out-Host
    Test-Condition -Condition ($LASTEXITCODE -eq 0) -Message 'Native harness behavioral contracts pass'
}
catch { Test-Condition -Condition $false -Message "Native harness behavioral contracts pass: $($_.Exception.Message)" }
try {
    & python (Join-Path $repoRoot 'tests/harness_evaluator.py') --json | Out-Host
    Test-Condition -Condition ($LASTEXITCODE -eq 0) -Message 'Executable cross-platform harness trajectories pass'
}
catch { Test-Condition -Condition $false -Message "Executable cross-platform harness trajectories pass: $($_.Exception.Message)" }

$mcpInventory = Get-Content -LiteralPath (Join-Path $repoRoot 'config/mcp-servers.json') -Raw | ConvertFrom-Json
$mcpTemplate = Get-Content -LiteralPath (Join-Path $repoRoot 'mcp/mcp.json.example') -Raw | ConvertFrom-Json
$cliMcpTemplate = Get-Content -LiteralPath (Join-Path $repoRoot 'mcp/copilot-cli.mcp.json.example') -Raw | ConvertFrom-Json
$expectedMcpIds = @('arxiv', 'context7', 'sequential-thinking')
$inventoryMcpIds = @($mcpInventory.servers.id | Sort-Object)
$templateMcpIds = @($mcpTemplate.servers.PSObject.Properties.Name | Sort-Object)
Test-Condition -Condition (($inventoryMcpIds -join '|') -eq ($expectedMcpIds -join '|')) -Message 'MCP inventory contains exactly the three reviewed research servers'
Test-Condition -Condition (($templateMcpIds -join '|') -eq ($expectedMcpIds -join '|')) -Message 'MCP template contains exactly the three reviewed research servers'
Test-Condition -Condition ((@($cliMcpTemplate.mcpServers.PSObject.Properties.Name | Sort-Object) -join '|') -eq ($expectedMcpIds -join '|')) -Message 'Copilot CLI MCP template contains exactly the three reviewed research servers'
Test-Condition -Condition ($cliMcpTemplate.mcpServers.context7.url -eq 'https://mcp.context7.com/mcp') -Message 'Copilot CLI Context7 uses the reviewed hosted HTTPS endpoint'
Test-Condition -Condition ($cliMcpTemplate.mcpServers.arxiv.command -eq '__ARXIV_MCP_ENTRY__') -Message 'Copilot CLI template requires the managed arXiv executable'
Test-Condition -Condition ($mcpTemplate.servers.context7.url -eq 'https://mcp.context7.com/mcp') -Message 'Context7 uses the reviewed hosted HTTPS endpoint'
Test-Condition -Condition ($mcpTemplate.servers.'sequential-thinking'.env.DISABLE_THOUGHT_LOGGING -eq 'true') -Message 'Sequential Thinking logging is disabled by default'
Test-Condition -Condition ($mcpTemplate.servers.arxiv.command -eq '__ARXIV_MCP_ENTRY__') -Message 'Portable MCP template requires a package-managed arXiv executable'
$inventoryById = @{}
foreach ($item in $mcpInventory.servers) { $inventoryById[$item.id] = $item }
foreach ($property in $mcpTemplate.servers.PSObject.Properties) {
    $server = $property.Value
    if ($server.type -eq 'stdio') {
        Test-Condition -Condition (-not [string]::IsNullOrWhiteSpace($server.command)) -Message "Stdio MCP server declares a command: $($property.Name)"
    }
    else {
        Test-Condition -Condition (([uri]$server.url).Scheme -eq 'https') -Message "Remote MCP server uses HTTPS: $($property.Name)"
    }
    Test-Condition -Condition ($inventoryById[$property.Name].transport -eq $server.type) -Message "MCP inventory transport matches template: $($property.Name)"
}
$researchAgent = Get-Content -LiteralPath (Join-Path $repoRoot '.github/agents/assured-arc-research.agent.md') -Raw
$disposableResearcher = Get-Content -LiteralPath (Join-Path $repoRoot '.github/agents/assured-arc-disposable-researcher.agent.md') -Raw
$implementer = Get-Content -LiteralPath (Join-Path $repoRoot '.github/agents/assured-arc-disposable-implementer.agent.md') -Raw
foreach ($toolSet in @('context7/*', 'sequential-thinking/*', 'arxiv/*')) {
    Test-Condition -Condition ($researchAgent -match [regex]::Escape($toolSet)) -Message "Research agent exposes $toolSet"
    Test-Condition -Condition ($disposableResearcher -match [regex]::Escape($toolSet)) -Message "Disposable researcher exposes $toolSet"
    Test-Condition -Condition ($implementer -notmatch [regex]::Escape($toolSet)) -Message "Disposable implementer cannot access $toolSet"
}
$instructionManifest = Get-Content -LiteralPath (Join-Path $repoRoot 'config/instructions.json') -Raw | ConvertFrom-Json
Test-Condition -Condition (($instructionManifest.instructions -join '|') -eq 'assured-arc-general-agent.instructions.md|assured-arc-agent-harness.instructions.md') -Message 'Only repository-neutral global instructions are installed'

$hookSandbox = Join-Path ([IO.Path]::GetTempPath()) ('assured-arc-hook-' + [guid]::NewGuid().ToString('N'))
$oldHookConfig = $env:ASSURED_ARC_HARNESS_CONFIG
$oldHookTrace = $env:ASSURED_ARC_HARNESS_TRACE_DIR
try {
    $env:ASSURED_ARC_HARNESS_CONFIG = Join-Path $repoRoot 'config/agent-harness.json'
    $env:ASSURED_ARC_HARNESS_TRACE_DIR = Join-Path $hookSandbox 'traces'
    $hookScript = Join-Path $repoRoot 'hooks/harness-event.ps1'
    $baseEvent = [ordered]@{ timestamp = '2026-01-01T00:00:00Z'; cwd = $repoRoot; session_id = 'powershell-writer'; hook_event_name = 'SubagentStart'; agent_id = 'writer-one'; agent_type = 'Assured Arc Disposable Implementer' }
    $firstWriter = (($baseEvent | ConvertTo-Json -Compress -Depth 10) | & pwsh -NoProfile -File $hookScript | Out-String) | ConvertFrom-Json
    $baseEvent.agent_id = 'writer-two'
    $secondWriter = (($baseEvent | ConvertTo-Json -Compress -Depth 10) | & pwsh -NoProfile -File $hookScript | Out-String) | ConvertFrom-Json
    Test-Condition -Condition ($firstWriter.hookSpecificOutput.hookEventName -eq 'SubagentStart') -Message 'PowerShell hook permits the first implementation writer'
    Test-Condition -Condition ($secondWriter.continue -eq $false -and $secondWriter.stopReason -match 'Single-writer') -Message 'PowerShell hook blocks a second implementation writer'
    $wrongStop = [ordered]@{ timestamp = '2026-01-01T00:00:00Z'; cwd = $repoRoot; session_id = 'powershell-writer'; hook_event_name = 'SubagentStop'; agent_id = 'wrong'; agent_type = 'Assured Arc Disposable Implementer' }
    [void](($wrongStop | ConvertTo-Json -Compress -Depth 10) | & pwsh -NoProfile -File $hookScript | Out-String)
    $baseEvent.agent_id = 'writer-three'
    $stillBlocked = (($baseEvent | ConvertTo-Json -Compress -Depth 10) | & pwsh -NoProfile -File $hookScript | Out-String) | ConvertFrom-Json
    Test-Condition -Condition ($stillBlocked.continue -eq $false -and $stillBlocked.stopReason -match 'Single-writer') -Message 'PowerShell unmatched stop does not release the active writer'
    $approvalEvent = [ordered]@{ timestamp = '2026-01-01T00:00:00Z'; cwd = $repoRoot; session_id = 'powershell-approval'; hook_event_name = 'PreToolUse'; tool_name = 'run_in_terminal'; tool_input = [ordered]@{ command = 'npm install example' } }
    $approval = (($approvalEvent | ConvertTo-Json -Compress -Depth 10) | & pwsh -NoProfile -File $hookScript | Out-String) | ConvertFrom-Json
    Test-Condition -Condition ($approval.hookSpecificOutput.permissionDecision -eq 'ask') -Message 'PowerShell hook requires approval for dependency installation'
    $secret = 'SHOULD-NOT-APPEAR-IN-TRACE'
    $promptEvent = [ordered]@{ timestamp = '2026-01-01T00:00:00Z'; cwd = $repoRoot; session_id = 'powershell-redaction'; hook_event_name = 'UserPromptSubmit'; prompt = $secret }
    [void](($promptEvent | ConvertTo-Json -Compress -Depth 10) | & pwsh -NoProfile -File $hookScript | Out-String)
    $traceText = @(Get-ChildItem -LiteralPath $env:ASSURED_ARC_HARNESS_TRACE_DIR -Recurse -File | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
    Test-Condition -Condition ($traceText -notmatch [regex]::Escape($secret)) -Message 'PowerShell hook traces exclude prompt text'
}
catch { Test-Condition -Condition $false -Message "PowerShell hook contracts pass: $($_.Exception.Message)" }
finally {
    $env:ASSURED_ARC_HARNESS_CONFIG = $oldHookConfig
    $env:ASSURED_ARC_HARNESS_TRACE_DIR = $oldHookTrace
    if (Test-Path -LiteralPath $hookSandbox) { Remove-Item -LiteralPath $hookSandbox -Recurse -Force }
}

$dryProfile = Join-Path ([IO.Path]::GetTempPath()) ('assured-arc-test-' + [guid]::NewGuid().ToString('N'))
try {
    & (Join-Path $repoRoot 'install.ps1') -DryRun -SkipExtensions -SkipVault -SkipMcp -ProfileRoot $dryProfile -VsCodeUserDirectory (Join-Path $dryProfile 'vscode-user') -CopilotRoot (Join-Path $dryProfile 'copilot') | Out-Host
    Test-Condition -Condition (-not (Test-Path -LiteralPath $dryProfile)) -Message 'PowerShell dry run creates no profile directory'
}
catch {
    Test-Condition -Condition $false -Message "PowerShell dry run succeeds: $($_.Exception.Message)"
}

$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('assured-arc-install-' + [guid]::NewGuid().ToString('N'))
$profile = Join-Path $sandbox 'profile'
$vscodeUser = Join-Path $sandbox 'vscode-user'
$copilot = Join-Path $sandbox 'copilot'
$vault = Join-Path $profile 'vault'
try {
    New-Item -ItemType Directory -Path (Join-Path $vscodeUser 'prompts') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $vscodeUser 'prompts/untouched.prompt.md') -Value 'existing user prompt' -NoNewline
    & (Join-Path $repoRoot 'install.ps1') -SkipMcp -SkipExtensions -ProfileRoot $profile -VaultPath $vault -VsCodeUserDirectory $vscodeUser -CopilotRoot $copilot | Out-Host
    Test-Condition -Condition (Test-Path -LiteralPath (Join-Path $profile 'state.json')) -Message 'PowerShell isolated install writes state'
    Test-Condition -Condition (Test-Path -LiteralPath (Join-Path $copilot 'skills/assured-arc-development-quality/SKILL.md')) -Message 'PowerShell isolated install copies skills'
    Test-Condition -Condition (Test-Path -LiteralPath (Join-Path $copilot 'skill-registry.json')) -Message 'PowerShell isolated install copies skill registry'
    Test-Condition -Condition (Test-Path -LiteralPath (Join-Path $copilot 'agents/assured-arc-development.agent.md')) -Message 'PowerShell isolated install copies agents into the managed customization root'
    Test-Condition -Condition (Test-Path -LiteralPath (Join-Path $copilot 'prompts/plan-implement-verify.prompt.md')) -Message 'PowerShell isolated install copies reusable prompts'
    Test-Condition -Condition (Test-Path -LiteralPath (Join-Path $copilot 'instructions/assured-arc-general-agent.instructions.md')) -Message 'PowerShell isolated install copies the general instruction'
    Test-Condition -Condition (Test-Path -LiteralPath (Join-Path $copilot 'instructions/assured-arc-agent-harness.instructions.md')) -Message 'PowerShell isolated install copies the global harness instruction'
    Test-Condition -Condition (@(Get-ChildItem -LiteralPath (Join-Path $copilot 'instructions') -File).Count -eq 2) -Message 'PowerShell installs only the two generic global instructions'
    Test-Condition -Condition (Test-Path -LiteralPath (Join-Path $copilot 'agent-harness.json')) -Message 'PowerShell isolated install writes the harness policy'
    $renderedHarness = Get-Content -LiteralPath (Join-Path $copilot 'agent-harness.json') -Raw | ConvertFrom-Json
    Test-Condition -Condition ((@($renderedHarness.delegation.allowedWorkers) -join '|') -eq (@('Assured Arc Disposable Scout', 'Assured Arc Disposable Researcher', 'Assured Arc Disposable Implementer', 'Assured Arc Disposable Verifier', 'Assured Arc Disposable Critic') -join '|')) -Message 'PowerShell rendered harness preserves worker names as strings'
    Test-Condition -Condition ((@($renderedHarness.loop.phases) -join '|') -eq 'contract|route|delegate|act|verify|repair|complete') -Message 'PowerShell rendered harness preserves loop phase strings'
    Test-Condition -Condition (Test-Path -LiteralPath (Join-Path $copilot 'hooks/agent-harness.json')) -Message 'PowerShell isolated install writes rendered hooks'
    $installedSettings = Get-Content -LiteralPath (Join-Path $vscodeUser 'settings.json') -Raw | ConvertFrom-Json
    Test-Condition -Condition (@($installedSettings.'chat.promptFilesLocations'.PSObject.Properties).Count -eq 1) -Message 'PowerShell settings discover the managed prompt location'
    Test-Condition -Condition ((Get-Content -LiteralPath (Join-Path $vscodeUser 'prompts/untouched.prompt.md') -Raw) -eq 'existing user prompt') -Message 'PowerShell install preserves the existing user prompt directory'
    Test-Condition -Condition (Test-Path -LiteralPath (Join-Path $vault 'Home.md')) -Message 'PowerShell isolated install creates vault'

    & (Join-Path $repoRoot 'install.ps1') -SkipMcp -SkipExtensions -ProfileRoot $profile -VaultPath $vault -VsCodeUserDirectory $vscodeUser -CopilotRoot $copilot | Out-Host
    $skillCount = (Get-ChildItem -LiteralPath (Join-Path $copilot 'skills') -Directory).Count
    Test-Condition -Condition ($skillCount -eq $skillDirectories.Count) -Message 'PowerShell repeated install remains idempotent'

    $alternateCopilot = Join-Path $sandbox 'alternate-copilot'
    $migrationRejected = $false
    try { & (Join-Path $repoRoot 'install/assured-arc.ps1') -SkipMcp -SkipExtensions -SkipVault -ProfileRoot $profile -VsCodeUserDirectory $vscodeUser -CopilotRoot $alternateCopilot | Out-Null }
    catch { $migrationRejected = $_.Exception.Message -match 'cannot migrate copilotRoot' }
    Test-Condition -Condition $migrationRejected -Message 'PowerShell repeat install rejects Copilot root migration'

    & (Join-Path $repoRoot 'install/uninstall.ps1') -ProfileRoot $profile -CopilotRoot $copilot -VsCodeUserDirectory $vscodeUser -RemoveVault | Out-Host
    Test-Condition -Condition (-not (Test-Path -LiteralPath (Join-Path $profile 'state.json'))) -Message 'PowerShell uninstall removes state'
    Test-Condition -Condition (-not (Test-Path -LiteralPath (Join-Path $copilot 'skills/assured-arc-development-quality'))) -Message 'PowerShell uninstall removes managed skills'
    Test-Condition -Condition (-not (Test-Path -LiteralPath (Join-Path $copilot 'skill-registry.json'))) -Message 'PowerShell uninstall removes managed skill registry'
    Test-Condition -Condition (-not (Test-Path -LiteralPath (Join-Path $copilot 'prompts/plan-implement-verify.prompt.md'))) -Message 'PowerShell uninstall removes managed reusable prompts'
    Test-Condition -Condition (-not (Test-Path -LiteralPath (Join-Path $copilot 'instructions/assured-arc-general-agent.instructions.md'))) -Message 'PowerShell uninstall removes the managed general instruction'
    Test-Condition -Condition (-not (Test-Path -LiteralPath (Join-Path $copilot 'agent-harness.json'))) -Message 'PowerShell uninstall removes the managed harness policy'
    $uninstalledSettings = Get-Content -LiteralPath (Join-Path $vscodeUser 'settings.json') -Raw | ConvertFrom-Json
    Test-Condition -Condition (@($uninstalledSettings.'chat.promptFilesLocations'.PSObject.Properties).Count -eq 0) -Message 'PowerShell uninstall removes the package prompt location from settings'
    Test-Condition -Condition ((Get-Content -LiteralPath (Join-Path $vscodeUser 'prompts/untouched.prompt.md') -Raw) -eq 'existing user prompt') -Message 'PowerShell uninstall preserves unrelated user prompts'
    Test-Condition -Condition (-not (Test-Path -LiteralPath $vault)) -Message 'PowerShell uninstall removes opted in vault'
}
catch {
    Test-Condition -Condition $false -Message "PowerShell isolated install and uninstall succeeds: $($_.Exception.Message)"
}
finally {
    if (Test-Path -LiteralPath $sandbox) { Remove-Item -LiteralPath $sandbox -Recurse -Force }
}

$cliSandbox = Join-Path ([IO.Path]::GetTempPath()) ('assured-arc-cli-' + [guid]::NewGuid().ToString('N'))
try {
    $cliProfile = Join-Path $cliSandbox 'profile'
    $cliVsCode = Join-Path $cliSandbox 'vscode-user'
    $cliManaged = Join-Path $cliSandbox 'managed'
    $cliRoot = Join-Path $cliSandbox 'cli-home'
    New-Item -ItemType Directory -Path $cliRoot -Force | Out-Null
    $fakeCopilot = Join-Path $cliSandbox 'copilot.cmd'
    Set-Content -LiteralPath $fakeCopilot -Encoding Ascii -Value "@echo off`r`nexit /b 0"
    $existingCliSettings = [ordered]@{ keep = 'user-value'; skillDirectories = @((Join-Path $cliSandbox 'existing-skills')) }
    $existingCliSettings | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $cliRoot 'settings.json') -Encoding utf8
    $existingCliMcp = [ordered]@{ mcpServers = [ordered]@{ unrelated = [ordered]@{ type = 'http'; url = 'https://example.invalid/mcp'; tools = @('*') } } }
    $existingCliMcp | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $cliRoot 'mcp-config.json') -Encoding utf8

    & (Join-Path $repoRoot 'install.ps1') -InstallCopilotCli -SkipMcp -SkipExtensions -SkipVault -ProfileRoot $cliProfile -VsCodeUserDirectory $cliVsCode -CopilotRoot $cliManaged -CopilotCliRoot $cliRoot -CopilotCliCommand $fakeCopilot | Out-Host
    $cliState = Get-Content -LiteralPath (Join-Path $cliProfile 'state.json') -Raw | ConvertFrom-Json
    Test-Condition -Condition ($cliState.schema -eq 4 -and $cliState.copilotCli.enabled) -Message 'PowerShell state records Copilot CLI ownership with schema 4'
    Test-Condition -Condition (Test-Path -LiteralPath (Join-Path $cliRoot 'agents/assured-arc-orchestrator.agent.md')) -Message 'PowerShell installs agents into the Copilot CLI user profile'
    Test-Condition -Condition (Test-Path -LiteralPath (Join-Path $cliRoot 'instructions/assured-arc-agent-harness.instructions.md')) -Message 'PowerShell installs modular Copilot CLI instructions'
    Test-Condition -Condition (Test-Path -LiteralPath (Join-Path $cliRoot 'hooks/assured-arc.json')) -Message 'PowerShell installs Copilot CLI user hooks'
    $cliHooks = Get-Content -LiteralPath (Join-Path $cliRoot 'hooks/assured-arc.json') -Raw | ConvertFrom-Json
    Test-Condition -Condition ($cliHooks.version -eq 1 -and $cliHooks.hooks.preToolUse[0].env.ASSURED_ARC_HARNESS_HOST -eq 'copilot-cli') -Message 'PowerShell renders the Copilot CLI hook contract'
    $cliSettings = Get-Content -LiteralPath (Join-Path $cliRoot 'settings.json') -Raw | ConvertFrom-Json
    Test-Condition -Condition ($cliSettings.keep -eq 'user-value' -and @($cliSettings.skillDirectories).Count -eq 2) -Message 'PowerShell preserves CLI settings and registers managed skills once'
    $cliVsCodeSettings = Get-Content -LiteralPath (Join-Path $cliVsCode 'settings.json') -Raw | ConvertFrom-Json
    Test-Condition -Condition (@($cliVsCodeSettings.'chat.agentFilesLocations'.PSObject.Properties.Name)[0] -like '*/cli-home/agents') -Message 'VS Code and Copilot CLI share the CLI-native agent directory'

    & (Join-Path $repoRoot 'install.ps1') -InstallCopilotCli -SkipMcp -SkipExtensions -SkipVault -ProfileRoot $cliProfile -VsCodeUserDirectory $cliVsCode -CopilotRoot $cliManaged -CopilotCliRoot $cliRoot -CopilotCliCommand $fakeCopilot | Out-Null
    $cliSettings = Get-Content -LiteralPath (Join-Path $cliRoot 'settings.json') -Raw | ConvertFrom-Json
    Test-Condition -Condition (@($cliSettings.skillDirectories).Count -eq 2) -Message 'PowerShell repeated CLI install remains idempotent'

    & (Join-Path $repoRoot 'install/uninstall.ps1') -ProfileRoot $cliProfile -CopilotRoot $cliManaged -CopilotCliRoot $cliRoot -VsCodeUserDirectory $cliVsCode | Out-Host
    $remainingCliSettings = Get-Content -LiteralPath (Join-Path $cliRoot 'settings.json') -Raw | ConvertFrom-Json
    $remainingCliMcp = Get-Content -LiteralPath (Join-Path $cliRoot 'mcp-config.json') -Raw | ConvertFrom-Json
    Test-Condition -Condition ($remainingCliSettings.keep -eq 'user-value' -and @($remainingCliSettings.skillDirectories).Count -eq 1) -Message 'PowerShell CLI uninstall preserves unrelated settings and skill directories'
    $remainingCliMcpIds = @($remainingCliMcp.mcpServers.PSObject.Properties.Name)
    Test-Condition -Condition ($remainingCliMcpIds.Count -eq 1 -and $remainingCliMcpIds[0] -eq 'unrelated') -Message 'PowerShell CLI uninstall preserves unrelated MCP servers'
    Test-Condition -Condition (-not (Test-Path -LiteralPath (Join-Path $cliRoot 'agents/assured-arc-orchestrator.agent.md'))) -Message 'PowerShell CLI uninstall removes package agents'
    Test-Condition -Condition (-not (Test-Path -LiteralPath (Join-Path $cliRoot 'hooks/assured-arc.json'))) -Message 'PowerShell CLI uninstall removes package hooks'
}
catch { Test-Condition -Condition $false -Message "PowerShell Copilot CLI lifecycle succeeds: $($_.Exception.Message)" }
finally {
    if (Test-Path -LiteralPath $cliSandbox) { Remove-Item -LiteralPath $cliSandbox -Recurse -Force }
}

$ownershipSandbox = Join-Path ([IO.Path]::GetTempPath()) ('assured-arc-settings-owner-' + [guid]::NewGuid().ToString('N'))
try {
    $ownershipProfile = Join-Path $ownershipSandbox 'profile'
    $ownershipVsCode = Join-Path $ownershipSandbox 'vscode-user'
    $ownershipCopilot = Join-Path $ownershipSandbox 'copilot'
    New-Item -ItemType Directory -Path $ownershipVsCode -Force | Out-Null
    $existingPromptFullPath = [IO.Path]::GetFullPath((Join-Path $ownershipCopilot 'prompts'))
    $homePrefix = [IO.Path]::GetFullPath($HOME).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $existingPromptPath = '~/' + $existingPromptFullPath.Substring($homePrefix.Length).Replace('\', '/')
    $existingPromptLocations = [ordered]@{}
    $existingPromptLocations[$existingPromptPath] = $true
    $existingSettings = [ordered]@{ 'chat.promptFilesLocations' = $existingPromptLocations; preserve = 'user-value' }
    $existingSettings | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $ownershipVsCode 'settings.json') -Encoding utf8
    & (Join-Path $repoRoot 'install/assured-arc.ps1') -SkipMcp -SkipExtensions -SkipVault -ProfileRoot $ownershipProfile -VsCodeUserDirectory $ownershipVsCode -CopilotRoot $ownershipCopilot | Out-Null
    $ownershipState = Get-Content -LiteralPath (Join-Path $ownershipProfile 'state.json') -Raw | ConvertFrom-Json
    $ownedPromptEntry = @($ownershipState.settings.locationEntries | Where-Object { $_.setting -eq 'chat.promptFilesLocations' -and $_.path -eq $existingPromptPath })
    Test-Condition -Condition ($ownedPromptEntry.Count -eq 1 -and $ownedPromptEntry[0].added -eq $false) -Message 'PowerShell state distinguishes a preexisting customization location'
    & (Join-Path $repoRoot 'install/uninstall.ps1') -ProfileRoot $ownershipProfile -CopilotRoot $ownershipCopilot -VsCodeUserDirectory $ownershipVsCode | Out-Null
    $preservedSettings = Get-Content -LiteralPath (Join-Path $ownershipVsCode 'settings.json') -Raw | ConvertFrom-Json
    Test-Condition -Condition ($preservedSettings.'chat.promptFilesLocations'.PSObject.Properties.Name -contains $existingPromptPath) -Message 'PowerShell uninstall preserves a preexisting package-named customization location'
    Test-Condition -Condition ($preservedSettings.preserve -eq 'user-value') -Message 'PowerShell uninstall preserves unrelated settings values'
}
catch { Test-Condition -Condition $false -Message "PowerShell settings ownership validation succeeds: $($_.Exception.Message)" }
finally {
    if (Test-Path -LiteralPath $ownershipSandbox) { Remove-Item -LiteralPath $ownershipSandbox -Recurse -Force }
}

$tamperSandbox = Join-Path ([IO.Path]::GetTempPath()) ('assured-arc-tamper-' + [guid]::NewGuid().ToString('N'))
try {
    $tamperProfile = Join-Path $tamperSandbox 'profile'
    $tamperVsCode = Join-Path $tamperSandbox 'vscode-user'
    $tamperCopilot = Join-Path $tamperProfile 'copilot'
    $protectedVictim = Join-Path $tamperSandbox 'victim'
    New-Item -ItemType Directory -Path $protectedVictim -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $protectedVictim 'keep.txt') -Value 'keep' -NoNewline
    & (Join-Path $repoRoot 'install/assured-arc.ps1') -SkipMcp -SkipExtensions -SkipVault -ProfileRoot $tamperProfile -VsCodeUserDirectory $tamperVsCode -CopilotRoot $tamperCopilot | Out-Null
    $tamperedState = Get-Content -LiteralPath (Join-Path $tamperProfile 'state.json') -Raw | ConvertFrom-Json
    $tamperedState.managed += [pscustomobject]@{ kind = 'skill'; target = $protectedVictim }
    $tamperedState | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $tamperProfile 'state.json') -Encoding utf8
    $repeatRejected = $false
    try { & (Join-Path $repoRoot 'install/assured-arc.ps1') -SkipMcp -SkipExtensions -SkipVault -ProfileRoot $tamperProfile -VsCodeUserDirectory $tamperVsCode -CopilotRoot $tamperCopilot | Out-Null }
    catch { $repeatRejected = $_.Exception.Message -match 'state integrity validation failed' }
    Test-Condition -Condition $repeatRejected -Message 'PowerShell repeat install rejects tampered prior state'
    $tamperRejected = $false
    try { & (Join-Path $repoRoot 'install/uninstall.ps1') -ProfileRoot $tamperProfile -CopilotRoot $tamperCopilot -VsCodeUserDirectory $tamperVsCode | Out-Null }
    catch { $tamperRejected = $_.Exception.Message -match 'state integrity validation failed' }
    Test-Condition -Condition $tamperRejected -Message 'PowerShell uninstall rejects tampered state before path mutation'
    Test-Condition -Condition (Test-Path -LiteralPath (Join-Path $protectedVictim 'keep.txt')) -Message 'PowerShell rejected tampered state preserves unrelated files'
}
catch { Test-Condition -Condition $false -Message "PowerShell tampered state validation succeeds: $($_.Exception.Message)" }
finally {
    if (Test-Path -LiteralPath $tamperSandbox) { Remove-Item -LiteralPath $tamperSandbox -Recurse -Force }
}

$homeProfile = Join-Path $HOME ('.assured-arc-location-test-' + [guid]::NewGuid().ToString('N'))
try {
    $homeVsCode = Join-Path $homeProfile 'vscode-user'
    & (Join-Path $repoRoot 'install/assured-arc.ps1') -SkipMcp -SkipExtensions -SkipVault -ProfileRoot $homeProfile -VsCodeUserDirectory $homeVsCode | Out-Null
    $homeSettings = Get-Content -LiteralPath (Join-Path $homeVsCode 'settings.json') -Raw | ConvertFrom-Json
    $locationKeys = @(
        $homeSettings.'chat.agentFilesLocations'.PSObject.Properties.Name
        $homeSettings.'chat.promptFilesLocations'.PSObject.Properties.Name
        $homeSettings.'chat.agentSkillsLocations'.PSObject.Properties.Name
        $homeSettings.'chat.instructionsFilesLocations'.PSObject.Properties.Name | Where-Object { $_ -like '~/.assured-arc-location-test-*' }
        $homeSettings.'chat.hookFilesLocations'.PSObject.Properties.Name
    )
    Test-Condition -Condition ($locationKeys.Count -eq 5 -and @($locationKeys | Where-Object { $_ -notlike '~/*' }).Count -eq 0) -Message 'PowerShell default global customization locations use supported tilde paths'
    & (Join-Path $repoRoot 'install/uninstall.ps1') -ProfileRoot $homeProfile -VsCodeUserDirectory $homeVsCode | Out-Null
}
catch { Test-Condition -Condition $false -Message "PowerShell tilde location validation succeeds: $($_.Exception.Message)" }
finally {
    if (Test-Path -LiteralPath $homeProfile) { Remove-Item -LiteralPath $homeProfile -Recurse -Force }
}

$rollbackSandbox = Join-Path ([IO.Path]::GetTempPath()) ('assured-arc-rollback-' + [guid]::NewGuid().ToString('N'))
$rollbackProfile = Join-Path $rollbackSandbox 'profile'
$rollbackVsCode = Join-Path $rollbackSandbox 'vscode-user'
$rollbackCopilot = Join-Path $rollbackSandbox 'copilot'
$invalidVault = Join-Path $rollbackSandbox 'vault-file'
try {
    New-Item -ItemType Directory -Path $rollbackSandbox -Force | Out-Null
    Set-Content -LiteralPath $invalidVault -Value 'not a directory' -NoNewline
    $failedAsExpected = $false
    try {
        & (Join-Path $repoRoot 'install/assured-arc.ps1') -SkipMcp -SkipExtensions -ProfileRoot $rollbackProfile -VaultPath $invalidVault -VsCodeUserDirectory $rollbackVsCode -CopilotRoot $rollbackCopilot | Out-Host
    }
    catch { $failedAsExpected = $true }
    Test-Condition -Condition $failedAsExpected -Message 'PowerShell installer reports simulated vault failure'
    Test-Condition -Condition (-not (Test-Path -LiteralPath (Join-Path $rollbackCopilot 'skills/assured-arc-development-quality'))) -Message 'PowerShell rollback removes copied skills'
    Test-Condition -Condition (-not (Test-Path -LiteralPath (Join-Path $rollbackVsCode 'settings.json'))) -Message 'PowerShell rollback removes created settings'
}
catch {
    Test-Condition -Condition $false -Message "PowerShell rollback validation succeeds: $($_.Exception.Message)"
}
finally {
    if (Test-Path -LiteralPath $rollbackSandbox) { Remove-Item -LiteralPath $rollbackSandbox -Recurse -Force }
}

$linkSandbox = Join-Path ([IO.Path]::GetTempPath()) ('assured-arc-link-' + [guid]::NewGuid().ToString('N'))
try {
    $realProfile = Join-Path $linkSandbox 'real-profile'
    $linkedProfile = Join-Path $linkSandbox 'linked-profile'
    New-Item -ItemType Directory -Path $realProfile -Force | Out-Null
    New-Item -ItemType Junction -Path $linkedProfile -Target $realProfile | Out-Null
    $linkRejected = $false
    try {
        & (Join-Path $repoRoot 'install/assured-arc.ps1') -SkipMcp -SkipExtensions -SkipVault -ProfileRoot $linkedProfile -VsCodeUserDirectory (Join-Path $linkSandbox 'vscode') -CopilotRoot (Join-Path $linkSandbox 'copilot') | Out-Host
    }
    catch { $linkRejected = $_.Exception.Message -match 'symbolic link or junction' }
    Test-Condition -Condition $linkRejected -Message 'PowerShell installer rejects linked profile paths before reading state'

    $uninstallLinkRejected = $false
    try { & (Join-Path $repoRoot 'install/uninstall.ps1') -ProfileRoot $linkedProfile | Out-Host }
    catch { $uninstallLinkRejected = $_.Exception.Message -match 'symbolic link or junction' }
    Test-Condition -Condition $uninstallLinkRejected -Message 'PowerShell uninstall rejects linked profile paths before reading state'

    $relativeProfile = Join-Path $linkSandbox 'relative-profile'
    New-Item -ItemType Directory -Path $relativeProfile -Force | Out-Null
    $relativeState = [ordered]@{ schema = 2; managed = @(); backups = @(); extensions = @(); mcp = [ordered]@{ target = 'relative-mcp.json'; serverIds = @('github'); inputIds = @() } }
    $relativeState | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $relativeProfile 'state.json') -Encoding utf8
    $relativeRejected = $false
    try { & (Join-Path $repoRoot 'install/uninstall.ps1') -ProfileRoot $relativeProfile | Out-Host }
    catch { $relativeRejected = $_.Exception.Message -match 'relative and cannot be trusted' }
    Test-Condition -Condition $relativeRejected -Message 'PowerShell uninstall rejects relative legacy MCP ownership'
}
catch {
    Test-Condition -Condition $false -Message "PowerShell link validation succeeds: $($_.Exception.Message)"
}
finally {
    if (Test-Path -LiteralPath $linkSandbox) { Remove-Item -LiteralPath $linkSandbox -Recurse -Force }
}

$mcpSandbox = Join-Path ([IO.Path]::GetTempPath()) ('assured-arc-mcp-' + [guid]::NewGuid().ToString('N'))
$mcpProfile = Join-Path $mcpSandbox 'profile'
$mcpVsCode = Join-Path $mcpSandbox 'vscode-user'
$mcpCopilot = Join-Path $mcpSandbox 'copilot'
$fakeBin = Join-Path $mcpSandbox 'bin'
$uvLog = Join-Path $mcpSandbox 'uv.log'
$originalPath = $env:PATH
try {
    New-Item -ItemType Directory -Path $fakeBin -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $fakeBin 'node.cmd') -Encoding Ascii -Value @'
@echo off
if "%~1"=="--version" echo v20.0.0
exit /b 0
'@
    Set-Content -LiteralPath (Join-Path $fakeBin 'npx.cmd') -Encoding Ascii -Value "@echo off`r`nexit /b 0"
    Set-Content -LiteralPath (Join-Path $fakeBin 'copilot.cmd') -Encoding Ascii -Value "@echo off`r`nexit /b 0"
    $fakeNpxCli = Join-Path $fakeBin 'node_modules\npm\bin\npx-cli.js'
    New-Item -ItemType Directory -Path (Split-Path -Parent $fakeNpxCli) -Force | Out-Null
    Set-Content -LiteralPath $fakeNpxCli -Encoding Ascii -Value '// test fixture'
    $uvFixture = @'
@echo off
setlocal EnableExtensions
if not defined UV_TOOL_BIN_DIR exit /b 1
mkdir "%UV_TOOL_BIN_DIR%" >nul 2>nul
> "%UV_TOOL_BIN_DIR%\arxiv-mcp-server.exe" echo fixture
>> "__UV_LOG__" echo install
exit /b 0
'@.Replace('__UV_LOG__', $uvLog)
    Set-Content -LiteralPath (Join-Path $fakeBin 'uv.cmd') -Encoding Ascii -Value $uvFixture
    $env:PATH = "$fakeBin$([IO.Path]::PathSeparator)$originalPath"

    New-Item -ItemType Directory -Path $mcpVsCode -Force | Out-Null
    $originalMcp = [ordered]@{ servers = [ordered]@{ unrelated = [ordered]@{ type = 'http'; url = 'https://example.invalid/mcp' } }; inputs = @() }
    $originalMcp | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $mcpVsCode 'mcp.json') -Encoding utf8

    & (Join-Path $repoRoot 'install.ps1') -SkipExtensions -SkipVault -ProfileRoot $mcpProfile -VsCodeUserDirectory $mcpVsCode -CopilotRoot $mcpCopilot | Out-Host
    $installedMcpPath = Join-Path $mcpVsCode 'mcp.json'
    $installedMcpText = Get-Content -LiteralPath $installedMcpPath -Raw
    $installedMcp = $installedMcpText | ConvertFrom-Json
    $installedIds = @($installedMcp.servers.PSObject.Properties.Name | Sort-Object)
    $installedArxivEntry = $installedMcp.servers.arxiv.command
    Test-Condition -Condition (($installedIds -join '|') -eq ((@($expectedMcpIds + 'unrelated') | Sort-Object) -join '|')) -Message 'PowerShell root installer configures exactly the three reviewed MCP servers'
    Test-Condition -Condition ($installedMcp.servers.unrelated.url -eq 'https://example.invalid/mcp') -Message 'PowerShell MCP install preserves unrelated server definitions'
    Test-Condition -Condition ($installedMcpText -notmatch '__ARXIV_MCP_ENTRY__') -Message 'PowerShell MCP install resolves the arXiv executable path'
    Test-Condition -Condition (Test-Path -LiteralPath $installedArxivEntry) -Message 'PowerShell MCP install creates the managed arXiv executable'
    Test-Condition -Condition ($installedMcp.servers.'sequential-thinking'.command -eq (Join-Path $fakeBin 'node.cmd')) -Message 'PowerShell MCP install launches npx through Node without cmd shell parsing'
    $mcpState = Get-Content -LiteralPath (Join-Path $mcpProfile 'state.json') -Raw | ConvertFrom-Json
    Test-Condition -Condition (@($mcpState.managed.kind) -contains 'mcp-runtime') -Message 'PowerShell state records the managed arXiv runtime'
    Test-Condition -Condition ([IO.Path]::IsPathRooted([string]$mcpState.mcp.target)) -Message 'PowerShell state stores canonical MCP ownership target'

    & (Join-Path $repoRoot 'install.ps1') -SkipExtensions -SkipVault -ProfileRoot $mcpProfile -VsCodeUserDirectory $mcpVsCode -CopilotRoot $mcpCopilot | Out-Host
    Test-Condition -Condition (@(Get-Content -LiteralPath $uvLog).Count -eq 1) -Message 'PowerShell repeated MCP install reuses the pinned immutable arXiv tool'
    $repeatedState = Get-Content -LiteralPath (Join-Path $mcpProfile 'state.json') -Raw | ConvertFrom-Json
    Test-Condition -Condition (@($repeatedState.backups | Where-Object { $_.target -eq $installedMcpPath }).Count -eq 1) -Message 'PowerShell repeated install preserves one original MCP backup'

    $movedVsCode = Join-Path $mcpSandbox 'moved-vscode-user'
    $moveRejected = $false
    try {
        & (Join-Path $repoRoot 'install.ps1') -SkipExtensions -SkipVault -ProfileRoot $mcpProfile -VsCodeUserDirectory $movedVsCode -CopilotRoot $mcpCopilot | Out-Host
    }
    catch { $moveRejected = $_.Exception.Message -match 'cannot migrate' }
    Test-Condition -Condition $moveRejected -Message 'PowerShell MCP ownership cannot migrate to another user configuration'
    Test-Condition -Condition (-not (Test-Path -LiteralPath (Join-Path $movedVsCode 'mcp.json'))) -Message 'PowerShell rejected MCP migration leaves no orphan configuration'

    $strictMcp = Get-Content -LiteralPath $installedMcpPath -Raw | ConvertFrom-Json | ConvertTo-Json -Depth 20
    $jsoncMcp = "{`n  // retained user comment`n" + $strictMcp.Substring(1, $strictMcp.Length - 2) + ",`n}`n"
    Set-Content -LiteralPath $installedMcpPath -Value $jsoncMcp -NoNewline

    & (Join-Path $repoRoot 'install/uninstall.ps1') -ProfileRoot $mcpProfile -CopilotRoot $mcpCopilot -VsCodeUserDirectory $mcpVsCode | Out-Host
    Test-Condition -Condition (-not (Test-Path -LiteralPath (Join-Path $mcpProfile 'mcp\arxiv-0.5.1'))) -Message 'PowerShell uninstall removes the managed arXiv runtime'
    $remainingMcp = Get-Content -LiteralPath $installedMcpPath -Raw | ConvertFrom-Json
    $remainingServerIds = @($remainingMcp.servers.PSObject.Properties.Name)
    Test-Condition -Condition ($remainingServerIds.Count -eq 1 -and $remainingServerIds[0] -eq 'unrelated') -Message 'PowerShell uninstall removes package MCP entries and preserves unrelated entries'
    Test-Condition -Condition $true -Message 'PowerShell uninstall accepts valid JSONC MCP configuration'

    $cliMcpRoot = Join-Path $mcpSandbox 'cli-profile'
    $cliMcpProfile = Join-Path $cliMcpRoot 'profile'
    $cliMcpVsCode = Join-Path $cliMcpRoot 'vscode-user'
    $cliMcpManaged = Join-Path $cliMcpRoot 'managed'
    $cliMcpHome = Join-Path $cliMcpRoot 'cli-home'
    New-Item -ItemType Directory -Path $cliMcpVsCode,$cliMcpHome -Force | Out-Null
    $unrelatedCliMcp = [ordered]@{ mcpServers = [ordered]@{ unrelated = [ordered]@{ type = 'http'; url = 'https://example.invalid/mcp'; tools = @('*') } } }
    $unrelatedCliMcp | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $cliMcpHome 'mcp-config.json') -Encoding utf8
    & (Join-Path $repoRoot 'install.ps1') -InstallCopilotCli -SkipExtensions -SkipVault -ProfileRoot $cliMcpProfile -VsCodeUserDirectory $cliMcpVsCode -CopilotRoot $cliMcpManaged -CopilotCliRoot $cliMcpHome -CopilotCliCommand (Join-Path $fakeBin 'copilot.cmd') | Out-Host
    $installedCliMcp = Get-Content -LiteralPath (Join-Path $cliMcpHome 'mcp-config.json') -Raw | ConvertFrom-Json
    $installedCliMcpIds = @($installedCliMcp.mcpServers.PSObject.Properties.Name | Sort-Object)
    Test-Condition -Condition (($installedCliMcpIds -join '|') -eq ((@($expectedMcpIds + 'unrelated') | Sort-Object) -join '|')) -Message 'PowerShell configures exactly the reviewed MCP servers for Copilot CLI'
    Test-Condition -Condition ($installedCliMcp.mcpServers.unrelated.url -eq 'https://example.invalid/mcp') -Message 'PowerShell preserves unrelated Copilot CLI MCP servers'
    Test-Condition -Condition (Test-Path -LiteralPath $installedCliMcp.mcpServers.arxiv.command) -Message 'PowerShell Copilot CLI MCP uses the managed arXiv runtime'
    $cliMcpState = Get-Content -LiteralPath (Join-Path $cliMcpProfile 'state.json') -Raw | ConvertFrom-Json
    Test-Condition -Condition ((@($cliMcpState.copilotCli.mcp.serverIds | Sort-Object) -join '|') -eq ($expectedMcpIds -join '|')) -Message 'PowerShell state records Copilot CLI MCP ownership'
    & (Join-Path $repoRoot 'install/uninstall.ps1') -ProfileRoot $cliMcpProfile -CopilotRoot $cliMcpManaged -CopilotCliRoot $cliMcpHome -VsCodeUserDirectory $cliMcpVsCode | Out-Host
    $remainingCliMcp = Get-Content -LiteralPath (Join-Path $cliMcpHome 'mcp-config.json') -Raw | ConvertFrom-Json
    $remainingCliMcpIds = @($remainingCliMcp.mcpServers.PSObject.Properties.Name)
    Test-Condition -Condition ($remainingCliMcpIds.Count -eq 1 -and $remainingCliMcpIds[0] -eq 'unrelated') -Message 'PowerShell CLI uninstall removes only package-owned MCP servers'

    $conflictRoot = Join-Path $mcpSandbox 'conflict'
    $conflictProfile = Join-Path $conflictRoot 'profile'
    $conflictVsCode = Join-Path $conflictRoot 'vscode-user'
    $conflictCopilot = Join-Path $conflictRoot 'copilot'
    New-Item -ItemType Directory -Path $conflictVsCode -Force | Out-Null
    $conflictText = '{"servers":{"context7":{"type":"http","url":"https://example.invalid/custom"}},"inputs":[]}'
    Set-Content -LiteralPath (Join-Path $conflictVsCode 'mcp.json') -Value $conflictText -NoNewline
    $conflicted = $false
    try {
        & (Join-Path $repoRoot 'install.ps1') -SkipExtensions -SkipVault -ProfileRoot $conflictProfile -VsCodeUserDirectory $conflictVsCode -CopilotRoot $conflictCopilot | Out-Host
    }
    catch { $conflicted = $_.Exception.Message -match 'server:context7' }
    Test-Condition -Condition $conflicted -Message 'PowerShell MCP install refuses an unreviewed same-name server conflict'
    Test-Condition -Condition ((Get-Content -LiteralPath (Join-Path $conflictVsCode 'mcp.json') -Raw) -eq $conflictText) -Message 'PowerShell conflict rollback restores the original MCP configuration'

    $restoreRoot = Join-Path $mcpSandbox 'restore'
    $restoreProfile = Join-Path $restoreRoot 'profile'
    $restoreVsCode = Join-Path $restoreRoot 'vscode-user'
    $restoreCopilot = Join-Path $restoreRoot 'copilot'
    $restorePrompt = Join-Path $restoreCopilot 'prompts\plan-implement-verify.prompt.md'
    $restoreMcp = Join-Path $restoreVsCode 'mcp.json'
    New-Item -ItemType Directory -Path (Split-Path -Parent $restorePrompt) -Force | Out-Null
    New-Item -ItemType Directory -Path (Split-Path -Parent $restoreMcp) -Force | Out-Null
    $originalPromptText = 'original user prompt'
    $originalMcpText = '{"servers":{"unrelated":{"type":"http","url":"https://example.invalid/original"}},"inputs":[]}'
    Set-Content -LiteralPath $restorePrompt -Value $originalPromptText -NoNewline
    Set-Content -LiteralPath $restoreMcp -Value $originalMcpText -NoNewline
    1..2 | ForEach-Object {
        & (Join-Path $repoRoot 'install.ps1') -SkipExtensions -SkipVault -ProfileRoot $restoreProfile -VsCodeUserDirectory $restoreVsCode -CopilotRoot $restoreCopilot | Out-Host
    }
    & (Join-Path $repoRoot 'install/uninstall.ps1') -ProfileRoot $restoreProfile -CopilotRoot $restoreCopilot -VsCodeUserDirectory $restoreVsCode -RestoreBackups | Out-Host
    Test-Condition -Condition ((Get-Content -LiteralPath $restorePrompt -Raw) -eq $originalPromptText) -Message 'PowerShell restore returns the original prompt after repeated installs'
    Test-Condition -Condition ((Get-Content -LiteralPath $restoreMcp -Raw) -eq $originalMcpText) -Message 'PowerShell restore returns the original MCP file after repeated installs'
}
catch {
    Test-Condition -Condition $false -Message "PowerShell isolated MCP lifecycle succeeds: $($_.Exception.Message)"
}
finally {
    $env:PATH = $originalPath
    if (Test-Path -LiteralPath $mcpSandbox) { Remove-Item -LiteralPath $mcpSandbox -Recurse -Force }
}

try {
    & (Join-Path $PSScriptRoot 'public-safety.ps1') | Out-Host
    Test-Condition -Condition $true -Message 'Public safety scan succeeds'
}
catch {
    Test-Condition -Condition $false -Message "Public safety scan succeeds: $($_.Exception.Message)"
}

if ($failures.Count -gt 0) {
    throw "Validation failed ($($failures.Count)/$checks): $($failures -join '; ')"
}
Write-Host "Validation passed: $checks checks"
