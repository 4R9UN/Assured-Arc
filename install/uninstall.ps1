<#
.SYNOPSIS
    Remove managed Assured Arc assets.

.DESCRIPTION
    Removes only paths recorded in the installer state file. Existing VS Code and
    Copilot CLI settings and MCP configuration are left intact unless
    -RestoreBackups is supplied.
#>
[CmdletBinding()]
param(
    [string]$ProfileRoot = (Join-Path $HOME '.assured-arc'),
    [string]$CopilotRoot,
    [string]$CopilotCliRoot,
    [string]$VsCodeUserDirectory,
    [string]$CodeCommand = 'code',
    [switch]$RestoreBackups,
    [switch]$RemoveExtensions,
    [switch]$RemoveVault,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProfileRoot = [IO.Path]::GetFullPath($ProfileRoot)
$expectedCopilotRoot = [IO.Path]::GetFullPath($(if ($CopilotRoot) { $CopilotRoot } else { Join-Path $ProfileRoot 'copilot' }))
$expectedCopilotCliRoot = [IO.Path]::GetFullPath($(if ($CopilotCliRoot) { $CopilotCliRoot } elseif ($env:COPILOT_HOME) { $env:COPILOT_HOME } else { Join-Path $HOME '.copilot' }))
$expectedVsCodeUser = [IO.Path]::GetFullPath($(if ($VsCodeUserDirectory) { $VsCodeUserDirectory } elseif ($env:OS -eq 'Windows_NT') { Join-Path $env:APPDATA 'Code\User' } elseif ([Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::OSX)) { Join-Path $HOME 'Library/Application Support/Code/User' } else { Join-Path $HOME '.config/Code/User' }))
$statePath = Join-Path $ProfileRoot 'state.json'

function Invoke-Mutation {
    param([string]$Description, [scriptblock]$Action)
    if ($DryRun) { Write-Host "[dry run] $Description"; return }
    & $Action
}

function Assert-NoReparsePath {
    param([string]$Path)
    $current = [IO.Path]::GetFullPath($Path)
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Refusing to modify path through symbolic link or junction: $current" }
        }
        $parent = Split-Path -Parent $current
        if (-not $parent -or $parent -eq $current) { break }
        $current = $parent
    }
}

Assert-NoReparsePath $ProfileRoot
Assert-NoReparsePath $statePath
if (-not (Test-Path -LiteralPath $statePath)) { throw "Assured Arc state not found: $statePath" }
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
$stateHashPath = $statePath + '.sha256'
if ($state.schema -ge 3) {
    Assert-NoReparsePath $stateHashPath
    if (-not (Test-Path -LiteralPath $stateHashPath)) { throw "Assured Arc state integrity file not found: $stateHashPath" }
    $expectedHash = (Get-Content -LiteralPath $stateHashPath -Raw).Trim().ToLowerInvariant()
    $actualHash = (Get-FileHash -LiteralPath $statePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($expectedHash -ne $actualHash) { throw 'Assured Arc state integrity validation failed. No managed paths were changed.' }
}

function Assert-OwnedAbsolutePath {
    param([string]$Path, [string]$Label)
    if (-not $Path) { return }
    if (-not [IO.Path]::IsPathRooted($Path)) { throw "$Label path is relative and cannot be trusted: $Path" }
    Assert-NoReparsePath ([IO.Path]::GetFullPath($Path))
}

function Test-PathWithin {
    param([string]$Path, [string]$Root)
    if (-not $Path -or -not $Root) { return $false }
    $candidate = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $owner = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    return [string]::Equals($candidate, $owner, [StringComparison]::OrdinalIgnoreCase) -or
        $candidate.StartsWith($owner + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Assert-ManagedTargetOwnership {
    param($Managed)
    $kind = [string]$Managed.kind
    $target = [string]$Managed.target
    $copilotKinds = @('skill', 'skill-registry', 'instruction', 'agent', 'prompt', 'agent-harness', 'tool-policy', 'hook-script', 'hook-config')
    if ($kind -in $copilotKinds) {
        if (-not (Test-PathWithin -Path $target -Root $expectedCopilotRoot)) { throw "Managed $kind target is outside the selected Copilot root: $target" }
        return
    }
    if ($kind -in @('cli-agent', 'cli-instruction', 'cli-hook-config')) {
        if (-not (Test-PathWithin -Path $target -Root $expectedCopilotCliRoot)) { throw "Managed $kind target is outside the selected Copilot CLI root: $target" }
        return
    }
    if ($kind -in @('mcp-runtime', 'mcp-template')) {
        if (-not (Test-PathWithin -Path $target -Root (Join-Path ([string]$state.profileRoot) 'mcp'))) { throw "Managed $kind target is outside the recorded MCP root: $target" }
        return
    }
    if ($kind -eq 'vault') {
        if (-not [string]::Equals([IO.Path]::GetFullPath($target), [IO.Path]::GetFullPath([string]$state.vaultPath), [StringComparison]::OrdinalIgnoreCase)) { throw "Managed vault target does not match recorded vault ownership: $target" }
        return
    }
    if ($kind -notin @('settings', 'mcp', 'cli-settings', 'cli-mcp')) { throw "Unknown managed target kind in state: $kind" }
}

function Assert-UninstallPlan {
    $recordedProfile = if ($state.PSObject.Properties.Name -contains 'profileRoot' -and $state.profileRoot) { [string]$state.profileRoot } else { $ProfileRoot }
    Assert-OwnedAbsolutePath -Path $recordedProfile -Label 'Profile root'
    if (-not [string]::Equals([IO.Path]::GetFullPath($recordedProfile), $ProfileRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'The recorded profile root does not match the requested profile.' }
    Assert-OwnedAbsolutePath -Path $expectedCopilotRoot -Label 'Selected Copilot root'
    if ($state.PSObject.Properties.Name -contains 'copilotRoot' -and $state.copilotRoot -and -not [string]::Equals([IO.Path]::GetFullPath([string]$state.copilotRoot), $expectedCopilotRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'The recorded Copilot root does not match the selected Copilot root.' }
    if ($state.PSObject.Properties.Name -contains 'settings') {
        Assert-OwnedAbsolutePath -Path ([string]$state.settings.target) -Label 'Settings ownership target'
        if (-not [string]::Equals([IO.Path]::GetFullPath([string]$state.settings.target), (Join-Path $expectedVsCodeUser 'settings.json'), [StringComparison]::OrdinalIgnoreCase)) { throw 'The settings ownership target does not match the selected VS Code user directory.' }
    }
    if ($state.PSObject.Properties.Name -contains 'mcp') {
        Assert-OwnedAbsolutePath -Path ([string]$state.mcp.target) -Label 'MCP ownership target'
        if ($state.mcp.target -and -not [string]::Equals([IO.Path]::GetFullPath([string]$state.mcp.target), (Join-Path $expectedVsCodeUser 'mcp.json'), [StringComparison]::OrdinalIgnoreCase)) { throw 'The MCP ownership target does not match the selected VS Code user directory.' }
    }
    if ($state.PSObject.Properties.Name -contains 'copilotCli' -and $state.copilotCli.enabled) {
        Assert-OwnedAbsolutePath -Path $expectedCopilotCliRoot -Label 'Selected Copilot CLI root'
        if ($state.copilotCli.root -and -not [string]::Equals([IO.Path]::GetFullPath([string]$state.copilotCli.root), $expectedCopilotCliRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'The recorded Copilot CLI root does not match the selected Copilot CLI root.' }
        Assert-OwnedAbsolutePath -Path ([string]$state.copilotCli.settings.target) -Label 'Copilot CLI settings target'
        if ($state.copilotCli.settings.target -and -not [string]::Equals([IO.Path]::GetFullPath([string]$state.copilotCli.settings.target), (Join-Path $expectedCopilotCliRoot 'settings.json'), [StringComparison]::OrdinalIgnoreCase)) { throw 'The Copilot CLI settings target does not match the selected CLI root.' }
        Assert-OwnedAbsolutePath -Path ([string]$state.copilotCli.mcp.target) -Label 'Copilot CLI MCP target'
        if ($state.copilotCli.mcp.target -and -not [string]::Equals([IO.Path]::GetFullPath([string]$state.copilotCli.mcp.target), (Join-Path $expectedCopilotCliRoot 'mcp-config.json'), [StringComparison]::OrdinalIgnoreCase)) { throw 'The Copilot CLI MCP target does not match the selected CLI root.' }
    }
    foreach ($managed in @($state.managed)) {
        Assert-ManagedTargetOwnership -Managed $managed
        if ($managed.kind -in @('settings', 'mcp', 'cli-settings', 'cli-mcp')) { continue }
        if ($managed.kind -eq 'vault' -and -not $RemoveVault) { continue }
        Assert-OwnedAbsolutePath -Path ([string]$managed.target) -Label 'Managed target'
    }
    if ($RemoveVault -and $state.vaultPath) { Assert-OwnedAbsolutePath -Path ([string]$state.vaultPath) -Label 'Recorded vault' }
    if ($RestoreBackups) {
        foreach ($backup in @($state.backups)) {
            Assert-OwnedAbsolutePath -Path ([string]$backup.target) -Label 'Backup target'
            Assert-OwnedAbsolutePath -Path ([string]$backup.backup) -Label 'Backup source'
            if (-not (Test-PathWithin -Path ([string]$backup.backup) -Root (Join-Path $recordedProfile 'backups'))) { throw "Backup source is outside the recorded backup root: $($backup.backup)" }
            $knownTarget = [string]::Equals([IO.Path]::GetFullPath([string]$backup.target), [IO.Path]::GetFullPath([string]$state.settings.target), [StringComparison]::OrdinalIgnoreCase) -or
                ($state.mcp.target -and [string]::Equals([IO.Path]::GetFullPath([string]$backup.target), [IO.Path]::GetFullPath([string]$state.mcp.target), [StringComparison]::OrdinalIgnoreCase)) -or
                ($state.PSObject.Properties.Name -contains 'copilotCli' -and $state.copilotCli.settings.target -and [string]::Equals([IO.Path]::GetFullPath([string]$backup.target), [IO.Path]::GetFullPath([string]$state.copilotCli.settings.target), [StringComparison]::OrdinalIgnoreCase)) -or
                ($state.PSObject.Properties.Name -contains 'copilotCli' -and $state.copilotCli.mcp.target -and [string]::Equals([IO.Path]::GetFullPath([string]$backup.target), [IO.Path]::GetFullPath([string]$state.copilotCli.mcp.target), [StringComparison]::OrdinalIgnoreCase)) -or
                (@($state.managed | Where-Object { [string]::Equals([IO.Path]::GetFullPath([string]$_.target), [IO.Path]::GetFullPath([string]$backup.target), [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0)
            if (-not $knownTarget) { throw "Backup target is not owned by this installer state: $($backup.target)" }
        }
    }
}

Assert-UninstallPlan

function Convert-JsonCToJson {
    param([string]$Text)
    $output = [Text.StringBuilder]::new()
    $inString = $false
    $escaped = $false
    $lineComment = $false
    $blockComment = $false
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $character = $Text[$i]
        $next = if ($i + 1 -lt $Text.Length) { $Text[$i + 1] } else { [char]0 }
        if ($lineComment) {
            if ($character -eq "`n" -or $character -eq "`r") { $lineComment = $false; [void]$output.Append($character) }
            continue
        }
        if ($blockComment) {
            if ($character -eq [char]'*' -and $next -eq [char]'/') { $blockComment = $false; $i++ }
            continue
        }
        if ($inString) {
            [void]$output.Append($character)
            if ($escaped) { $escaped = $false }
            elseif ($character -eq [char]'\') { $escaped = $true }
            elseif ($character -eq [char]'"') { $inString = $false }
            continue
        }
        if ($character -eq [char]'"') { $inString = $true; [void]$output.Append($character) }
        elseif ($character -eq [char]'/' -and $next -eq [char]'/') { $lineComment = $true; $i++ }
        elseif ($character -eq [char]'/' -and $next -eq [char]'*') { $blockComment = $true; $i++ }
        else { [void]$output.Append($character) }
    }
    $result = $output.ToString()
    $withoutTrailingCommas = [Text.StringBuilder]::new()
    $inString = $false
    $escaped = $false
    for ($i = 0; $i -lt $result.Length; $i++) {
        $character = $result[$i]
        if ($inString) {
            [void]$withoutTrailingCommas.Append($character)
            if ($escaped) { $escaped = $false }
            elseif ($character -eq [char]'\') { $escaped = $true }
            elseif ($character -eq [char]'"') { $inString = $false }
            continue
        }
        if ($character -eq [char]'"') { $inString = $true; [void]$withoutTrailingCommas.Append($character); continue }
        if ($character -eq [char]',') {
            $cursor = $i + 1
            while ($cursor -lt $result.Length -and [char]::IsWhiteSpace($result[$cursor])) { $cursor++ }
            if ($cursor -lt $result.Length -and ($result[$cursor] -eq [char]'}' -or $result[$cursor] -eq [char]']')) { continue }
        }
        [void]$withoutTrailingCommas.Append($character)
    }
    return $withoutTrailingCommas.ToString()
}

function Restore-Backup {
    param($Backup)
    if (-not (Test-Path -LiteralPath $Backup.backup)) { Write-Warning "Backup missing: $($Backup.backup)"; return }
    Assert-NoReparsePath $Backup.target
    Assert-NoReparsePath $Backup.backup
    Invoke-Mutation "Restore $($Backup.target) from backup" {
        if (Test-Path -LiteralPath $Backup.target) { Remove-Item -LiteralPath $Backup.target -Recurse -Force }
        $parent = Split-Path -Parent $Backup.target
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Copy-Item -LiteralPath $Backup.backup -Destination $Backup.target -Recurse -Force
    }
}

function Remove-ManagedSettingEntries {
    if (-not ($state.PSObject.Properties.Name -contains 'settings') -or -not $state.settings.target -or -not (Test-Path -LiteralPath $state.settings.target)) { return }
    Assert-NoReparsePath $state.settings.target
    Invoke-Mutation "Remove package-owned customization locations from $($state.settings.target)" {
        try {
            $text = Get-Content -LiteralPath $state.settings.target -Raw
            $config = Convert-JsonCToJson $text | ConvertFrom-Json
        }
        catch {
            throw "Cannot safely remove managed settings locations from malformed JSON: $($state.settings.target). Package assets and state were preserved. $($_.Exception.Message)"
        }
        foreach ($entry in @($state.settings.locationEntries)) {
            if ($entry.PSObject.Properties.Name -contains 'added' -and -not [bool]$entry.added) { continue }
            $setting = $config.PSObject.Properties[[string]$entry.setting]
            if ($setting -and $setting.Value) {
                [void]$setting.Value.PSObject.Properties.Remove([string]$entry.path)
            }
        }
        $json = $config | ConvertTo-Json -Depth 20
        [IO.File]::WriteAllText($state.settings.target, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    }
}

function Remove-ManagedMcpEntries {
    if (-not ($state.PSObject.Properties.Name -contains 'mcp') -or -not $state.mcp.target -or -not (Test-Path -LiteralPath $state.mcp.target)) { return }
    Assert-NoReparsePath $state.mcp.target
    Invoke-Mutation "Remove package-owned MCP entries from $($state.mcp.target)" {
        try {
            $text = Get-Content -LiteralPath $state.mcp.target -Raw
            $config = Convert-JsonCToJson $text | ConvertFrom-Json
        }
        catch {
            throw "Cannot safely remove managed MCP entries from malformed JSON: $($state.mcp.target). Managed MCP runtime and state were preserved. $($_.Exception.Message)"
        }
        if ($config.servers) {
            foreach ($id in @($state.mcp.serverIds)) { [void]$config.servers.PSObject.Properties.Remove([string]$id) }
        }
        if ($config.inputs) {
            $managedInputIds = @($state.mcp.inputIds)
            $config.inputs = @($config.inputs | Where-Object { $managedInputIds -notcontains $_.id })
        }
        $json = $config | ConvertTo-Json -Depth 20
        [IO.File]::WriteAllText($state.mcp.target, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    }
}

function Remove-ManagedCopilotCliEntries {
    if (-not ($state.PSObject.Properties.Name -contains 'copilotCli') -or -not $state.copilotCli.enabled) { return }
    $settings = $state.copilotCli.settings
    if ($settings.target -and (Test-Path -LiteralPath $settings.target)) {
        Assert-NoReparsePath $settings.target
        Invoke-Mutation "Remove package-owned skill directory from $($settings.target)" {
            try {
                $text = Get-Content -LiteralPath $settings.target -Raw
                $config = Convert-JsonCToJson $text | ConvertFrom-Json
            }
            catch { throw "Cannot safely remove managed Copilot CLI settings from malformed JSON: $($settings.target). Package assets and state were preserved. $($_.Exception.Message)" }
            $removed = @($settings.skillDirectoryEntries | Where-Object { -not ($_.PSObject.Properties.Name -contains 'added') -or [bool]$_.added } | ForEach-Object { [IO.Path]::GetFullPath([string]$_.path) })
            if ($config.PSObject.Properties.Name -contains 'skillDirectories') {
                $config.skillDirectories = @($config.skillDirectories | Where-Object { $candidate = [IO.Path]::GetFullPath([string]$_); -not @($removed | Where-Object { [string]::Equals($_, $candidate, [StringComparison]::OrdinalIgnoreCase) }).Count })
            }
            $json = $config | ConvertTo-Json -Depth 20
            [IO.File]::WriteAllText($settings.target, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
        }
    }
    $mcp = $state.copilotCli.mcp
    if ($mcp.target -and (Test-Path -LiteralPath $mcp.target)) {
        Assert-NoReparsePath $mcp.target
        Invoke-Mutation "Remove package-owned MCP entries from $($mcp.target)" {
            try {
                $text = Get-Content -LiteralPath $mcp.target -Raw
                $config = Convert-JsonCToJson $text | ConvertFrom-Json
            }
            catch { throw "Cannot safely remove managed Copilot CLI MCP entries from malformed JSON: $($mcp.target). Package assets and state were preserved. $($_.Exception.Message)" }
            if ($config.mcpServers) {
                foreach ($id in @($mcp.serverIds)) { [void]$config.mcpServers.PSObject.Properties.Remove([string]$id) }
            }
            $json = $config | ConvertTo-Json -Depth 20
            [IO.File]::WriteAllText($mcp.target, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
        }
    }
}

if (-not $RestoreBackups) {
    Remove-ManagedSettingEntries
    Remove-ManagedMcpEntries
    Remove-ManagedCopilotCliEntries
}

Write-Host 'Removing package-managed agents, skills, and instructions.'
foreach ($managed in $state.managed) {
    if ($managed.kind -in @('settings', 'mcp', 'cli-settings', 'cli-mcp')) { continue }
    if ($managed.kind -eq 'vault' -and -not $RemoveVault) { continue }
    Assert-NoReparsePath $managed.target
    Invoke-Mutation "Remove $($managed.target)" {
        if (Test-Path -LiteralPath $managed.target) { Remove-Item -LiteralPath $managed.target -Recurse -Force }
    }
}

if ($RemoveVault) {
    $recordedVault = [string]$state.vaultPath
    if ($recordedVault -and (Test-Path -LiteralPath $recordedVault)) {
        Assert-NoReparsePath $recordedVault
        Invoke-Mutation "Remove recorded vault $recordedVault" { Remove-Item -LiteralPath $recordedVault -Recurse -Force }
    }
}

if ($RestoreBackups) {
    $backups = @($state.backups)
    [array]::Reverse($backups)
    foreach ($backup in $backups) { Restore-Backup $backup }
}
else {
    Write-Host 'Existing VS Code and Copilot CLI settings and unrelated MCP entries were preserved. Package-owned entries were removed.'
}

if ($RemoveExtensions) {
    $code = (Get-Command $CodeCommand -ErrorAction SilentlyContinue).Source
    if (-not $code) { Write-Warning "Cannot find '$CodeCommand'; extension uninstall skipped." }
    else {
        foreach ($extension in $state.extensions) {
            Invoke-Mutation "Uninstall extension $extension" { & $code '--uninstall-extension' $extension }
        }
    }
}

if (-not $DryRun) {
    Assert-NoReparsePath $statePath
    Remove-Item -LiteralPath $statePath -Force
    if (Test-Path -LiteralPath $stateHashPath) { Remove-Item -LiteralPath $stateHashPath -Force }
    Write-Host "Removed state file: $statePath"
}
Write-Host 'Uninstall completed.'
