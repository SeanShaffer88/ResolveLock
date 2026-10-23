# ResolveLock

## TL;DR

Your build uses whatever compiler, SDK tool, or Python your computer happens to find first — and that can silently change when something gets installed or updated. ResolveLock writes down exactly which programs your build finds, where they live, and a fingerprint (hash) of each one. Later, you run it again and it tells you if anything changed. It is one PowerShell script, it works on Windows PowerShell 5.1 or newer, and there is nothing to install.

## Download and install

There is nothing to build and nothing to install — ResolveLock is the single file `ResolveLock.ps1`.

1. Download `ResolveLock.ps1` from the [v0.1.0 release](https://github.com/SeanShaffer88/ResolveLock/releases/tag/v0.1.0), or copy it from this repository.
2. Check the download (optional but recommended). The v0.1.0 script's SHA-256 is:

   ```
   a37cec356e1fdb854c3fd3728ce984f0f05d6bf3d3fc1b261329389dbc608cbd
   ```

   ```powershell
   (Get-FileHash .\ResolveLock.ps1 -Algorithm SHA256).Hash
   ```

3. Put the script wherever you keep build tools, or in the repository whose toolchain you want to lock, and run it from PowerShell (see Usage).

## Requirements

- Windows
- Windows PowerShell 5.1 or newer (it also runs under PowerShell 7 on Windows)
- No modules, no dependencies, no administrator rights

The script checks that it is running on Windows and stops with `ResolveLock is for Windows.` anywhere else.

## Usage

Run ResolveLock in the same kind of PowerShell session that runs your build — the answers depend on that session's `PATH`, aliases, and modules.

Capture a baseline:

```powershell
.\ResolveLock.ps1 -Mode Capture -File .\toolchain.lock.json `
    -Tools git,dotnet,cl,cmake,python
```

Capture prints one line per tool showing what won, for example *(illustrative)*:

```
Captured 5 tools in .\toolchain.lock.json
  git: Application: C:\Program Files\Git\cmd\git.exe [x64]
  python: Application: C:\Python312\python.exe [x64]
```

Check for drift later, or on a CI agent:

```powershell
.\ResolveLock.ps1 -Mode Check -File .\toolchain.lock.json
```

If nothing changed, Check prints `No tool-resolution drift detected.` and exits 0. If something changed, it prints what, for example *(illustrative)*:

```
CHANGED: python
  Was: Application: C:\Python311\python.exe [x64]
  Now: Application: C:\Python312\python.exe [x64]
  PATH matches before:
    C:\Python311\python.exe
  PATH matches now:
    C:\Python312\python.exe
```

### Parameters

| Parameter | Required | Default | Meaning |
| --- | --- | --- | --- |
| `-Mode` | No | `Capture` | `Capture` writes a lockfile; `Check` compares the live machine against an existing lockfile. |
| `-File` | Yes | — | Path to the lockfile. `Capture` writes it; `Check` reads it. |
| `-Tools` | No (Capture) | `git,dotnet,cl,cmake,python` | Command names to record — names, not paths. In `Check` mode the tool list comes from the lockfile, not from this parameter. |

Tool names may contain letters, digits, `_ . + -`, and an optional extension (for example `python.exe`). Passing a path instead of a name is rejected with `Use a command name, not a path`.

### Exit codes

| Code | Meaning |
| --- | --- |
| 0 | Capture succeeded, or `Check` found no drift |
| 2 | `Check` found drift |
| other | An error (for example, a missing lockfile, or a lockfile with an unsupported format version) |

Exit code 2 is the point of Check mode: wire it into a CI preflight step and the build fails when the toolchain is not the one that was locked.

## What it records — feature breakdown

For every tool, the lockfile stores two different views, on purpose:

**The winner** — what PowerShell itself resolves first, from `Get-Command -All`:

- the command type (application, external script, alias, cmdlet, function, and so on)
- for an alias, its target (function bodies are never stored)
- the module the command came from, when there is one
- for a file-backed command: full path, SHA-256 hash, and PE architecture

**Every `PATH` match** — a separate inventory of matching files, found by scanning `PATH` in order:

- directories are taken in `PATH` order, with environment variables expanded and surrounding quotes removed; invalid or inaccessible entries are skipped rather than stopping the scan
- within a directory, extensions are tried in `PATHEXT` order (falling back to `.COM, .EXE, .BAT, .CMD` when `PATHEXT` is empty); if the tool name already has an extension, only that name is matched
- each match is recorded once (duplicates removed), with its rank, full path, SHA-256 hash, and PE architecture

**PE architecture** is read from the file's own PE header, not guessed from its path. Recognized values:

| Machine code | Reported as |
| --- | --- |
| `0x014c` | `x86` |
| `0x8664` | `x64` |
| `0x01c4` | `ARM32` |
| `0xAA64` | `ARM64` |
| anything else | `PE-0x…` (the raw machine code) |
| not a PE file / unreadable | *(empty)* |

**Drift detection in Check mode** compares everything except capture time and computer name: the winner, hashes, architectures, and the ordering of all `PATH` matches. If the set of `PATH` matches changed, both lists are printed; if only a hash or architecture changed, Check says so.

## The lockfile format

`Capture` writes JSON, format version 1. Structure (values shortened with placeholders — this is the shape, not a real capture):

```json
{
  "FormatVersion": 1,
  "CapturedUtc": "<ISO-8601 UTC timestamp>",
  "Computer": "<computer name>",
  "Tools": [
    {
      "Name": "python",
      "Winner": {
        "Type": "Application",
        "Name": "python.exe",
        "AliasTarget": null,
        "Module": "",
        "File": {
          "Path": "<full path to python.exe>",
          "SHA256": "<64 hex characters>",
          "Architecture": "x64"
        }
      },
      "PathMatches": [
        {
          "Rank": 0,
          "Path": "<full path to python.exe>",
          "SHA256": "<64 hex characters>",
          "Architecture": "x64"
        }
      ]
    }
  ]
}
```

A tool that is not found gets `"Winner": null` and an empty `PathMatches` list. `Check` refuses a lockfile whose `FormatVersion` is not 1.

## Project structure

```
ResolveLock.ps1                  the whole tool — one file
tests/Test-PeArchitecture.ps1    smoke test for the PE-architecture reader
tests/Test-OnMachine.ps1         full Capture/Check verification — run on Windows
VERIFY.md                        how to run the on-machine verification
README.md                        this file
CHANGELOG.md                     release history
LICENSE                          MIT license
```

There is no build step and there are no shortcuts or settings — the script's parameters above are the entire interface. (No screenshots: ResolveLock is a console script; the example output above is text.)

## Tests

The smoke test builds synthetic PE files (x64, x86) plus a non-PE file in your temp folder, extracts ResolveLock's reader functions without running Capture/Check, and verifies the architectures and hashing. Run it on Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\Test-PeArchitecture.ps1
```

Expected result: five `PASS:` lines and `All tests passed.`

The full end-to-end test is `tests/Test-OnMachine.ps1` — see [VERIFY.md](VERIFY.md). It runs ResolveLock as a direct child process and checks Capture (exit 0, format-1 lockfile), Check with no drift (exit 0), Check against a tampered lockfile (drift reported, exit 2), and Check with a missing lockfile (fails). Run it on Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\Test-OnMachine.ps1
```

Separately, the script itself parses with zero errors under the PowerShell parser, and the complete Capture → Check cycle — including the tamper test — passes in a simulated Windows environment under PowerShell 7.4 (see Verification status). A run on a real Windows machine under Windows PowerShell 5.1 is **to be confirmed**.

## Troubleshooting

- **`ResolveLock is for Windows.`** — the script was run on a non-Windows OS. It is Windows-only by design.
- **A tool shows `(not found)`.** — PowerShell cannot resolve that name in *this* session and no matching file exists on `PATH`. Check that the tool is installed and that you are in the same kind of session (for example, a Developer PowerShell for Visual Studio for `cl`) that runs your build.
- **`Use a command name, not a path: …`** — `-Tools` takes names like `python`, not `C:\Python312\python.exe`.
- **`Unsupported ResolveLock format in …`** — the lockfile's format version is not 1; re-capture it with this version of the script.
- **Exit code 2 in CI.** — that is Check working as intended: something resolved differently from the lockfile. The output names the tool and shows the before/after winners and `PATH` matches. If the change is intentional, re-capture the lockfile and commit the new one.
- **Drift is printed but the CI step still passes.** — invoke ResolveLock *directly* (as the step's own command, or as a child process via `powershell -File ResolveLock.ps1 …`), not nested inside another script with `& .\ResolveLock.ps1 …`. Observed on PowerShell 7.4: a nested `&` call printed the drift report but the calling process still exited 0, because `exit 2` ends the called script in that arrangement. Details in [VERIFY.md](VERIFY.md).
- **PowerShell refuses to run the script at all** — your execution policy is blocking local scripts. Run it in a session with a policy that allows it, for example `powershell -ExecutionPolicy Bypass -File .\ResolveLock.ps1 -Mode Capture -File .\toolchain.lock.json`, or set a policy you are comfortable with. (Changing execution policy is a machine setting — your call, not this tool's.)

## Privacy

The lockfile contains local executable paths and hashes. Paths can reveal user names, install layouts, and machine-specific details. **Review a lockfile before committing or publishing it**, the same way you would review any diagnostic capture. ResolveLock itself collects nothing, sends nothing anywhere, and has no network code — Capture writes only the lockfile you name.

## Limitations

- ResolveLock reports **PowerShell command resolution** and a separate `PATH` inventory. It deliberately does **not** claim to reproduce every native Windows process-search rule (application directories, App Paths registry entries, the exact search order `CreateProcess` uses, and so on). Treat the `PATH` inventory as diagnostic evidence, in `PATH` order.
- It only records the tools you name (or the defaults). It is not an inventory of everything installed.
- A hash changes whenever the underlying tool file changes — including legitimate tool updates. That sensitivity is the point, but it means a tool update requires a deliberate re-capture.
- Two machines with different install layouts will produce different lockfiles. A lockfile is per-environment evidence, not a portable manifest.

## Verification status

- **Verified:** the script parses with zero errors under the PowerShell parser; the PE-architecture reader and file hashing pass the smoke test in `tests/` (synthetic x64 / x86 / non-PE files); the published v0.1.0 release asset's SHA-256 matches the script in this repository. The complete Capture → Check cycle also passes end to end in a simulated Windows environment (PowerShell 7.4 on Linux, Windows-style `PATH`/`PATHEXT` with synthetic PE tools): Capture wrote a correct format-1 lockfile with hashes and architectures, a clean Check exited 0, a tampered lockfile and a swapped tool file were both reported as drift, and a direct `powershell -File` Check exited exactly 2. The on-machine test script (`tests/Test-OnMachine.ps1`) passes all five of its checks in that same simulated environment.
- **To be confirmed:** a full `Capture` → `Check` run on a real Windows machine under Windows PowerShell 5.1 — the simulated run cannot prove 5.1 or real-Windows behavior (for example, its `Get-Command` winner was not exercised). [VERIFY.md](VERIFY.md) makes this a three-minute job.

## License

MIT — see [LICENSE](LICENSE). Copyright (c) 2026 Sean Shaffer.
