[CmdletBinding()]
param([string]$ProfileRoot = (Join-Path $HOME '.assured-arc'))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$healthy = $true

function Write-Check([bool]$Passed, [string]$Label, [string]$Detail = '') {
    $prefix = if ($Passed) { 'PASS' } else { 'FAIL' }
    Write-Host "$prefix $Label$(if ($Detail) { ": $Detail" })"
    if (-not $Passed) { $script:healthy = $false }
}

function Test-Command([string]$Name) {
    Write-Check ([bool](Get-Command $Name -ErrorAction SilentlyContinue)) "COMMAND $Name"
}

Test-Command 'pwsh'
$statePath = Join-Path ([IO.Path]::GetFullPath($ProfileRoot)) 'state.json'
if (-not (Test-Path -LiteralPath $statePath)) {
    Write-Check $true 'STATE' 'not installed; optional component prerequisites not inferred'
    exit $(if ($healthy) { 0 } else { 1 })
}

try { $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json }
catch { Write-Check $false 'STATE JSON' 'invalid'; exit 1 }
$schema = if ($state.PSObject.Properties.Name -contains 'schema') { [int]$state.schema } else { 0 }
Write-Check ($schema -in @(2, 3, 4)) 'STATE SCHEMA' ([string]$schema)
if ($schema -ge 3) {
    $checksumPath = $statePath + '.sha256'
    try { $checksumValid = (Test-Path -LiteralPath $checksumPath) -and ((Get-Content -LiteralPath $checksumPath -Raw).Trim().ToLowerInvariant() -eq (Get-FileHash -LiteralPath $statePath -Algorithm SHA256).Hash.ToLowerInvariant()) }
    catch { $checksumValid = $false }
    Write-Check $checksumValid 'STATE CHECKSUM'
}
else { Write-Check $true 'STATE CHECKSUM' 'not required by schema' }

$extensions = @(if ($state.PSObject.Properties.Name -contains 'extensions') { @($state.extensions) } else { @() })
$managed = @(if ($state.PSObject.Properties.Name -contains 'managed') { @($state.managed) } else { @() })
$mcpTarget = if ($state.PSObject.Properties.Name -contains 'mcp' -and $state.mcp.PSObject.Properties.Name -contains 'target') { [string]$state.mcp.target } else { '' }
$cliEnabled = $state.PSObject.Properties.Name -contains 'copilotCli' -and $state.copilotCli.PSObject.Properties.Name -contains 'enabled' -and [bool]$state.copilotCli.enabled
foreach ($command in @('code')) {
    if ($extensions.Count -gt 0) { Test-Command $command }
}
if ($mcpTarget -or @($managed | Where-Object kind -eq 'mcp-runtime').Count -gt 0) {
    foreach ($command in @('node', 'npx', 'uv')) { Test-Command $command }
}
if ($cliEnabled) { Test-Command 'copilot' }

$missing = @($managed | Where-Object { -not $_.target -or -not [IO.Path]::IsPathRooted([string]$_.target) -or -not (Test-Path -LiteralPath ([string]$_.target)) })
Write-Check ($missing.Count -eq 0) 'MANAGED FILES' "$($managed.Count - $missing.Count)/$($managed.Count) present"
$runtimes = @($managed | Where-Object kind -eq 'mcp-runtime')
$missingRuntimes = @($runtimes | Where-Object { -not (Test-Path -LiteralPath ([string]$_.target)) })
Write-Check ($missingRuntimes.Count -eq 0) 'MCP RUNTIME' $(if ($runtimes.Count) { "$($runtimes.Count - $missingRuntimes.Count)/$($runtimes.Count) present" } else { 'not recorded' })
exit $(if ($healthy) { 0 } else { 1 })