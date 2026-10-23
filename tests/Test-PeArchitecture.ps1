# Smoke test for ResolveLock's PE-architecture reader.
# Run on Windows (PowerShell 5.1+):
#   powershell -ExecutionPolicy Bypass -File .\tests\Test-PeArchitecture.ps1
# It extracts ResolveLock's functions (without running the script's main
# Capture/Check dispatch), builds synthetic PE files, and checks the reader.

$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'ResolveLock.ps1'
$lines = Get-Content -LiteralPath $scriptPath

# Find, by exact prefix, the first function and the Mode dispatch that follows it.
$start = $null; $dispatch = $null
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($null -eq $start -and $lines[$i].StartsWith('function Get-PeArchitecture')) { $start = $i }
    if ($null -ne $start -and $lines[$i].StartsWith('if ($Mode')) { $dispatch = $i; break }
}
if ($null -eq $start -or $null -eq $dispatch) { throw 'Could not locate ResolveLock functions to extract.' }

$functionsFile = Join-Path $env:TEMP 'resolvelock-functions.ps1'
$lines[$start..($dispatch - 1)] | Set-Content -LiteralPath $functionsFile -Encoding UTF8
. $functionsFile

function New-SyntheticPe {
    param([string] $Path, [uint16] $Machine)
    $bytes = New-Object byte[] 128
    $bytes[0] = 0x4D; $bytes[1] = 0x5A                        # MZ
    [BitConverter]::GetBytes([int]64).CopyTo($bytes, 0x3C)     # e_lfanew
    [BitConverter]::GetBytes([uint32]0x00004550).CopyTo($bytes, 64) # PE\0\0
    [BitConverter]::GetBytes($Machine).CopyTo($bytes, 68)
    [IO.File]::WriteAllBytes($Path, $bytes)
}

$x64 = Join-Path $env:TEMP 'rl-test-x64.exe'
$x86 = Join-Path $env:TEMP 'rl-test-x86.exe'
New-SyntheticPe $x64 0x8664
New-SyntheticPe $x86 0x014c

$failures = 0
function Assert-Equal($Actual, $Expected, $Label) {
    if ($Actual -eq $Expected) { Write-Host "PASS: $Label -> $Actual" }
    else { Write-Host "FAIL: $Label -> expected '$Expected', got '$Actual'"; $script:failures++ }
}

Assert-Equal (Get-PeArchitecture $x64) 'x64' 'x64 PE'
Assert-Equal (Get-PeArchitecture $x86) 'x86' 'x86 PE'
Assert-Equal (Get-PeArchitecture $scriptPath) $null 'non-PE file'
$identity = Get-FileIdentity $x64
Assert-Equal $identity.Architecture 'x64' 'Get-FileIdentity architecture'
if (-not $identity.SHA256) { Write-Host 'FAIL: Get-FileIdentity returned no hash'; $failures++ }
else { Write-Host "PASS: Get-FileIdentity SHA256 -> $($identity.SHA256.Substring(0,16))..." }

Remove-Item $x64, $x86, $functionsFile -ErrorAction SilentlyContinue
if ($failures -gt 0) { exit 1 }
Write-Host 'All tests passed.'
