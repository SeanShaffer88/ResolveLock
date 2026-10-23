## TL;DR

ResolveLock answers "why did this build use *that* compiler, SDK tool, or Python?" It creates a lockfile that records what PowerShell actually resolves for each tool, every matching executable on `PATH` (in order), each file's SHA-256 hash, and its PE architecture (x86 / x64 / ARM32 / ARM64). Run it again after an SDK install, a CI image update, or a mysterious build failure and it shows you exactly what changed — and it can fail a CI preflight when it finds drift. It needs only Windows PowerShell 5.1 or newer, and nothing else.

# ResolveLock

A single-file PowerShell utility for capturing and checking tool resolution on Windows. No modules, no dependencies, no installation — copy `ResolveLock.ps1` into a repo or onto a build machine and run it in the same kind of PowerShell session that runs your build.

## Usage

Capture a baseline:

```powershell
.\ResolveLock.ps1 -Mode Capture -File .\toolchain.lock.json `
    -Tools git,dotnet,cl,cmake,python
```

Check for drift later, or on a CI agent:

```powershell
.\ResolveLock.ps1 -Mode Check -File .\toolchain.lock.json
```

- `-Mode` — `Capture` (default) or `Check`.
- `-File` — path to the lockfile (required). `Capture` writes it; `Check` reads it and re-measures the tools named in it.
- `-Tools` — command names to record (not paths). Defaults to `git,dotnet,cl,cmake,python`.

## What gets recorded

For each tool, the lockfile (format version 1) stores:

- **Winner** — what `Get-Command -All` resolves first: its type (application, external script, alias, cmdlet/function), the alias target when it is an alias, the module when there is one, and — for files — the full path, SHA-256 hash, and PE architecture.
- **PathMatches** — every matching file found by scanning `PATH` in order, honoring `PATHEXT`, each with its rank, full path, SHA-256 hash, and PE architecture. Duplicates are reported once.
- Capture time (UTC) and computer name, for context.

`Check` compares everything except capture time and computer name — including hashes and the ordering of all `PATH` matches — and prints what changed: the old and new winners, the before/after `PATH` match lists when those changed, or a note that a file's hash or architecture changed.

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | Capture succeeded, or `Check` found no drift (`No tool-resolution drift detected.`) |
| 2 | `Check` found drift |
| other | An error (for example, a missing or unsupported lockfile) |

Exit code 2 makes `Check` usable as a CI preflight step: the build fails when the toolchain is not the one that was locked.

## What it deliberately does *not* claim

ResolveLock reports **PowerShell command resolution** and a separate `PATH` inventory. It does not claim to reproduce every native Windows process-search rule (for example, application directories, App Paths registry entries, or the exact search order `CreateProcess` uses). The `PATH` inventory is diagnostic evidence, presented in `PATH` order — treat it that way.

## Privacy / publishing note

The lockfile contains local executable paths and hashes. Paths can reveal user names, install layouts, and machine-specific details. **Review a lockfile before committing or publishing it**, the same way you would review any diagnostic capture.

## Requirements

- Windows
- Windows PowerShell 5.1 or newer (also runs under PowerShell 7 on Windows)

The script refuses to run on a non-Windows OS by design.

## Verification status

- **Verified:** the script parses with zero errors under the PowerShell parser; the PE-architecture reader was exercised against synthetic PE files and correctly reported `x64`, `x86`, and "not a PE" for a non-PE file, and file hashing returned the expected SHA-256.
- **Unverified:** a full `Capture` → `Check` run on a real Windows machine under Windows PowerShell 5.1. That on-machine run is still owed; results here come from a Linux-hosted PowerShell 7 parser/harness, which does not prove 5.1-on-Windows behavior.

## License

MIT — see [LICENSE](LICENSE).
