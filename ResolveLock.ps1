param(
    [ValidateSet('Capture', 'Check')]
    [string] $Mode = 'Capture',

    [Parameter(Mandatory = $true)]
    [string] $File,

    [string[]] $Tools = @('git', 'dotnet', 'cl', 'cmake', 'python')
)

$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    throw 'ResolveLock is for Windows.'
}

function Get-PeArchitecture {
    param([string] $Path)

    $stream = $null
    $reader = $null
    try {
        $stream = [IO.File]::Open(
            $Path, [IO.FileMode]::Open,
            [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite
        )
        if ($stream.Length -lt 64) { return $null }

        $reader = New-Object IO.BinaryReader($stream)
        if ($reader.ReadUInt16() -ne 0x5A4D) { return $null } # MZ

        [void] $stream.Seek(0x3C, [IO.SeekOrigin]::Begin)
        $offset = $reader.ReadInt32()
        if ($offset -lt 0 -or $offset -gt ($stream.Length - 6)) {
            return $null
        }

        [void] $stream.Seek($offset, [IO.SeekOrigin]::Begin)
        if ($reader.ReadUInt32() -ne 0x00004550) { return $null } # PE
        $machine = $reader.ReadUInt16()

        switch ($machine) {
            0x014c { return 'x86' }
            0x8664 { return 'x64' }
            0x01c4 { return 'ARM32' }
            0xAA64 { return 'ARM64' }
            default { return ('PE-0x{0:X4}' -f $machine) }
        }
    }
    catch {
        return $null
    }
    finally {
        if ($reader) { $reader.Dispose() }
        elseif ($stream) { $stream.Dispose() }
    }
}

function Get-FileIdentity {
    param([string] $Path)

    try {
        $item = Get-Item -LiteralPath $Path -ErrorAction Stop
        if ($item.PSIsContainer) { return $null }

        return [pscustomobject]@{
            Path         = $item.FullName
            SHA256       = (Get-FileHash -LiteralPath $item.FullName `
                              -Algorithm SHA256).Hash
            Architecture = Get-PeArchitecture $item.FullName
        }
    }
    catch {
        return [pscustomobject]@{
            Path         = $Path
            SHA256       = $null
            Architecture = $null
        }
    }
}

function Get-ToolRecord {
    param([string] $Name)

    if ($Name -notmatch '^[a-zA-Z0-9_.+-]+$') {
        throw "Use a command name, not a path: $Name"
    }

    # This is PowerShell's view, including aliases and functions.
    $commands = @(Get-Command -Name $Name -All -ErrorAction SilentlyContinue)
    $winner = $null

    if ($commands.Count -gt 0) {
        $command = $commands[0]
        $target = $null

        if ($command.CommandType -in @('Application', 'ExternalScript')) {
            $target = Get-FileIdentity $command.Path
        }

        $winner = [pscustomobject]@{
            Type       = [string] $command.CommandType
            Name       = [string] $command.Name
            # Definition is useful for aliases; don't store function bodies.
            AliasTarget = if ($command.CommandType -eq 'Alias') {
                [string] $command.Definition
            } else { $null }
            Module     = [string] $command.ModuleName
            File       = $target
        }
    }

    # Separately inventory matching files on PATH, in PATH order.
    # This is diagnostic evidence, not a simulation of CreateProcess().
    $extensions = @()
    if ([IO.Path]::GetExtension($Name)) {
        $extensions = @('')
    } else {
        $extensions = @(
            $env:PATHEXT -split ';' |
                Where-Object { $_ } |
                ForEach-Object { $_.Trim() }
        )
        if ($extensions.Count -eq 0) {
            $extensions = @('.COM', '.EXE', '.BAT', '.CMD')
        }
    }

    $matches = @()
    $seen = @{}
    $rank = 0

    foreach ($directory in ($env:PATH -split ';')) {
        $directory = [Environment]::ExpandEnvironmentVariables(
            $directory.Trim().Trim('"')
        )
        if (-not $directory) { continue }

        foreach ($extension in $extensions) {
            try {
                $candidate = Join-Path $directory ($Name + $extension)
                if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
                    continue
                }

                $identity = Get-FileIdentity $candidate
                $key = $identity.Path.ToLowerInvariant()
                if ($seen.ContainsKey($key)) { continue }

                $seen[$key] = $true
                $matches += [pscustomobject]@{
                    Rank         = $rank
                    Path         = $identity.Path
                    SHA256       = $identity.SHA256
                    Architecture = $identity.Architecture
                }
                $rank++
            }
            catch {
                # An invalid or inaccessible PATH entry need not stop the scan.
            }
        }
    }

    return [pscustomobject]@{
        Name       = $Name
        Winner     = $winner
        PathMatches = @($matches)
    }
}

function Get-Snapshot {
    param([string[]] $Names)

    $records = @(
        foreach ($name in ($Names | Select-Object -Unique)) {
            Get-ToolRecord $name
        }
    )

    return [pscustomobject]@{
        FormatVersion = 1
        CapturedUtc   = [DateTime]::UtcNow.ToString('o')
        Computer      = $env:COMPUTERNAME
        Tools         = $records
    }
}

function Describe-Winner {
    param($Winner)

    if ($null -eq $Winner) { return '(not found)' }
    if ($Winner.File) {
        return "$($Winner.Type): $($Winner.File.Path) [$($Winner.File.Architecture)]"
    }
    if ($Winner.AliasTarget) {
        return "Alias: $($Winner.Name) -> $($Winner.AliasTarget)"
    }
    return "$($Winner.Type): $($Winner.Name) [$($Winner.Module)]"
}

if ($Mode -eq 'Capture') {
    $snapshot = Get-Snapshot $Tools
    $snapshot |
        ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath $File -Encoding UTF8

    Write-Host "Captured $($snapshot.Tools.Count) tools in $File"
    foreach ($tool in $snapshot.Tools) {
        Write-Host "  $($tool.Name): $(Describe-Winner $tool.Winner)"
    }
}
else {
    $before = Get-Content -LiteralPath $File -Raw | ConvertFrom-Json
    if ($before.FormatVersion -ne 1) {
        throw "Unsupported ResolveLock format in $File"
    }

    $names = @($before.Tools | ForEach-Object { $_.Name })
    $after = Get-Snapshot $names
    $changed = $false

    for ($i = 0; $i -lt $names.Count; $i++) {
        $old = $before.Tools[$i]
        $new = $after.Tools[$i]

        # Excludes capture time and computer name; includes hashes and
        # the ordering of all PATH matches.
        $oldIdentity = ConvertTo-Json -InputObject $old -Depth 10 -Compress
        $newIdentity = ConvertTo-Json -InputObject $new -Depth 10 -Compress
        if ($oldIdentity -eq $newIdentity) { continue }

        $changed = $true
        Write-Host "CHANGED: $($old.Name)"
        Write-Host "  Was: $(Describe-Winner $old.Winner)"
        Write-Host "  Now: $(Describe-Winner $new.Winner)"

        $oldPaths = @($old.PathMatches | ForEach-Object { $_.Path })
        $newPaths = @($new.PathMatches | ForEach-Object { $_.Path })
        if (($oldPaths -join '|') -ne ($newPaths -join '|')) {
            Write-Host '  PATH matches before:'
            $oldPaths | ForEach-Object { Write-Host "    $_" }
            Write-Host '  PATH matches now:'
            $newPaths | ForEach-Object { Write-Host "    $_" }
        } else {
            Write-Host '  A file hash or architecture changed.'
        }
    }

    if ($changed) { exit 2 }
    Write-Host 'No tool-resolution drift detected.'
}
