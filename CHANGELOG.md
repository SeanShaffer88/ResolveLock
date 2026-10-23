# Changelog

## 0.1.0 — 2026-10-22

- Initial release: `ResolveLock.ps1` with `Capture` and `Check` modes.
- Records the PowerShell-resolved winner for each tool, every `PATH` match in order, each file's SHA-256 hash, and PE architecture (x86 / x64 / ARM32 / ARM64).
- `Check` exits with code 2 when tool-resolution drift is detected, for CI preflight use.
- Requires Windows PowerShell 5.1 or newer; no dependencies.
