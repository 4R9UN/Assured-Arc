[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$excluded = @('.git', 'tests/public-safety.ps1')
$patterns = @(
    'C:\\Users\\',
    'OneDrive - Microsoft',
    '(?i)\bartrived\b',
    '(?i)\bMSTIC\\',
    '(?i)wcdscrubbed',
    '(?i)mdecleardata',
    '(?i)kcdexdw'
)

$findings = [System.Collections.ArrayList]@()
Get-ChildItem -LiteralPath $repoRoot -Recurse -File | ForEach-Object {
    $relative = $_.FullName.Substring($repoRoot.Length).TrimStart('\', '/') -replace '\\', '/'
    if ($relative -like '.git/*' -or $relative -like '.venv/*' -or $excluded -contains $relative) { return }
    if ($_.Extension -in @('.png', '.jpg', '.jpeg', '.gif', '.zip', '.exe', '.dll', '.pyc')) { return }
    $text = Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue
    foreach ($pattern in $patterns) {
        if ($text -match $pattern) {
            $findings.Add("$relative matches $pattern") | Out-Null
            break
        }
    }
}

if ($findings.Count -gt 0) {
    throw "Public safety scan failed: $($findings -join '; ')"
}
Write-Host 'Public safety scan passed.'
