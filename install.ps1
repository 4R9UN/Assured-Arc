<#
.SYNOPSIS
    Install or update Assured Arc on Windows.

.DESCRIPTION
    This is the only Windows entry point most users need. It delegates to the
    tested installer under install/, enables the reviewed Context7, Sequential
    Thinking, and arXiv MCP profile by default, optionally installs the same
    agents and guardrails for GitHub Copilot CLI, and preserves dry run, backup,
    rollback, and advanced installer options.
#>
[CmdletBinding()]
param(
    [string]$Profile,
    [string]$ProfileRoot = (Join-Path $HOME '.assured-arc'),
    [string]$VaultPath,
    [string]$VsCodeUserDirectory,
    [string]$CopilotRoot,
    [string]$CopilotCliRoot,
    [string]$ConfigPath,
    [string]$CodeCommand = 'code',
    [string]$CopilotCliCommand = 'copilot',
    [switch]$DryRun,
    [switch]$InstallCopilotCli,
    [switch]$SkipCopilotCli,
    [switch]$InstallExtensions,
    [switch]$SkipExtensions,
    [switch]$InstallVault,
    [switch]$SkipVault,
    [switch]$InstallMcp,
    [switch]$SkipMcp,
    [switch]$ForceSettings,
    [switch]$NoBackup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$installer = Join-Path $PSScriptRoot 'install\assured-arc.ps1'
if (-not (Test-Path -LiteralPath $installer)) {
    throw "Internal installer not found: $installer"
}

$arguments = @{
    ProfileRoot = $ProfileRoot
    CodeCommand = $CodeCommand
    CopilotCliCommand = $CopilotCliCommand
}
foreach ($name in @('Profile', 'VaultPath', 'VsCodeUserDirectory', 'CopilotRoot', 'CopilotCliRoot', 'ConfigPath')) {
    if ($PSBoundParameters.ContainsKey($name)) { $arguments[$name] = $PSBoundParameters[$name] }
}
foreach ($name in @('DryRun', 'InstallCopilotCli', 'SkipCopilotCli', 'InstallExtensions', 'SkipExtensions', 'InstallVault', 'SkipVault', 'InstallMcp', 'ForceSettings', 'NoBackup')) {
    if ($PSBoundParameters.ContainsKey($name)) { $arguments[$name] = [bool]$PSBoundParameters[$name] }
}
if ($SkipMcp) { $arguments.SkipMcp = $true }

& $installer @arguments
