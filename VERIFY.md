# Verifying ResolveLock on a real Windows machine

The one check that cannot be done from a Linux or simulated environment is a full Capture → Check run under **Windows PowerShell 5.1**. This page makes that a three-minute job.

## The one-command way

From the root of this repository, in Windows PowerShell 5.1 or newer:

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\Test-OnMachine.ps1
```

The script runs ResolveLock as a direct child process and checks:

1. Capture exits 0 and writes a parseable format-1 lockfile (it prints each default tool's winner and PATH-match count)
2. Check against that fresh lockfile reports no drift and exits 0
3. Check against a tampered lockfile reports the drift and exits **2**
4. Check with a missing lockfile fails instead of silently passing

It writes `ResolveLock-verification.log` in the repo root and exits 0 only if everything passes. It changes nothing on the machine — its lockfiles live in a temp folder that is deleted afterwards. **Send back or paste that log file** and the verification status in the README can be updated from evidence.

For a meaningful winner for `cl`, run it from a *Developer PowerShell for Visual Studio* — that is the session whose resolution a build would actually see, which is exactly what ResolveLock is for.

## The manual way

```powershell
# In the PowerShell session your build uses:
.\ResolveLock.ps1 -Mode Capture -File .\toolchain.lock.json
.\ResolveLock.ps1 -Mode Check   -File .\toolchain.lock.json
# Expect: "No tool-resolution drift detected." and exit code 0 ($LASTEXITCODE in a parent script,
# or the process exit code when run directly).
```

Then change something small — prepend a different Python's folder to `PATH` in a new session — and run Check again: it should name the tool, show the before/after winners, and exit 2.

## One invocation rule that matters

Run ResolveLock **directly** — as the command itself (`.\ResolveLock.ps1 …`), as a CI step's own command, or as a child process (`powershell -File ResolveLock.ps1 …`).

Do not call it from inside another PowerShell script with `& .\ResolveLock.ps1 …` when you depend on its exit code. In testing on PowerShell 7.4, a nested `&` invocation printed the drift report correctly but the caller's process still exited 0 — the `exit 2` ends the called script, not the host, in that arrangement. Whether Windows PowerShell 5.1 behaves the same when nested is part of what the on-machine run above confirms; the direct invocation is verified to exit 2.
