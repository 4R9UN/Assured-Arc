<#
.SYNOPSIS
    Install Assured Arc on Windows.

.DESCRIPTION
    Creates a managed profile, backs up affected VS Code and optional Copilot CLI
    configuration, installs selected extensions, copies public agents, skills,
    instructions, and hooks, creates an optional Obsidian vault template, and
    writes state for uninstall or rollback.

    The script never sends telemetry, publishes a repository, or writes secrets.
    The reviewed Context7, Sequential Thinking, and arXiv MCP profile is enabled
    by default through the package configuration and can be skipped explicitly.
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

$script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$script:StatePath = Join-Path $ProfileRoot 'state.json'
$script:BackupRoot = Join-Path $ProfileRoot ('backups' + [IO.Path]::DirectorySeparatorChar + (Get-Date -Format 'yyyyMMdd-HHmmss-fffffff'))
$script:State = [ordered]@{
    schema = 4
    createdAt = (Get-Date).ToUniversalTime().ToString('o')
    updatedAt = (Get-Date).ToUniversalTime().ToString('o')
    repositoryRoot = $script:RepoRoot
    profileRoot = $ProfileRoot
    vscodeUserDirectory = ''
    copilotRoot = ''
    vaultPath = ''
    backups = [System.Collections.ArrayList]@()
    created = [System.Collections.ArrayList]@()
    managed = [System.Collections.ArrayList]@()
    extensions = [System.Collections.ArrayList]@()
    settings = [ordered]@{
        target = ''
        locationEntries = [System.Collections.ArrayList]@()
    }
    mcp = [ordered]@{
        target = ''
        serverIds = [System.Collections.ArrayList]@()
        inputIds = [System.Collections.ArrayList]@()
    }
    copilotCli = [ordered]@{
        enabled = $false
        root = ''
        settings = [ordered]@{
            target = ''
            skillDirectoryEntries = [System.Collections.ArrayList]@()
        }
        mcp = [ordered]@{
            target = ''
            serverIds = [System.Collections.ArrayList]@()
        }
    }
}
$script:BackedUp = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$script:TransactionBackedUp = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$script:TransactionBackups = [System.Collections.ArrayList]@()
$script:TransactionCreated = [System.Collections.ArrayList]@()
$script:TransactionExtensions = [System.Collections.ArrayList]@()
$script:Step = 0
$script:TotalSteps = 9

function Write-Step {
    param([string]$Message)
    $script:Step++
    Write-Progress -Activity 'Assured Arc' -Status $Message -PercentComplete ([math]::Min(100, [int](100 * $script:Step / $script:TotalSteps)))
    Write-Host "[$script:Step/$script:TotalSteps] $Message"
}

function Invoke-Mutation {
    param([string]$Description, [scriptblock]$Action)
    if ($DryRun) {
        Write-Host "[dry run] $Description"
        return
    }
    & $Action
}

function Get-Platform {
    if ($env:OS -eq 'Windows_NT') { return 'windows' }
    if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX)) { return 'macos' }
    return 'linux'
}

function Get-VsCodeUserDirectory {
    switch (Get-Platform) {
        'windows' { return (Join-Path $env:APPDATA 'Code\User') }
        'macos' { return (Join-Path $HOME 'Library/Application Support/Code/User') }
        default { return (Join-Path $HOME '.config/Code/User') }
    }
}

function Resolve-CodeCommand {
    param([string]$Requested)
    $found = Get-Command $Requested -ErrorAction SilentlyContinue
    if ($found) { return $found.Source }
    if ((Get-Platform) -eq 'windows') {
        $candidates = @(
            (Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\bin\code.cmd'),
            (Join-Path $env:ProgramFiles 'Microsoft VS Code\bin\code.cmd')
        )
        foreach ($candidate in $candidates) { if (Test-Path $candidate) { return $candidate } }
    }
    return $null
}

function ConvertTo-Hashtable {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [string] -or $Value.GetType().IsPrimitive -or $Value -is [decimal] -or $Value -is [datetime]) { return $Value }
    if ($Value -is [System.Collections.IDictionary]) {
        $table = [ordered]@{}
        foreach ($key in $Value.Keys) { $table[$key] = ConvertTo-Hashtable $Value[$key] }
        return $table
    }
    if ($Value -is [pscustomobject]) {
        $table = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) { $table[$property.Name] = ConvertTo-Hashtable $property.Value }
        return $table
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        return @($Value | ForEach-Object { ConvertTo-Hashtable $_ })
    }
    return $Value
}

function Convert-JsonCToJson {
    param([string]$Text)
    $withoutComments = [Text.StringBuilder]::new()
    $inString = $false
    $escaped = $false
    $lineComment = $false
    $blockComment = $false
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $character = $Text[$i]
        $next = if ($i + 1 -lt $Text.Length) { $Text[$i + 1] } else { [char]0 }
        if ($lineComment) {
            if ($character -eq "`n" -or $character -eq "`r") {
                $lineComment = $false
                [void]$withoutComments.Append($character)
            }
            continue
        }
        if ($blockComment) {
            if ($character -eq [char]'*' -and $next -eq [char]'/' ) {
                $blockComment = $false
                $i++
            }
            continue
        }
        if ($inString) {
            [void]$withoutComments.Append($character)
            if ($escaped) { $escaped = $false }
            elseif ($character -eq [char]'\') { $escaped = $true }
            elseif ($character -eq [char]'"') { $inString = $false }
            continue
        }
        if ($character -eq [char]'"') {
            $inString = $true
            [void]$withoutComments.Append($character)
        }
        elseif ($character -eq [char]'/' -and $next -eq [char]'/' ) {
            $lineComment = $true
            $i++
        }
        elseif ($character -eq [char]'/' -and $next -eq [char]'*' ) {
            $blockComment = $true
            $i++
        }
        else {
            [void]$withoutComments.Append($character)
        }
    }

    $result = $withoutComments.ToString()
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
        if ($character -eq [char]'"') {
            $inString = $true
            [void]$withoutTrailingCommas.Append($character)
            continue
        }
        if ($character -eq [char]',') {
            $cursor = $i + 1
            while ($cursor -lt $result.Length -and [char]::IsWhiteSpace($result[$cursor])) { $cursor++ }
            if ($cursor -lt $result.Length -and ($result[$cursor] -eq [char]'}' -or $result[$cursor] -eq [char]']')) { continue }
        }
        [void]$withoutTrailingCommas.Append($character)
    }
    return $withoutTrailingCommas.ToString()
}

function Read-JsonC {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return [ordered]@{} }
    $text = [IO.File]::ReadAllText($Path)
    $text = Convert-JsonCToJson $text
    if ([string]::IsNullOrWhiteSpace($text)) { return [ordered]@{} }
    return ConvertTo-Hashtable ($text | ConvertFrom-Json)
}

function Merge-Defaults {
    param([System.Collections.IDictionary]$Existing, [System.Collections.IDictionary]$Defaults, [switch]$ReplaceValues)
    foreach ($key in $Defaults.Keys) {
        if (-not $Existing.Contains($key)) {
            $Existing[$key] = $Defaults[$key]
            continue
        }
        if ($Existing[$key] -is [System.Collections.IDictionary] -and $Defaults[$key] -is [System.Collections.IDictionary]) {
            Merge-Defaults -Existing $Existing[$key] -Defaults $Defaults[$key] -ReplaceValues:$ReplaceValues
        }
        elseif ($ReplaceValues) {
            $Existing[$key] = $Defaults[$key]
        }
    }
}

function Write-Json {
    param([string]$Path, $Value)
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $json = $Value | ConvertTo-Json -Depth 20
    $temporary = Join-Path $directory ('.' + [IO.Path]::GetFileName($Path) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
    $replacementBackup = $temporary + '.previous'
    try {
        [IO.File]::WriteAllText($temporary, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
        if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($temporary, $Path, $replacementBackup, $true) }
        else { [IO.File]::Move($temporary, $Path) }
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $replacementBackup) { Remove-Item -LiteralPath $replacementBackup -Force -ErrorAction SilentlyContinue }
    }
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

function Assert-InstallPlanPaths {
    param([string]$VsCodeUser, [string]$CopilotProfile, [string]$CopilotCliProfile, [string]$Vault, [string]$Profile)
    $targets = [System.Collections.ArrayList]@(
        $Profile,
        $script:StatePath,
        $script:BackupRoot,
        $VsCodeUser,
        (Join-Path $VsCodeUser 'settings.json'),
        (Join-Path $VsCodeUser 'mcp.json'),
        $CopilotProfile,
        (Join-Path $CopilotProfile 'skill-registry.json'),
        (Join-Path $CopilotProfile 'agent-harness.json'),
        (Join-Path $CopilotProfile 'tool-policy.json'),
        (Join-Path $CopilotProfile 'hooks\agent-harness.json'),
        (Join-Path $CopilotProfile 'hooks\harness-event.ps1'),
        (Join-Path $CopilotProfile 'hooks\harness_event.py'),
        (Join-Path $CopilotProfile 'hooks\scoreboard.py'),
        (Join-Path $CopilotProfile 'scoreboard.json'),
        (Join-Path $CopilotProfile 'checks\approved_check.py'),
        (Join-Path $Profile 'claude'),
        (Join-Path $Profile 'claude\settings.json'),
        (Join-Path $Profile 'claude\agent-contract.json')
    )
    Get-ChildItem (Join-Path $script:RepoRoot '.github\skills') -Directory | ForEach-Object {
        $targets.Add((Join-Path $CopilotProfile ('skills' + [IO.Path]::DirectorySeparatorChar + $_.Name))) | Out-Null
    }
    $instructionManifest = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'config\instructions.json') -Raw | ConvertFrom-Json
    foreach ($instructionName in @($instructionManifest.instructions)) {
        $targets.Add((Join-Path $CopilotProfile ('instructions' + [IO.Path]::DirectorySeparatorChar + $instructionName))) | Out-Null
    }
    Get-ChildItem (Join-Path $script:RepoRoot '.github\agents') -Filter '*.agent.md' -File | ForEach-Object {
        $targets.Add((Join-Path $CopilotProfile ('agents' + [IO.Path]::DirectorySeparatorChar + $_.Name))) | Out-Null
    }
    Get-ChildItem (Join-Path $script:RepoRoot '.github\prompts') -Filter '*.prompt.md' -File | ForEach-Object {
        $targets.Add((Join-Path $CopilotProfile ('prompts' + [IO.Path]::DirectorySeparatorChar + $_.Name))) | Out-Null
    }
    foreach ($role in @('orchestrator', 'scout', 'researcher', 'implementer', 'verifier', 'critic')) {
        $targets.Add((Join-Path $Profile ('claude\agents\assured-arc-' + $role + '.md'))) | Out-Null
    }
    if ($InstallCopilotCli) {
        $targets.Add($CopilotCliProfile) | Out-Null
        $targets.Add((Join-Path $CopilotCliProfile 'settings.json')) | Out-Null
        $targets.Add((Join-Path $CopilotCliProfile 'mcp-config.json')) | Out-Null
        $targets.Add((Join-Path $CopilotCliProfile 'hooks\assured-arc.json')) | Out-Null
        foreach ($instructionName in @($instructionManifest.instructions)) {
            $targets.Add((Join-Path $CopilotCliProfile ('instructions' + [IO.Path]::DirectorySeparatorChar + $instructionName))) | Out-Null
        }
        Get-ChildItem (Join-Path $script:RepoRoot '.github\agents') -Filter '*.agent.md' -File | ForEach-Object {
            $targets.Add((Join-Path $CopilotCliProfile ('agents' + [IO.Path]::DirectorySeparatorChar + $_.Name))) | Out-Null
        }
    }
    if ($InstallMcp) {
        $mcpManifest = Read-JsonC (Join-Path $script:RepoRoot 'config\mcp-servers.json')
        $arxivVersion = [string](@($mcpManifest['servers'] | Where-Object { $_['id'] -eq 'arxiv' })[0]['version'])
        $targets.Add((Join-Path $Profile "mcp\arxiv-$arxivVersion")) | Out-Null
    }
    else {
        $targets.Add((Join-Path $Profile 'mcp\mcp.json.example')) | Out-Null
    }
    if (-not $SkipVault) {
        $targets.Add($Vault) | Out-Null
        Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'vault-template') -Recurse -File | ForEach-Object {
            $relative = $_.FullName.Substring((Join-Path $script:RepoRoot 'vault-template').Length).TrimStart('\', '/')
            $targets.Add((Join-Path $Vault $relative)) | Out-Null
        }
        $targets.Add((Join-Path $Vault 'assured-arc.code-workspace')) | Out-Null
    }
    foreach ($target in @($targets | Select-Object -Unique)) { Assert-NoReparsePath ([IO.Path]::GetFullPath($target)) }
}

function Backup-Item {
    param([string]$Path)
    Assert-NoReparsePath $Path
    if (-not (Test-Path -LiteralPath $Path) -or $script:TransactionBackedUp.Contains($Path)) { return }
    if ($DryRun -or $NoBackup) { return }
    $script:TransactionBackedUp.Add($Path) | Out-Null
    $leaf = Split-Path -Leaf $Path
    $backup = Join-Path $script:BackupRoot (([guid]::NewGuid().ToString('N')) + '-' + $leaf)
    $backupParent = Split-Path -Parent $backup
    if (-not (Test-Path -LiteralPath $backupParent)) { New-Item -ItemType Directory -Path $backupParent -Force | Out-Null }
    Copy-Item -LiteralPath $Path -Destination $backup -Recurse -Force
    $entry = [ordered]@{ target = $Path; backup = $backup }
    $script:TransactionBackups.Add($entry) | Out-Null
    if (-not $script:BackedUp.Contains($Path) -and $script:State.created -notcontains $Path) {
        $script:BackedUp.Add($Path) | Out-Null
        $script:State.backups.Add($entry) | Out-Null
    }
}

function Register-Created {
    param([string]$Path)
    if (-not ($script:State.created -contains $Path)) {
        $script:State.created.Add($Path) | Out-Null
        $script:TransactionCreated.Add($Path) | Out-Null
    }
}

function Register-Managed {
    param([string]$Kind, [string]$Target)
    $exists = $script:State.managed | Where-Object { $_['kind'] -eq $Kind -and $_['target'] -eq $Target }
    if (-not $exists) { $script:State.managed.Add([ordered]@{ kind = $Kind; target = $Target }) | Out-Null }
}

function Register-SettingLocation {
    param([string]$Setting, [string]$Path, [bool]$Added = $true)
    $exists = $script:State.settings.locationEntries | Where-Object { $_['setting'] -eq $Setting -and $_['path'] -eq $Path }
    if (-not $exists) {
        $script:State.settings.locationEntries.Add([ordered]@{ setting = $Setting; path = $Path; added = $Added }) | Out-Null
    }
}

function Register-CopilotCliSkillDirectory {
    param([string]$Path, [bool]$Added = $true)
    $exists = $script:State.copilotCli.settings.skillDirectoryEntries | Where-Object { $_['path'] -eq $Path }
    if (-not $exists) {
        $script:State.copilotCli.settings.skillDirectoryEntries.Add([ordered]@{ path = $Path; added = $Added }) | Out-Null
    }
}

function Import-PreviousState {
    if (-not (Test-Path -LiteralPath $script:StatePath)) { return }
    $previous = Get-Content -LiteralPath $script:StatePath -Raw | ConvertFrom-Json
    if ($previous.schema -ge 3) {
        $hashPath = $script:StatePath + '.sha256'
        Assert-NoReparsePath $hashPath
        if (-not (Test-Path -LiteralPath $hashPath)) { throw "Assured Arc state integrity file not found: $hashPath" }
        $expectedHash = (Get-Content -LiteralPath $hashPath -Raw).Trim().ToLowerInvariant()
        $actualHash = (Get-FileHash -LiteralPath $script:StatePath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($expectedHash -ne $actualHash) { throw 'Assured Arc state integrity validation failed. No prior ownership was imported.' }
    }
    foreach ($pair in @(
        @('profileRoot', $ProfileRoot),
        @('copilotRoot', $script:State.copilotRoot),
        @('vscodeUserDirectory', $script:State.vscodeUserDirectory),
        @('vaultPath', $script:State.vaultPath)
    )) {
        $name = [string]$pair[0]
        $requested = [string]$pair[1]
        if ($previous.PSObject.Properties.Name -contains $name -and $previous.$name -and -not [string]::Equals([IO.Path]::GetFullPath([string]$previous.$name), [IO.Path]::GetFullPath($requested), [StringComparison]::OrdinalIgnoreCase)) {
            throw "This profile cannot migrate $name. Uninstall the existing profile first."
        }
    }
    if ($previous.createdAt) { $script:State.createdAt = $previous.createdAt }
    $script:State.updatedAt = (Get-Date).ToUniversalTime().ToString('o')
    foreach ($item in @($previous.backups)) {
        $entry = ConvertTo-Hashtable $item
        $script:State.backups.Add($entry) | Out-Null
        [void]$script:BackedUp.Add($entry['target'])
    }
    foreach ($path in @($previous.created)) {
        if (-not ($script:State.created -contains $path)) { $script:State.created.Add([string]$path) | Out-Null }
    }
    foreach ($item in @($previous.managed)) {
        $entry = ConvertTo-Hashtable $item
        Register-Managed -Kind $entry['kind'] -Target $entry['target']
    }
    foreach ($extension in @($previous.extensions)) {
        if (-not ($script:State.extensions -contains $extension)) { $script:State.extensions.Add($extension) | Out-Null }
    }
    if ($previous.PSObject.Properties.Name -contains 'settings') {
        $script:State.settings.target = [string]$previous.settings.target
        foreach ($entry in @($previous.settings.locationEntries)) {
            $added = if ($entry.PSObject.Properties.Name -contains 'added') { [bool]$entry.added } else { $true }
            Register-SettingLocation -Setting ([string]$entry.setting) -Path ([string]$entry.path) -Added $added
        }
    }
    if ($previous.PSObject.Properties.Name -contains 'mcp') {
        $script:State.mcp.target = [string]$previous.mcp.target
        foreach ($id in @($previous.mcp.serverIds)) {
            if (-not ($script:State.mcp.serverIds -contains $id)) { $script:State.mcp.serverIds.Add([string]$id) | Out-Null }
        }
        foreach ($id in @($previous.mcp.inputIds)) {
            if (-not ($script:State.mcp.inputIds -contains $id)) { $script:State.mcp.inputIds.Add([string]$id) | Out-Null }
        }
    }
    if ($previous.PSObject.Properties.Name -contains 'copilotCli') {
        $script:State.copilotCli.enabled = [bool]$previous.copilotCli.enabled
        if ($previous.copilotCli.enabled) {
            $script:InstallCopilotCli = $true
            $savedRoot = [string]$previous.copilotCli.root
            if ($savedRoot -and -not [string]::Equals([IO.Path]::GetFullPath($savedRoot), [IO.Path]::GetFullPath([string]$script:State.copilotCli.root), [StringComparison]::OrdinalIgnoreCase)) {
                throw 'This profile cannot migrate the Copilot CLI root. Uninstall the existing profile first.'
            }
        }
        $script:State.copilotCli.root = [string]$previous.copilotCli.root
        if ($previous.copilotCli.PSObject.Properties.Name -contains 'settings') {
            $script:State.copilotCli.settings.target = [string]$previous.copilotCli.settings.target
            foreach ($entry in @($previous.copilotCli.settings.skillDirectoryEntries)) {
                $added = if ($entry.PSObject.Properties.Name -contains 'added') { [bool]$entry.added } else { $true }
                Register-CopilotCliSkillDirectory -Path ([string]$entry.path) -Added $added
            }
        }
        if ($previous.copilotCli.PSObject.Properties.Name -contains 'mcp') {
            $script:State.copilotCli.mcp.target = [string]$previous.copilotCli.mcp.target
            foreach ($id in @($previous.copilotCli.mcp.serverIds)) {
                if (-not ($script:State.copilotCli.mcp.serverIds -contains $id)) { $script:State.copilotCli.mcp.serverIds.Add([string]$id) | Out-Null }
            }
        }
    }
}

function Copy-ManagedDirectory {
    param([string]$Source, [string]$Destination, [string]$Kind)
    if (-not (Test-Path -LiteralPath $Source)) { throw "Package source missing: $Source" }
    Assert-NoReparsePath $Destination
    if (Test-Path -LiteralPath $Destination) { Backup-Item $Destination } else { Register-Created $Destination }
    Invoke-Mutation "Copy $Kind to $Destination" {
        $parent = Split-Path -Parent $Destination
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Recurse -Force }
        Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force
    }
    Register-Managed -Kind $Kind -Target $Destination
}

function Copy-ManagedFile {
    param([string]$Source, [string]$Destination, [string]$Kind)
    if (-not (Test-Path -LiteralPath $Source)) { throw "Package source missing: $Source" }
    Assert-NoReparsePath $Destination
    if (Test-Path -LiteralPath $Destination) { Backup-Item $Destination } else { Register-Created $Destination }
    Invoke-Mutation "Copy $Kind to $Destination" {
        $parent = Split-Path -Parent $Destination
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
    }
    Register-Managed -Kind $Kind -Target $Destination
}

function Copy-TemplateIfMissing {
    param([string]$Source, [string]$Destination)
    Get-ChildItem -LiteralPath $Source -Recurse -File | ForEach-Object {
        $relative = $_.FullName.Substring($Source.Length).TrimStart('\', '/')
        $target = Join-Path $Destination $relative
        Assert-NoReparsePath $target
        if (-not (Test-Path -LiteralPath $target)) {
            Register-Created $target
            Invoke-Mutation "Create vault template file $target" {
                $parent = Split-Path -Parent $target
                if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
                Copy-Item -LiteralPath $_.FullName -Destination $target -Force
            }
        }
    }
}

function Update-Settings {
    param([string]$Target, [string]$Template, [string]$CustomizationRoot, [string]$AgentRoot)
    Assert-NoReparsePath $Target
    if (-not (Test-Path -LiteralPath $Target)) { Register-Created $Target }
    $existing = Read-JsonC $Target
    $defaults = Read-JsonC $Template
    if (-not $AgentRoot) { $AgentRoot = Join-Path $CustomizationRoot 'agents' }
    $locations = [ordered]@{
        'chat.agentFilesLocations' = $AgentRoot
        'chat.promptFilesLocations' = (Join-Path $CustomizationRoot 'prompts')
        'chat.agentSkillsLocations' = (Join-Path $CustomizationRoot 'skills')
        'chat.instructionsFilesLocations' = (Join-Path $CustomizationRoot 'instructions')
        'chat.hookFilesLocations' = (Join-Path $CustomizationRoot 'hooks\agent-harness.json')
    }
    foreach ($setting in $locations.Keys) {
        $fullPath = [IO.Path]::GetFullPath($locations[$setting])
        $homePath = [IO.Path]::GetFullPath($HOME).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
        $homePrefix = $homePath + [IO.Path]::DirectorySeparatorChar
        $path = if ([string]::Equals($fullPath, $homePath, [StringComparison]::OrdinalIgnoreCase)) {
            '~/'
        }
        elseif ($fullPath.StartsWith($homePrefix, [StringComparison]::OrdinalIgnoreCase)) {
            '~/' + $fullPath.Substring($homePrefix.Length).Replace('\', '/')
        }
        else {
            $fullPath.Replace('\', '/')
        }
        if ($setting -eq 'chat.agentFilesLocations' -and $existing.Contains($setting) -and $existing[$setting] -is [System.Collections.IDictionary]) {
            foreach ($prior in @($script:State.settings.locationEntries | Where-Object { $_['setting'] -eq $setting -and $_['path'] -ne $path -and $_['added'] })) {
                [void]$existing[$setting].Remove([string]$prior['path'])
                [void]$script:State.settings.locationEntries.Remove($prior)
            }
        }
        if (-not $defaults.Contains($setting) -or $defaults[$setting] -isnot [System.Collections.IDictionary]) {
            $defaults[$setting] = [ordered]@{}
        }
        $defaults[$setting][$path] = $true
        $wasPresent = $existing.Contains($setting) -and $existing[$setting] -is [System.Collections.IDictionary] -and $existing[$setting].Contains($path)
        Register-SettingLocation -Setting $setting -Path $path -Added (-not $wasPresent)
    }
    $script:State.settings.target = [IO.Path]::GetFullPath($Target)
    Backup-Item $Target
    Merge-Defaults -Existing $existing -Defaults $defaults -ReplaceValues:$ForceSettings
    Invoke-Mutation "Merge VS Code settings into $Target" { Write-Json -Path $Target -Value $existing }
    Register-Managed -Kind 'settings' -Target $Target
}

function Copy-CopilotCliManagedFile {
    param([string]$Source, [string]$Destination, [string]$Kind)
    $owned = @($script:State.managed | Where-Object { $_['kind'] -eq $Kind -and [string]::Equals([string]$_['target'], $Destination, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
    if ((Test-Path -LiteralPath $Destination) -and -not $owned -and -not $ForceSettings) {
        throw "Copilot CLI file conflicts with an existing unmanaged file: $Destination. Rerun with -ForceSettings only after reviewing its contents."
    }
    Copy-ManagedFile -Source $Source -Destination $Destination -Kind $Kind
}

function Update-CopilotCliSettings {
    param([string]$Target, [string]$SkillsDirectory)
    $Target = [IO.Path]::GetFullPath($Target)
    $SkillsDirectory = [IO.Path]::GetFullPath($SkillsDirectory)
    Assert-NoReparsePath $Target
    if ($script:State.copilotCli.settings.target) {
        $savedTarget = [IO.Path]::GetFullPath([string]$script:State.copilotCli.settings.target)
        if (-not [string]::Equals($savedTarget, $Target, [StringComparison]::OrdinalIgnoreCase)) {
            throw "This profile owns Copilot CLI settings in $savedTarget and cannot migrate them to $Target. Uninstall the existing profile first."
        }
    }
    if (-not (Test-Path -LiteralPath $Target)) { Register-Created $Target }
    $existing = Read-JsonC $Target
    $directories = [System.Collections.ArrayList]@()
    if ($existing.Contains('skillDirectories')) {
        foreach ($item in @($existing['skillDirectories'])) { if ($item) { $directories.Add([string]$item) | Out-Null } }
    }
    $wasPresent = @($directories | Where-Object { [string]::Equals([IO.Path]::GetFullPath([string]$_), $SkillsDirectory, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
    Register-CopilotCliSkillDirectory -Path $SkillsDirectory -Added (-not $wasPresent)
    if (-not $wasPresent) { $directories.Add($SkillsDirectory) | Out-Null }
    $existing['skillDirectories'] = @($directories.ToArray())
    $script:State.copilotCli.settings.target = $Target
    Backup-Item $Target
    Invoke-Mutation "Register managed skills in Copilot CLI settings at $Target" { Write-Json -Path $Target -Value $existing }
    Register-Managed -Kind 'cli-settings' -Target $Target
}

function Install-CopilotCliProfile {
    param([string]$CliRoot, [string]$CopilotProfile, [string]$Profile)

    $script:State.copilotCli.enabled = $true
    $script:State.copilotCli.root = [IO.Path]::GetFullPath($CliRoot)
    Update-CopilotCliSettings -Target (Join-Path $CliRoot 'settings.json') -SkillsDirectory (Join-Path $CopilotProfile 'skills')

    $instructionManifest = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'config\instructions.json') -Raw | ConvertFrom-Json
    foreach ($instructionName in @($instructionManifest.instructions)) {
        $source = Join-Path (Join-Path $script:RepoRoot '.github\instructions') $instructionName
        $target = Join-Path $CliRoot ('instructions' + [IO.Path]::DirectorySeparatorChar + $instructionName)
        Copy-CopilotCliManagedFile -Source $source -Destination $target -Kind 'cli-instruction'
    }
    Get-ChildItem (Join-Path $script:RepoRoot '.github\agents') -Filter '*.agent.md' -File | ForEach-Object {
        $target = Join-Path $CliRoot ('agents' + [IO.Path]::DirectorySeparatorChar + $_.Name)
        Copy-CopilotCliManagedFile -Source $_.FullName -Destination $target -Kind 'cli-agent'
    }

    $hookTarget = Join-Path $CliRoot 'hooks\assured-arc.json'
    $hookConfig = Read-JsonC (Join-Path $script:RepoRoot '.github\hooks\copilot-cli-harness.json.example')
    $harnessTarget = Join-Path $CopilotProfile 'agent-harness.json'
    $toolPolicyTarget = Join-Path $CopilotProfile 'tool-policy.json'
    $powerShellTarget = Join-Path $CopilotProfile 'hooks\harness-event.ps1'
    $pythonTarget = Join-Path $CopilotProfile 'hooks\harness_event.py'
    $traceDirectory = Join-Path $Profile 'harness-runs'
    foreach ($eventName in @($hookConfig['hooks'].Keys)) {
        foreach ($hook in @($hookConfig['hooks'][$eventName])) {
            $hook['bash'] = "python3 `"$pythonTarget`""
            $hook['powershell'] = "pwsh -NoProfile -ExecutionPolicy Bypass -File `"$powerShellTarget`""
            $hook['env']['ASSURED_ARC_HARNESS_CONFIG'] = $harnessTarget
            $hook['env']['ASSURED_ARC_HARNESS_TRACE_DIR'] = $traceDirectory
            $hook['env']['ASSURED_ARC_HARNESS_TOOL_POLICY'] = $toolPolicyTarget
            $hook['env']['ASSURED_ARC_HARNESS_HOST'] = 'copilot-cli'
            $hook['env']['ASSURED_ARC_HARNESS_EVENT'] = $eventName
            $hook['env']['ASSURED_ARC_SCOREBOARD'] = (Join-Path $CopilotProfile 'scoreboard.json')
            $hook['env']['ASSURED_ARC_SCOREBOARD_SCRIPT'] = (Join-Path $CopilotProfile 'hooks\scoreboard.py')
            $hook['env']['ASSURED_ARC_SCOREBOARD_ROOT'] = [IO.Path]::GetFullPath($CopilotProfile)
        }
    }
    $owned = @($script:State.managed | Where-Object { $_['kind'] -eq 'cli-hook-config' -and [string]::Equals([string]$_['target'], $hookTarget, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
    if ((Test-Path -LiteralPath $hookTarget) -and -not $owned -and -not $ForceSettings) {
        throw "Copilot CLI hook conflicts with an existing unmanaged file: $hookTarget. Rerun with -ForceSettings only after reviewing its contents."
    }
    Assert-NoReparsePath $hookTarget
    if (Test-Path -LiteralPath $hookTarget) { Backup-Item $hookTarget } else { Register-Created $hookTarget }
    Invoke-Mutation "Write Copilot CLI harness hooks to $hookTarget" { Write-Json -Path $hookTarget -Value $hookConfig }
    Register-Managed -Kind 'cli-hook-config' -Target $hookTarget
}

function Install-AgentHarness {
    param([string]$CopilotProfile, [string]$Profile, [string]$CopilotCliProfile)

    $harnessTarget = Join-Path $CopilotProfile 'agent-harness.json'
    $harness = Read-JsonC (Join-Path $script:RepoRoot 'config\agent-harness.json')
    $registryTarget = [IO.Path]::GetFullPath((Join-Path $CopilotProfile 'skill-registry.json')).Replace('\', '/')
    $skillsTarget = [IO.Path]::GetFullPath((Join-Path $CopilotProfile 'skills')).Replace('\', '/')
    $harness['skillRouting']['catalogs'] = @('~/.copilot/skill-registry.json', $registryTarget)
    $harness['skillRouting']['fallbackLocations'] = @('~/.copilot/skills', $skillsTarget, '.github/skills', '.claude/skills')
    $protectedRoots = [System.Collections.ArrayList]@(
        [IO.Path]::GetFullPath($CopilotProfile).Replace('\', '/'),
        [IO.Path]::GetFullPath($Profile).Replace('\', '/')
    )
    if ($CopilotCliProfile) { $protectedRoots.Add([IO.Path]::GetFullPath($CopilotCliProfile).Replace('\', '/')) | Out-Null }
    $harness['protectedRoots'] = @($protectedRoots.ToArray())
    $toolPolicyTarget = Join-Path $CopilotProfile 'tool-policy.json'
    $harness['toolPolicy']['path'] = [IO.Path]::GetFullPath($toolPolicyTarget).Replace('\\', '/')
    Assert-NoReparsePath $harnessTarget
    if (Test-Path -LiteralPath $harnessTarget) { Backup-Item $harnessTarget } else { Register-Created $harnessTarget }
    Invoke-Mutation "Write agent harness policy to $harnessTarget" { Write-Json -Path $harnessTarget -Value $harness }
    if (-not $DryRun) {
        $renderedHarness = Get-Content -LiteralPath $harnessTarget -Raw | ConvertFrom-Json
        $expectedWorkers = @('Assured Arc Disposable Scout', 'Assured Arc Disposable Researcher', 'Assured Arc Disposable Implementer', 'Assured Arc Disposable Verifier', 'Assured Arc Disposable Critic')
        if ((@($renderedHarness.delegation.allowedWorkers) -join '|') -ne ($expectedWorkers -join '|')) { throw 'Rendered agent harness worker policy is corrupted.' }
        if ((@($renderedHarness.loop.phases) -join '|') -ne 'contract|route|delegate|act|verify|repair|complete') { throw 'Rendered agent harness loop policy is corrupted.' }
    }
    Register-Managed -Kind 'agent-harness' -Target $harnessTarget

    Copy-ManagedFile -Source (Join-Path $script:RepoRoot 'config\tool-policy.json') -Destination $toolPolicyTarget -Kind 'tool-policy'

    $hookDirectory = Join-Path $CopilotProfile 'hooks'
    $powerShellTarget = Join-Path $hookDirectory 'harness-event.ps1'
    $pythonTarget = Join-Path $hookDirectory 'harness_event.py'
    Copy-ManagedFile -Source (Join-Path $script:RepoRoot 'hooks\harness-event.ps1') -Destination $powerShellTarget -Kind 'hook-script'
    Copy-ManagedFile -Source (Join-Path $script:RepoRoot 'hooks\harness_event.py') -Destination $pythonTarget -Kind 'hook-script'
    $scoreboardTarget = Join-Path $CopilotProfile 'scoreboard.json'
    $scoreboardScript = Join-Path $hookDirectory 'scoreboard.py'
    $scoreboardCheck = Join-Path $CopilotProfile 'checks\approved_check.py'
    Copy-ManagedFile -Source (Join-Path $script:RepoRoot 'config\scoreboard.json') -Destination $scoreboardTarget -Kind 'scoreboard'
    Copy-ManagedFile -Source (Join-Path $script:RepoRoot 'scripts\scoreboard.py') -Destination $scoreboardScript -Kind 'hook-script'
    Copy-ManagedFile -Source (Join-Path $script:RepoRoot 'config\checks\approved_check.py') -Destination $scoreboardCheck -Kind 'scoreboard-check'

    $hookTarget = Join-Path $hookDirectory 'agent-harness.json'
    $hookConfig = Read-JsonC (Join-Path $script:RepoRoot '.github\hooks\agent-harness.json.example')
    $traceDirectory = Join-Path $Profile 'harness-runs'
    foreach ($eventName in @($hookConfig['hooks'].Keys)) {
        foreach ($hook in @($hookConfig['hooks'][$eventName])) {
            $hook['command'] = "python3 `"$pythonTarget`""
            $hook['windows'] = "pwsh -NoProfile -ExecutionPolicy Bypass -File `"$powerShellTarget`""
            $hook['linux'] = "python3 `"$pythonTarget`""
            $hook['osx'] = "python3 `"$pythonTarget`""
            $hook['env']['ASSURED_ARC_HARNESS_CONFIG'] = $harnessTarget
            $hook['env']['ASSURED_ARC_HARNESS_TRACE_DIR'] = $traceDirectory
            $hook['env']['ASSURED_ARC_HARNESS_TOOL_POLICY'] = $toolPolicyTarget
            $hook['env']['ASSURED_ARC_SCOREBOARD'] = $scoreboardTarget
            $hook['env']['ASSURED_ARC_SCOREBOARD_SCRIPT'] = $scoreboardScript
            $hook['env']['ASSURED_ARC_SCOREBOARD_ROOT'] = [IO.Path]::GetFullPath($CopilotProfile)
        }
    }
    Assert-NoReparsePath $hookTarget
    if (Test-Path -LiteralPath $hookTarget) { Backup-Item $hookTarget } else { Register-Created $hookTarget }
    Invoke-Mutation "Write agent harness hooks to $hookTarget" { Write-Json -Path $hookTarget -Value $hookConfig }
    Register-Managed -Kind 'hook-config' -Target $hookTarget
    Install-ClaudeAdapters -Destination (Join-Path $Profile 'claude') -PythonHook $pythonTarget -HarnessTarget $harnessTarget -TraceDirectory $traceDirectory -ToolPolicyTarget $toolPolicyTarget -ScoreboardTarget $scoreboardTarget -ScoreboardScript $scoreboardScript -ScoreboardRoot ([IO.Path]::GetFullPath($CopilotProfile))
}

function Install-ClaudeAdapters {
    param(
        [string]$Destination,
        [string]$PythonHook,
        [string]$HarnessTarget,
        [string]$TraceDirectory,
        [string]$ToolPolicyTarget,
        [string]$ScoreboardTarget,
        [string]$ScoreboardScript,
        [string]$ScoreboardRoot
    )
    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python) { throw 'Python is required to render Claude adapters from the shared contract.' }
    $expected = @(
        (Join-Path $Destination 'settings.json'),
        (Join-Path $Destination 'agent-contract.json')
    )
    foreach ($role in @('orchestrator', 'scout', 'researcher', 'implementer', 'verifier', 'critic')) {
        $expected += Join-Path $Destination ('agents\assured-arc-' + $role + '.md')
    }
    foreach ($target in $expected) {
        Assert-NoReparsePath $target
        if (Test-Path -LiteralPath $target) { Backup-Item $target } else { Register-Created $target }
    }
    $arguments = @(
        (Join-Path $script:RepoRoot 'scripts\render_contract.py'),
        '--contract', (Join-Path $script:RepoRoot 'config\agent-contract.json'),
        '--destination', $Destination,
        '--command', "python `"$PythonHook`""
    )
    foreach ($entry in @(
        "ASSURED_ARC_HARNESS_HOST=claude",
        "ASSURED_ARC_HARNESS_CONFIG=$HarnessTarget",
        "ASSURED_ARC_HARNESS_TRACE_DIR=$TraceDirectory",
        "ASSURED_ARC_HARNESS_TOOL_POLICY=$ToolPolicyTarget",
        "ASSURED_ARC_SCOREBOARD=$ScoreboardTarget",
        "ASSURED_ARC_SCOREBOARD_SCRIPT=$ScoreboardScript",
        "ASSURED_ARC_SCOREBOARD_ROOT=$ScoreboardRoot"
    )) { $arguments += @('--env', $entry) }
    Invoke-Mutation "Render Claude adapters from the shared contract to $Destination" {
        & $python.Source @arguments
        if ($LASTEXITCODE -ne 0) { throw 'Claude adapter render failed.' }
    }
    Register-Managed -Kind 'claude-settings' -Target (Join-Path $Destination 'settings.json')
    Register-Managed -Kind 'claude-contract' -Target (Join-Path $Destination 'agent-contract.json')
    foreach ($role in @('orchestrator', 'scout', 'researcher', 'implementer', 'verifier', 'critic')) {
        Register-Managed -Kind 'claude-agent' -Target (Join-Path $Destination ('agents\assured-arc-' + $role + '.md'))
    }
}

function Install-ArxivMcp {
    param([string]$Version)
    $target = Join-Path $ProfileRoot "mcp\arxiv-$Version"
    $toolDirectory = Join-Path $target 'tools'
    $binDirectory = Join-Path $target 'bin'
    $entry = Join-Path $binDirectory 'arxiv-mcp-server.exe'
    $marker = Join-Path $target '.assured-arc-version'
    $previousToolDirectory = $env:UV_TOOL_DIR
    $previousBinDirectory = $env:UV_TOOL_BIN_DIR
    if ((Test-Path -LiteralPath $entry) -and (Test-Path -LiteralPath $marker) -and (Get-Content -LiteralPath $marker -Raw).Trim() -eq $Version) {
        Write-Host "arXiv MCP already installed: $Version"
        Register-Managed -Kind 'mcp-runtime' -Target $target
        return $entry
    }
    if (Test-Path -LiteralPath $target) { Backup-Item $target } else { Register-Created $target }
    Invoke-Mutation "Install arXiv MCP $Version into $target" {
        $env:UV_TOOL_DIR = $toolDirectory
        $env:UV_TOOL_BIN_DIR = $binDirectory
        try {
            & uv tool install --force --quiet "arxiv-mcp-server==$Version"
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $entry)) { throw "Unable to install arXiv MCP $Version" }
            [IO.File]::WriteAllText($marker, $Version + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
        }
        finally {
            if ($null -eq $previousToolDirectory) { Remove-Item Env:UV_TOOL_DIR -ErrorAction SilentlyContinue } else { $env:UV_TOOL_DIR = $previousToolDirectory }
            if ($null -eq $previousBinDirectory) { Remove-Item Env:UV_TOOL_BIN_DIR -ErrorAction SilentlyContinue } else { $env:UV_TOOL_BIN_DIR = $previousBinDirectory }
        }
    }
    Register-Managed -Kind 'mcp-runtime' -Target $target
    return $entry
}

function Update-McpConfig {
    param([string]$Target, [string]$Template, [string]$ArxivEntry)
    $Target = [IO.Path]::GetFullPath($Target)
    Assert-NoReparsePath $Target
    if ($script:State.mcp.target) {
        if (-not [IO.Path]::IsPathRooted([string]$script:State.mcp.target)) { throw 'The saved MCP ownership target is relative and cannot be trusted. Restore or remove this profile before reinstalling.' }
        $savedTarget = [IO.Path]::GetFullPath([string]$script:State.mcp.target)
        $requestedTarget = $Target
        if (-not [string]::Equals($savedTarget, $requestedTarget, [StringComparison]::OrdinalIgnoreCase)) {
            throw "This profile owns MCP entries in $savedTarget and cannot migrate them to $requestedTarget. Uninstall the existing profile first."
        }
    }
    if (-not (Test-Path -LiteralPath $Target)) { Register-Created $Target }
    $existing = Read-JsonC $Target
    $defaults = Read-JsonC $Template
    $defaultInputs = [System.Collections.ArrayList]@()
    if ($defaults.Contains('inputs')) {
        if ($defaults['inputs'] -is [System.Collections.IDictionary]) { $defaultInputs.Add($defaults['inputs']) | Out-Null }
        else { foreach ($item in @($defaults['inputs'])) { $defaultInputs.Add($item) | Out-Null } }
    }
    if (-not $ArxivEntry) { throw 'The arXiv MCP executable path was not resolved.' }
    if ($defaults['servers'].Contains('arxiv')) {
        $defaults['servers']['arxiv']['command'] = $ArxivEntry
    }
    if ((Get-Platform) -eq 'windows') {
        $nodeCommand = (Get-Command node -ErrorAction Stop).Source
        $npxCommand = (Get-Command npx -ErrorAction Stop).Source
        $npxCli = Join-Path (Split-Path -Parent $npxCommand) 'node_modules\npm\bin\npx-cli.js'
        if (-not (Test-Path -LiteralPath $npxCli)) { throw "Unable to resolve the npx CLI beside $npxCommand" }
        foreach ($server in $defaults['servers'].Values) {
            if ($server.Contains('command') -and $server['command'] -eq 'npx') {
                $server['command'] = $nodeCommand
                $server['args'] = @($npxCli) + @($server['args'])
            }
        }
    }
    if (-not $existing.Contains('servers')) { $existing['servers'] = [ordered]@{} }
    $existingInputs = [System.Collections.ArrayList]@()
    if ($existing.Contains('inputs')) {
        if ($existing['inputs'] -is [System.Collections.IDictionary]) { $existingInputs.Add($existing['inputs']) | Out-Null }
        else { foreach ($item in @($existing['inputs'])) { $existingInputs.Add($item) | Out-Null } }
    }
    $ownedServerIds = @($script:State.mcp.serverIds)
    $ownedInputIds = @($script:State.mcp.inputIds)
    $conflicts = [System.Collections.ArrayList]@()
    foreach ($key in $defaults['servers'].Keys) {
        if ($existing['servers'].Contains($key) -and $ownedServerIds -notcontains $key -and -not $ForceSettings) {
            $conflicts.Add("server:$key") | Out-Null
        }
    }
    foreach ($input in $defaultInputs) {
        $id = $input['id']
        if (($existingInputs | Where-Object { $_['id'] -eq $id }) -and $ownedInputIds -notcontains $id -and -not $ForceSettings) {
            $conflicts.Add("input:$id") | Out-Null
        }
    }
    if ($conflicts.Count -gt 0) { throw "MCP configuration conflicts with existing IDs: $($conflicts -join ', '). Rerun with -ForceSettings only after reviewing replacements." }
    Backup-Item $Target
    foreach ($key in $defaults['servers'].Keys) {
        $existing['servers'][$key] = $defaults['servers'][$key]
        if ($script:State.mcp.serverIds -notcontains $key) { $script:State.mcp.serverIds.Add($key) | Out-Null }
    }
    foreach ($input in $defaultInputs) {
        for ($index = $existingInputs.Count - 1; $index -ge 0; $index--) {
            if ($existingInputs[$index]['id'] -eq $input['id']) { $existingInputs.RemoveAt($index) }
        }
        $existingInputs.Add($input) | Out-Null
        if ($script:State.mcp.inputIds -notcontains $input['id']) { $script:State.mcp.inputIds.Add($input['id']) | Out-Null }
    }
    $existing['inputs'] = @($existingInputs.ToArray())
    $script:State.mcp.target = $Target
    Invoke-Mutation "Merge reviewed MCP template into $Target" { Write-Json -Path $Target -Value $existing }
    Register-Managed -Kind 'mcp' -Target $Target
}

function Update-CopilotCliMcpConfig {
    param([string]$Target, [string]$Template, [string]$ArxivEntry)
    $Target = [IO.Path]::GetFullPath($Target)
    Assert-NoReparsePath $Target
    if ($script:State.copilotCli.mcp.target) {
        $savedTarget = [IO.Path]::GetFullPath([string]$script:State.copilotCli.mcp.target)
        if (-not [string]::Equals($savedTarget, $Target, [StringComparison]::OrdinalIgnoreCase)) {
            throw "This profile owns Copilot CLI MCP entries in $savedTarget and cannot migrate them to $Target. Uninstall the existing profile first."
        }
    }
    if (-not (Test-Path -LiteralPath $Target)) { Register-Created $Target }
    $existing = Read-JsonC $Target
    $defaults = Read-JsonC $Template
    if (-not $ArxivEntry) { throw 'The arXiv MCP executable path was not resolved.' }
    $defaults['mcpServers']['arxiv']['command'] = $ArxivEntry
    if ((Get-Platform) -eq 'windows') {
        $nodeCommand = (Get-Command node -ErrorAction Stop).Source
        $npxCommand = (Get-Command npx -ErrorAction Stop).Source
        $npxCli = Join-Path (Split-Path -Parent $npxCommand) 'node_modules\npm\bin\npx-cli.js'
        if (-not (Test-Path -LiteralPath $npxCli)) { throw "Unable to resolve the npx CLI beside $npxCommand" }
        foreach ($server in $defaults['mcpServers'].Values) {
            if ($server.Contains('command') -and $server['command'] -eq 'npx') {
                $server['command'] = $nodeCommand
                $server['args'] = @($npxCli) + @($server['args'])
            }
        }
    }
    if (-not $existing.Contains('mcpServers')) { $existing['mcpServers'] = [ordered]@{} }
    $ownedIds = @($script:State.copilotCli.mcp.serverIds)
    $conflicts = [System.Collections.ArrayList]@()
    foreach ($key in $defaults['mcpServers'].Keys) {
        if ($existing['mcpServers'].Contains($key) -and $ownedIds -notcontains $key -and -not $ForceSettings) { $conflicts.Add("server:$key") | Out-Null }
    }
    if ($conflicts.Count -gt 0) { throw "Copilot CLI MCP configuration conflicts with existing IDs: $($conflicts -join ', '). Rerun with -ForceSettings only after reviewing replacements." }
    Backup-Item $Target
    foreach ($key in $defaults['mcpServers'].Keys) {
        $existing['mcpServers'][$key] = $defaults['mcpServers'][$key]
        if ($script:State.copilotCli.mcp.serverIds -notcontains $key) { $script:State.copilotCli.mcp.serverIds.Add($key) | Out-Null }
    }
    $script:State.copilotCli.mcp.target = $Target
    Invoke-Mutation "Merge reviewed MCP template into Copilot CLI at $Target" { Write-Json -Path $Target -Value $existing }
    Register-Managed -Kind 'cli-mcp' -Target $Target
}

function Install-Extensions {
    param([string]$Code, [string]$Manifest)
    $extensions = Read-JsonC $Manifest
    $installed = @(& $Code '--list-extensions')
    if ($LASTEXITCODE -ne 0) { throw 'Unable to list installed VS Code extensions.' }
    $known = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($item in $installed) { [void]$known.Add($item.Trim()) }
    foreach ($extension in $extensions['extensions']) {
        $id = $extension['id']
        if ($extension.Contains('install') -and -not [bool]$extension['install']) {
            Write-Host "Extension capability provided by VS Code: $id"
            continue
        }
        if ($known.Contains($id)) {
            Write-Host "Extension already installed: $id"
            continue
        }
        Invoke-Mutation "Install VS Code extension $id" {
            & $Code '--install-extension' $id
            if ($LASTEXITCODE -ne 0) { throw "Extension install failed: $id" }
        }
        if (-not $DryRun -and $script:State.extensions -notcontains $id) {
            $script:State.extensions.Add($id) | Out-Null
            $script:TransactionExtensions.Add($id) | Out-Null
        }
    }
}

function Invoke-Rollback {
    Write-Warning 'Installer failed. Rolling back package-managed changes.'
    $removeProfileRoot = $false
    foreach ($path in @($script:TransactionCreated | Select-Object -Unique | Sort-Object Length -Descending)) {
        if ([string]::Equals($path, $ProfileRoot, [StringComparison]::OrdinalIgnoreCase)) {
            $removeProfileRoot = $true
            continue
        }
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue }
    }
    $backups = @($script:TransactionBackups)
    [array]::Reverse($backups)
    foreach ($backup in $backups) {
        if (Test-Path -LiteralPath $backup.target) { Remove-Item -LiteralPath $backup.target -Recurse -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $backup.backup) {
            $parent = Split-Path -Parent $backup.target
            if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            Copy-Item -LiteralPath $backup.backup -Destination $backup.target -Recurse -Force
        }
    }
    if ($removeProfileRoot -and (Test-Path -LiteralPath $ProfileRoot)) {
        Remove-Item -LiteralPath $ProfileRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    $code = Resolve-CodeCommand $CodeCommand
    if ($code) {
        foreach ($extension in $script:TransactionExtensions) {
            Write-Warning "Removing extension installed during failed Assured Arc installation: $extension"
            & $code '--uninstall-extension' $extension | Out-Null
        }
    }
}

function Remove-TransientBackups {
    if ($NoBackup -or $DryRun) { return }
    $retained = @($script:State.backups | ForEach-Object { $_['backup'] })
    foreach ($backup in $script:TransactionBackups) {
        if ($retained -notcontains $backup['backup'] -and (Test-Path -LiteralPath $backup['backup'])) {
            Remove-Item -LiteralPath $backup['backup'] -Recurse -Force
        }
    }
    if ((Test-Path -LiteralPath $script:BackupRoot) -and -not (Get-ChildItem -LiteralPath $script:BackupRoot -Force | Select-Object -First 1)) {
        Remove-Item -LiteralPath $script:BackupRoot -Force
    }
}

try {
    Write-Step 'Resolve configuration'
    if ($InstallMcp -and $SkipMcp) { throw 'Use either -InstallMcp or -SkipMcp, not both.' }
    if ($InstallCopilotCli -and $SkipCopilotCli) { throw 'Use either -InstallCopilotCli or -SkipCopilotCli, not both.' }
    if ($InstallExtensions -and $SkipExtensions) { throw 'Use either -InstallExtensions or -SkipExtensions, not both.' }
    if ($InstallVault -and $SkipVault) { throw 'Use either -InstallVault or -SkipVault, not both.' }
    if (-not $ConfigPath) { $ConfigPath = Join-Path $script:RepoRoot 'config\assured-arc.example.json' }
    $config = Read-JsonC $ConfigPath
    $profileManifest = Read-JsonC (Join-Path $script:RepoRoot 'config\install-profiles.json')
    $selectedProfile = if ($PSBoundParameters.ContainsKey('Profile')) { $Profile } elseif ($config.Contains('profile') -and $config['profile']) { [string]$config['profile'] } else { [string]$profileManifest['default'] }
    $profileName = @($profileManifest['profiles'].Keys | Where-Object { [string]::Equals([string]$_, $selectedProfile, [StringComparison]::OrdinalIgnoreCase) }) | Select-Object -First 1
    if (-not $profileName) { throw "Unknown install profile '$selectedProfile'. Expected one of: $($profileManifest['profiles'].Keys -join ', ')." }
    $profileConfig = $profileManifest['profiles'][$profileName]
    if (-not $PSBoundParameters.ContainsKey('InstallExtensions') -and -not $PSBoundParameters.ContainsKey('SkipExtensions')) { $SkipExtensions = -not [bool]$profileConfig['installExtensions'] }
    if (-not $PSBoundParameters.ContainsKey('InstallMcp') -and -not $PSBoundParameters.ContainsKey('SkipMcp')) { $InstallMcp = [bool]$profileConfig['installMcp'] }
    if (-not $PSBoundParameters.ContainsKey('InstallVault') -and -not $PSBoundParameters.ContainsKey('SkipVault')) { $SkipVault = -not [bool]$profileConfig['installVault'] }
    if (-not $PSBoundParameters.ContainsKey('InstallCopilotCli') -and -not $PSBoundParameters.ContainsKey('SkipCopilotCli')) { $InstallCopilotCli = [bool]$profileConfig['installCopilotCli'] }
    if ($config.Contains('installExtensions') -and -not $PSBoundParameters.ContainsKey('InstallExtensions') -and -not $PSBoundParameters.ContainsKey('SkipExtensions')) { $SkipExtensions = -not [bool]$config['installExtensions'] }
    if ($config.Contains('installMcp') -and -not $PSBoundParameters.ContainsKey('InstallMcp') -and -not $PSBoundParameters.ContainsKey('SkipMcp')) { $InstallMcp = [bool]$config['installMcp'] }
    if ($config.Contains('installVault') -and -not $PSBoundParameters.ContainsKey('InstallVault') -and -not $PSBoundParameters.ContainsKey('SkipVault')) { $SkipVault = -not [bool]$config['installVault'] }
    if ($config.Contains('installCopilotCli') -and -not $PSBoundParameters.ContainsKey('InstallCopilotCli') -and -not $PSBoundParameters.ContainsKey('SkipCopilotCli')) { $InstallCopilotCli = [bool]$config['installCopilotCli'] }
    if ($config.Contains('profileRoot') -and $config['profileRoot'] -and -not $PSBoundParameters.ContainsKey('ProfileRoot')) { $ProfileRoot = $config['profileRoot'] }
    $ProfileRoot = [IO.Path]::GetFullPath($ProfileRoot)
    $script:StatePath = Join-Path $ProfileRoot 'state.json'
    $script:BackupRoot = Join-Path $ProfileRoot ('backups' + [IO.Path]::DirectorySeparatorChar + (Get-Date -Format 'yyyyMMdd-HHmmss-fffffff'))
    $script:State.profileRoot = $ProfileRoot
    if (-not $VaultPath) { $VaultPath = Join-Path $ProfileRoot 'vault' }
    if ($config.Contains('vaultPath') -and $config['vaultPath'] -and -not $PSBoundParameters.ContainsKey('VaultPath')) { $VaultPath = $config['vaultPath'] }
    $VaultPath = [IO.Path]::GetFullPath($VaultPath)
    if ($InstallExtensions) { $SkipExtensions = $false }
    if ($InstallVault) { $SkipVault = $false }
    if ($SkipCopilotCli) { $InstallCopilotCli = $false }
    if ($SkipMcp) { $InstallMcp = $false }
    if ($config.Contains('forceSettings') -and $config['forceSettings'] -and -not $PSBoundParameters.ContainsKey('ForceSettings')) { $ForceSettings = $true }
    $vscodeUser = [IO.Path]::GetFullPath($(if ($VsCodeUserDirectory) { $VsCodeUserDirectory } else { Get-VsCodeUserDirectory }))
    $copilotRoot = [IO.Path]::GetFullPath($(if ($CopilotRoot) { $CopilotRoot } else { Join-Path $ProfileRoot 'copilot' }))
    $copilotCliRoot = [IO.Path]::GetFullPath($(if ($CopilotCliRoot) { $CopilotCliRoot } elseif ($env:COPILOT_HOME) { $env:COPILOT_HOME } else { Join-Path $HOME '.copilot' }))
    $script:State.vscodeUserDirectory = $vscodeUser
    $script:State.copilotRoot = $copilotRoot
    $script:State.copilotCli.enabled = [bool]$InstallCopilotCli
    $script:State.copilotCli.root = $copilotCliRoot
    $script:State.vaultPath = $VaultPath
    Assert-InstallPlanPaths -VsCodeUser $vscodeUser -CopilotProfile $copilotRoot -CopilotCliProfile $copilotCliRoot -Vault $VaultPath -Profile $ProfileRoot
    Import-PreviousState
    if ($InstallCopilotCli) { Assert-InstallPlanPaths -VsCodeUser $vscodeUser -CopilotProfile $copilotRoot -CopilotCliProfile $copilotCliRoot -Vault $VaultPath -Profile $ProfileRoot }

    Write-Step 'Validate prerequisites'
    if ((Get-Platform) -ne 'windows') { throw 'The PowerShell installer supports Windows. Use install/assured-arc.sh on macOS or Linux.' }
    $code = $null
    if (-not $SkipExtensions) {
        $code = Resolve-CodeCommand $CodeCommand
        if (-not $code) { throw "VS Code command '$CodeCommand' was not found. Install VS Code and enable the code command, or rerun with -SkipExtensions." }
    }
    if ($InstallCopilotCli) {
        $cli = Get-Command $CopilotCliCommand -ErrorAction SilentlyContinue
        if (-not $cli) { throw "GitHub Copilot CLI command '$CopilotCliCommand' was not found. Install Copilot CLI, or omit -InstallCopilotCli." }
    }
    if ($InstallMcp) {
        foreach ($command in @('node', 'npx', 'uv')) {
            if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "$command is required for the reviewed MCP profile. Install it, or rerun with -SkipMcp through the root installer." }
        }
        $nodeMajor = [int]((& node '--version').TrimStart('v').Split('.')[0])
        if ($nodeMajor -lt 18) { throw 'Sequential Thinking MCP requires Node.js 18 or newer.' }
    }

    Write-Step 'Create profile and backup location'
    Assert-NoReparsePath $ProfileRoot
    if (-not (Test-Path -LiteralPath $ProfileRoot)) { Register-Created $ProfileRoot }
    Invoke-Mutation "Create profile root $ProfileRoot" { New-Item -ItemType Directory -Path $ProfileRoot -Force | Out-Null }
    if (-not $NoBackup) { Invoke-Mutation "Create backup location $script:BackupRoot" { New-Item -ItemType Directory -Path $script:BackupRoot -Force | Out-Null } }

    $script:State.vscodeUserDirectory = $vscodeUser
    $script:State.copilotRoot = $copilotRoot
    $script:State.vaultPath = $VaultPath
    $settingsTarget = Join-Path $vscodeUser 'settings.json'
    $mcpTarget = Join-Path $vscodeUser 'mcp.json'

    Write-Step 'Configure VS Code settings'
    $agentRoot = if ($InstallCopilotCli) { Join-Path $copilotCliRoot 'agents' } else { Join-Path $copilotRoot 'agents' }
    Update-Settings -Target $settingsTarget -Template (Join-Path $script:RepoRoot 'config\user-settings.json') -CustomizationRoot $copilotRoot -AgentRoot $agentRoot

    Write-Step 'Install managed agents, skills, and instructions'
    Get-ChildItem (Join-Path $script:RepoRoot '.github\skills') -Directory | ForEach-Object {
        Copy-ManagedDirectory -Source $_.FullName -Destination (Join-Path $copilotRoot ('skills' + [IO.Path]::DirectorySeparatorChar + $_.Name)) -Kind 'skill'
    }
    $registryTarget = Join-Path $copilotRoot 'skill-registry.json'
    Copy-ManagedFile -Source (Join-Path $script:RepoRoot 'config\skill-registry.json') -Destination $registryTarget -Kind 'skill-registry'
    $instructionManifest = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'config\instructions.json') -Raw | ConvertFrom-Json
    foreach ($instructionName in @($instructionManifest.instructions)) {
        $source = Join-Path (Join-Path $script:RepoRoot '.github\instructions') $instructionName
        if (-not (Test-Path -LiteralPath $source)) { throw "Instruction manifest entry not found: $instructionName" }
        $target = Join-Path $copilotRoot ('instructions' + [IO.Path]::DirectorySeparatorChar + $instructionName)
        Copy-ManagedFile -Source $source -Destination $target -Kind 'instruction'
    }
    Get-ChildItem (Join-Path $script:RepoRoot '.github\agents') -Filter '*.agent.md' -File | ForEach-Object {
        $target = Join-Path $copilotRoot ('agents' + [IO.Path]::DirectorySeparatorChar + $_.Name)
        Copy-ManagedFile -Source $_.FullName -Destination $target -Kind 'agent'
    }
    Get-ChildItem (Join-Path $script:RepoRoot '.github\prompts') -Filter '*.prompt.md' -File | ForEach-Object {
        $target = Join-Path $copilotRoot ('prompts' + [IO.Path]::DirectorySeparatorChar + $_.Name)
        Copy-ManagedFile -Source $_.FullName -Destination $target -Kind 'prompt'
    }
    Install-AgentHarness -CopilotProfile $copilotRoot -Profile $ProfileRoot -CopilotCliProfile $(if ($InstallCopilotCli) { $copilotCliRoot } else { '' })

    Write-Step 'Configure GitHub Copilot CLI'
    if ($InstallCopilotCli) { Install-CopilotCliProfile -CliRoot $copilotCliRoot -CopilotProfile $copilotRoot -Profile $ProfileRoot }
    else { Write-Host 'Copilot CLI personal-profile installation skipped. Repository agents and skills remain CLI-compatible.' }

    Write-Step 'Install VS Code extensions'
    if ($SkipExtensions) { Write-Host 'Extension installation skipped.' } else { Install-Extensions -Code $code -Manifest (Join-Path $script:RepoRoot 'config\extensions.json') }

    Write-Step 'Configure reviewed MCP profile'
    if ($InstallMcp) {
        $mcpManifest = Read-JsonC (Join-Path $script:RepoRoot 'config\mcp-servers.json')
        $arxivVersion = [string](@($mcpManifest['servers'] | Where-Object { $_['id'] -eq 'arxiv' })[0]['version'])
        $arxivEntry = Install-ArxivMcp -Version $arxivVersion
        Update-McpConfig -Target $mcpTarget -Template (Join-Path $script:RepoRoot 'mcp\mcp.json.example') -ArxivEntry $arxivEntry
        if ($InstallCopilotCli) {
            Update-CopilotCliMcpConfig -Target (Join-Path $copilotCliRoot 'mcp-config.json') -Template (Join-Path $script:RepoRoot 'mcp\copilot-cli.mcp.json.example') -ArxivEntry $arxivEntry
        }
    }
    else {
        $profileMcp = Join-Path $ProfileRoot 'mcp\mcp.json.example'
        Assert-NoReparsePath $profileMcp
        if (-not (Test-Path -LiteralPath $profileMcp)) { Register-Created $profileMcp }
        Invoke-Mutation "Copy MCP example to $profileMcp" {
            $parent = Split-Path -Parent $profileMcp
            if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'mcp\mcp.json.example') -Destination $profileMcp -Force
        }
        $profileCliMcp = Join-Path $ProfileRoot 'mcp\copilot-cli.mcp.json.example'
        Assert-NoReparsePath $profileCliMcp
        if (-not (Test-Path -LiteralPath $profileCliMcp)) { Register-Created $profileCliMcp }
        Invoke-Mutation "Copy Copilot CLI MCP example to $profileCliMcp" {
            Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'mcp\copilot-cli.mcp.json.example') -Destination $profileCliMcp -Force
        }
        Write-Host 'MCP installation skipped. The reviewed template was copied for reference.'
    }

    Write-Step 'Create optional Obsidian vault template'
    if ($SkipVault) { Write-Host 'Vault template installation skipped.' }
    else {
        if (-not (Test-Path -LiteralPath $VaultPath)) { Register-Created $VaultPath }
        Invoke-Mutation "Create or extend vault template at $VaultPath" {
            if (-not (Test-Path -LiteralPath $VaultPath)) { New-Item -ItemType Directory -Path $VaultPath -Force | Out-Null }
            Copy-TemplateIfMissing -Source (Join-Path $script:RepoRoot 'vault-template') -Destination $VaultPath
            $workspace = Join-Path $VaultPath 'assured-arc.code-workspace'
            if (-not (Test-Path -LiteralPath $workspace)) {
                $workspaceConfig = [ordered]@{
                    folders = @([ordered]@{ path = '.' })
                    settings = [ordered]@{ 'files.exclude' = [ordered]@{ 'local-only' = $true } }
                }
                Write-Json -Path $workspace -Value $workspaceConfig
            }
        }
    }

    if (-not $DryRun) {
        Write-Json -Path $script:StatePath -Value $script:State
        $stateHashPath = $script:StatePath + '.sha256'
        $stateHash = (Get-FileHash -LiteralPath $script:StatePath -Algorithm SHA256).Hash.ToLowerInvariant()
        [IO.File]::WriteAllText($stateHashPath, $stateHash + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
        try { Remove-TransientBackups }
        catch { Write-Warning "Installation succeeded, but transient backup cleanup failed: $($_.Exception.Message)" }
        Write-Host "Installation state: $script:StatePath"
    }
    Write-Progress -Activity 'Assured Arc' -Completed
    Write-Host 'Assured Arc installation completed successfully.'
    if ($DryRun) { Write-Host 'No changes were made because -DryRun was used.' }
}
catch {
    $message = $_.Exception.Message
    if (-not $DryRun) { Invoke-Rollback }
    throw "Assured Arc installation failed: $message"
}
