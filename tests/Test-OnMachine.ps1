# On-machine verification for ResolveLock — run this ON WINDOWS.
#   powershell -ExecutionPolicy Bypass -File .\tests\Test-OnMachine.ps1
#
# It runs ResolveLock as a direct child process (the only invocation whose
# exit code is meaningful — see VERIFY.md) and checks four things:
#   1. Capture succeeds (exit 0) and writes a parseable format-1 lockfile
#   2. Check against that fresh lockfile reports no drift (exit 0)
#   3. Check against a tampered lockfile reports drift (exit 2)
#   4. Check with a missing lockfile fails (non-zero exit)
# Results are written to ResolveLock-verification.log in the repo root.
# This script exits 0 when all four pass, 1 otherwise. It changes nothing
# on the machine; all lockfiles live in a temp folder that is removed.

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent
$scriptPath = Join-Path $repoRoot 'ResolveLock.ps1'
$logPath = Join-Path $repoRoot 'ResolveLock-verification.log'
$work = Join-Path $env:TEMP ('resolvelock-verify-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null

$psExe = (Get-Process -Id $PID).Path
$results = @()

function Log($text) {
    $text | Tee-Object -FilePath $logPath -Append
}

function Invoke-ResolveLock {
    param([string[]] $Arguments)
    $output = & $psExe -NoProfile -ExecutionPolicy Bypass -File $scriptPath @Arguments 2>&1 |
        Out-String
    return @{ Output = $output.Trim(); ExitCode = $LASTEXITCODE }
}

function Record($label, $ok, $detail) {
    $script:results += $ok
    Log ("{0}: {1} — {2}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $label, $detail)
}

Remove-Item $logPath -ErrorAction SilentlyContinue
Log "ResolveLock on-machine verification — $(Get-Date -Format o)"
Log "Host: $psExe"
Log "Script under test: $scriptPath"
Log ''

try {
    # 1. Capture with the default tool list.
    $lock = Join-Path $work 'toolchain.lock.json'
    $capture = Invoke-ResolveLock @('-Mode', 'Capture', '-File', $lock)
    $parsed = $null
    if (Test-Path -LiteralPath $lock) {
        try { $parsed = Get-Content -LiteralPath $lock -Raw | ConvertFrom-Json } catch { }
    }
    Record 'Capture exit 0 + lockfile written' `
        ($capture.ExitCode -eq 0 -and $null -ne $parsed) `
        "exit=$($capture.ExitCode)"
    if ($null -ne $parsed) {
        Record 'Lockfile is format version 1' ($parsed.FormatVersion -eq 1) `
            "FormatVersion=$($parsed.FormatVersion), tools=$($parsed.Tools.Count)"
        foreach ($tool in $parsed.Tools) {
            $winner = if ($tool.Winner -and $tool.Winner.File) {
                $tool.Winner.File.Path
            } elseif ($tool.Winner) { "$($tool.Winner.Type): $($tool.Winner.Name)" }
            else { '(not found)' }
            Log "    $($tool.Name): winner=$winner, PATH matches=$(@($tool.PathMatches).Count)"
        }
    }

    # 2. Check immediately — nothing should have drifted.
    $clean = Invoke-ResolveLock @('-Mode', 'Check', '-File', $lock)
    Record 'Check on fresh lockfile: no drift, exit 0' `
        ($clean.ExitCode -eq 0 -and $clean.Output -match 'No tool-resolution drift') `
        "exit=$($clean.ExitCode)"

    # 3. Tamper with a copy — Check must report drift and exit 2.
    $tampered = Join-Path $work 'tampered.lock.json'
    $data = Get-Content -LiteralPath $lock -Raw | ConvertFrom-Json
    $zeroHash = '0' * 64
    $tamperedWhat = $null
    foreach ($tool in $data.Tools) {
        if ($tool.Winner -and $tool.Winner.File -and $tool.Winner.File.SHA256) {
            $tool.Winner.File.SHA256 = $zeroHash; $tamperedWhat = "$($tool.Name) winner hash"; break
        }
    }
    if (-not $tamperedWhat) {
        foreach ($tool in $data.Tools) {
            if (@($tool.PathMatches).Count -gt 0) {
                $tool.PathMatches[0].SHA256 = $zeroHash; $tamperedWhat = "$($tool.Name) PATH-match hash"; break
            }
        }
    }
    if (-not $tamperedWhat) {
        $data.Tools[0].PathMatches = @([pscustomobject]@{
            Rank = 0; Path = 'C:\tampered\fake.exe'; SHA256 = $zeroHash; Architecture = 'x64' })
        $tamperedWhat = 'added a fake PATH match (no tool on this machine has a file to tamper)'
    }
    $data | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $tampered -Encoding UTF8
    $drift = Invoke-ResolveLock @('-Mode', 'Check', '-File', $tampered)
    Record 'Check on tampered lockfile: drift, exit 2' `
        ($drift.ExitCode -eq 2 -and $drift.Output -match 'CHANGED:') `
        "exit=$($drift.ExitCode), tampered: $tamperedWhat"

    # 4. Missing lockfile — Check must fail, not silently pass.
    $missing = Invoke-ResolveLock @('-Mode', 'Check', '-File', (Join-Path $work 'nope.json'))
    Record 'Check with missing lockfile: fails' ($missing.ExitCode -ne 0) `
        "exit=$($missing.ExitCode)"
}
finally {
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}

Log ''
if ($results -notcontains $false -and $results.Count -eq 5) {
    Log 'ALL CHECKS PASSED'
    exit 0
}
Log "FAILED: $(@($results -eq $false).Count) of $($results.Count) checks failed (some checks may not have run)"
exit 1
