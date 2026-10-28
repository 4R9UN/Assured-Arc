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
$combinedPattern = '(' + ($patterns -join '|') + ')'
$binaryExtensions = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($ext in @('.png', '.jpg', '.jpeg', '.gif', '.zip', '.exe', '.dll', '.pyc')) { [void]$binaryExtensions.Add($ext) }

function Scan-Directory([string]$Dir) {
    foreach ($subDir in [IO.Directory]::GetDirectories($Dir)) {
        $leaf = [IO.Path]::GetFileName($subDir)
        if ($leaf -in @('.git', '.venv', 'venv', 'node_modules', '__pycache__')) { continue }
        Scan-Directory $subDir
    }
    foreach ($file in [IO.Directory]::GetFiles($Dir)) {
        $ext = [IO.Path]::GetExtension($file)
        if ($binaryExtensions.Contains($ext)) { continue }
        $relative = $file.Substring($repoRoot.Length).TrimStart('\', '/') -replace '\\', '/'
        if ($excluded -contains $relative) { continue }
        $text = [IO.File]::ReadAllText($file)
        if ($text -match $combinedPattern) {
            foreach ($pattern in $patterns) {
                if ($text -match $pattern) {
                    $findings.Add("$relative matches $pattern") | Out-Null
                    break
                }
            }
        }
    }
}
Scan-Directory $repoRoot

if ($findings.Count -gt 0) {
    throw "Public safety scan failed: $($findings -join '; ')"
}
Write-Host 'Public safety scan passed.'
