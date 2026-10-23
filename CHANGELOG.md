# Changelog

## 0.1.1 — 2026-10-22

- Fixed: Check now terminates the host process with exit code 2 on drift in **every** invocation mode, using `[Environment]::Exit(2)` instead of the `exit` keyword. In 0.1.0, when the script was invoked nested from another script (the `&` operator), `exit` ended only the called script and the caller continued with exit code 0 — a CI check that found drift could silently pass (observed on PowerShell 7.4; a nested clean Check still returns control to the caller with exit 0, unchanged). Note the consequence: because the process terminates, running Check interactively in your own session will end that session when drift is found — run it as a child process (`powershell -File ResolveLock.ps1 -Mode Check …`) if you want the session to stay open.
- Verified: full simulated-environment suite re-run against 0.1.1 — parse clean, PE smoke test passes, Capture → clean Check (exit 0), tampered Check (exit 2) both directly and nested, on-machine test script passes all five checks. Windows PowerShell 5.1 on a real machine remains to be confirmed (see VERIFY.md).

## 0.1.0 — 2026-10-22

- Initial release: `ResolveLock.ps1` with `Capture` and `Check` modes.
- Records the PowerShell-resolved winner for each tool, every `PATH` match in order, each file's SHA-256 hash, and PE architecture (x86 / x64 / ARM32 / ARM64).
- `Check` exits with code 2 when tool-resolution drift is detected, for CI preflight use.
- Requires Windows PowerShell 5.1 or newer; no dependencies.
