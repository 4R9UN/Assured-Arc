[CmdletBinding()]
param(
    [string]$LegacyProfileRoot = (Join-Path $HOME '.vscode-ai-bootstrap'),
    [string]$TargetProfileRoot = (Join-Path $HOME '.assured-arc')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$valid = $true
function Write-Check([bool]$Passed, [string]$Label, [string]$Detail = '') {
    Write-Host "$(if ($Passed) { 'PASS' } else { 'FAIL' }) $Label$(if ($Detail) { ": $Detail" })"
    if (-not $Passed) { $script:valid = $false }
}

$legacyRoot = [IO.Path]::GetFullPath($LegacyProfileRoot)
$targetRoot = [IO.Path]::GetFullPath($TargetProfileRoot)
$statePath = Join-Path $legacyRoot 'state.json'
if (-not (Test-Path -LiteralPath $statePath)) { Write-Check $false 'LEGACY STATE' 'not found'; exit 1 }
try { $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json }
catch { Write-Check $false 'LEGACY STATE JSON' 'invalid'; exit 1 }
$schema = if ($state.PSObject.Properties.Name -contains 'schema') { [int]$state.schema } else { 0 }
Write-Check ($schema -in @(2, 3, 4)) 'LEGACY SCHEMA' ([string]$schema)
if ($schema -ge 3) {
    $hashPath = $statePath + '.sha256'
    try { $checksumValid = (Test-Path -LiteralPath $hashPath) -and ((Get-Content -LiteralPath $hashPath -Raw).Trim().ToLowerInvariant() -eq (Get-FileHash $statePath -Algorithm SHA256).Hash.ToLowerInvariant()) }
    catch { $checksumValid = $false }
    Write-Check $checksumValid 'LEGACY CHECKSUM'
}
if (-not $valid) { exit 1 }
$managed = if ($state.PSObject.Properties.Name -contains 'managed') { @($state.managed) } else { @() }
$created = if ($state.PSObject.Properties.Name -contains 'created') { @($state.created) } else { @() }
$backups = if ($state.PSObject.Properties.Name -contains 'backups') { @($state.backups) } else { @() }
$paths = @($managed | ForEach-Object { $_.target }) + $created + @($backups | ForEach-Object { $_.target }) + @($backups | ForEach-Object { $_.backup })
foreach ($name in @('profileRoot', 'copilotRoot', 'vscodeUserDirectory', 'vaultPath')) {
    if ($state.PSObject.Properties.Name -contains $name -and $state.$name) { $paths += [string]$state.$name }
}
$settingsTarget = if ($state.PSObject.Properties.Name -contains 'settings' -and $state.settings.PSObject.Properties.Name -contains 'target') { [string]$state.settings.target } else { '' }
$mcpTarget = if ($state.PSObject.Properties.Name -contains 'mcp' -and $state.mcp.PSObject.Properties.Name -contains 'target') { [string]$state.mcp.target } else { '' }
$cliRoot = if ($state.PSObject.Properties.Name -contains 'copilotCli' -and $state.copilotCli.PSObject.Properties.Name -contains 'root') { [string]$state.copilotCli.root } else { '' }
$cliSettingsTarget = if ($state.PSObject.Properties.Name -contains 'copilotCli' -and $state.copilotCli.PSObject.Properties.Name -contains 'settings' -and $state.copilotCli.settings.PSObject.Properties.Name -contains 'target') { [string]$state.copilotCli.settings.target } else { '' }
$cliMcpTarget = if ($state.PSObject.Properties.Name -contains 'copilotCli' -and $state.copilotCli.PSObject.Properties.Name -contains 'mcp' -and $state.copilotCli.mcp.PSObject.Properties.Name -contains 'target') { [string]$state.copilotCli.mcp.target } else { '' }
foreach ($candidate in @($settingsTarget, $mcpTarget, $cliRoot, $cliSettingsTarget, $cliMcpTarget)) { if ($candidate) { $paths += $candidate } }
Write-Check (@($paths | Where-Object { $_ -and -not [IO.Path]::IsPathRooted([string]$_) }).Count -eq 0) 'OWNERSHIP PATHS' 'absolute'
$mcpIds = if ($state.PSObject.Properties.Name -contains 'mcp' -and $state.mcp.PSObject.Properties.Name -contains 'serverIds') { @($state.mcp.serverIds) } else { @() }
$cliMcpIds = if ($state.PSObject.Properties.Name -contains 'copilotCli' -and $state.copilotCli.PSObject.Properties.Name -contains 'mcp' -and $state.copilotCli.mcp.PSObject.Properties.Name -contains 'serverIds') { @($state.copilotCli.mcp.serverIds) } else { @() }
$safeIds = @($mcpIds + $cliMcpIds) | Where-Object { $_ -match '^[A-Za-z0-9._-]+$' } | Sort-Object -Unique
$extensionCount = if ($state.PSObject.Properties.Name -contains 'extensions') { @($state.extensions).Count } else { 0 }
Write-Check $true 'OWNED COMPONENTS' "$(@($managed).Count) managed entries; $extensionCount extensions"
Write-Check $true 'OWNED MCP IDS' $(if (@($safeIds).Count) { $safeIds -join ', ' } else { 'none' })
$conflict = (Test-Path -LiteralPath $targetRoot) -and @(Get-ChildItem -LiteralPath $targetRoot -Force -ErrorAction SilentlyContinue).Count -gt 0
Write-Check (-not $conflict) 'TARGET CONFLICT' $(if ($conflict) { 'target is not empty' } else { 'none' })
if ($valid) {
    Write-Host 'NEXT 1: run the matching legacy uninstall script with -ProfileRoot <legacy-profile-root>.'
    Write-Host 'NEXT 2: .\install.ps1 -Profile Full -ProfileRoot <target-profile-root>'
}
exit $(if ($valid) { 0 } else { 1 })