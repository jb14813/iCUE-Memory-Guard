# iCUE Memory Guard

**v0.1.0 · Experimental · Windows 11 x64 · JZB Apps**

A local patch for identified memory allocation paths in Corsair's CPU identification service and its CPUID SDK. It derives the modified files from your installed originals, preserves verified originals for recovery, and reloads the affected service.

[Download Windows installer](https://github.com/jb14813/iCUE-Memory-Guard/releases/download/v0.1.0/iCUEMemoryGuard-Setup-0.1.0.exe) · [Release files](https://github.com/jb14813/iCUE-Memory-Guard/releases/tag/v0.1.0) · [Verify downloads](SIGNING.md)

## Before installing

This is an independent experimental tool, unaffiliated with Corsair or CPUID. Modifying vendor files invalidates their vendor signatures. Windows security policies may prevent the modified files from loading. Instability, loss of sensor functionality or update conflicts are possible. Restore the originals if problems appear.

Compatibility is determined by **exact file contents**, not version labels alone. The tested originals identify themselves as `CorsairCpuIdService.exe` 5.52.93.0 and `cpuidsdk64.dll` 1.3.4.7. Both files must match the published patch definitions. A small vendor update can change those contents and invalidate compatibility or ownership; an update can also overwrite the fix. Unknown files are preserved, and there is no automatic reapplication to an unfamiliar build.

See [validation coverage and exact hashes](VALIDATION.md). The finite local tests do not establish that every iCUE memory leak is fixed or that every system, game and sensor is supported.

## Install, check and restore

1. Download the installer and verify it using [SIGNING.md](SIGNING.md). The installer uses the JZB Apps experimental self-signed certificate; Windows may show an unknown or untrusted publisher warning.
2. Run Setup as administrator. Setup checks compatibility, creates protected recovery material and applies the matching patch pair. Installation reloads `CorsairCpuIdService`; sensor readings may pause briefly.
3. Check again after iCUE updates. An update may replace the fix. Do not copy older patched files over updated vendor files.

The manager is installed under `%ProgramFiles%\JZB Apps\iCUE Memory Guard`. To inspect or restore from an elevated Windows PowerShell window:

```powershell
$manager = Join-Path $env:ProgramFiles 'JZB Apps\iCUE Memory Guard\Manage-iCUEMemoryGuard.ps1'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$manager" -Action Status
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$manager" -Action Check
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$manager" -Action Restore
```

The execution-policy override applies only to each launched PowerShell process; it does not change the stored Windows policy or certificate trust.

`Status` and `Check` are read-only. `Install` applies the supported patch or verifies an existing owned installation. `Restore` restores verified originals only over the exact patched files this tool owns. `Uninstall` performs the manager's recovery operation; use **Windows Settings → Apps → Installed apps → iCUE Memory Guard → Uninstall** to remove the installed application as well.

All actions accept `-Json` and `-Quiet`; failures return a nonzero exit code. Uninstall stops if an owned patch cannot be safely restored. Unknown vendor files are preserved. Recovery material may remain when iCUE is absent or an update has replaced the files; keep it until recovery is resolved. Do not delete backups to bypass an error.

Windows' built-in PowerShell 5.1 runs the tool. It adds no resident process, service, scheduled task, tray icon or driver. No separate runtime or framework installation is required. Setup does not require a Windows reboot or change certificate trust or system security policy.

## Source and builds

The repository contains our source and changed-byte patch definitions, not original or modified Corsair/CPUID images. [GitHub supplies the source archives for v0.1.0](https://github.com/jb14813/iCUE-Memory-Guard/releases/tag/v0.1.0).

Build from Windows PowerShell with Inno Setup 6 installed:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\tools\Build-Installer.ps1"
```

GitHub Actions runs synthetic checks and builds unsigned development artifacts. Release signing uses a retained local JZB Apps key; the key is not included in the repository or CI. See [SIGNING.md](SIGNING.md) for the public verification assets and trust limitations.

## Support

Report reproducible problems through [GitHub issues](https://github.com/jb14813/iCUE-Memory-Guard/issues) or [support@jzbapps.com](mailto:support@jzbapps.com). Include the app version, Windows version, iCUE version, manager Status/Check result and what happened. Review reports for private paths and personal information before sharing. See [SECURITY.md](SECURITY.md) for security reports.

[JZB Apps](https://jzbapps.com) · [License](LICENSE) · [Third-party notices](THIRD-PARTY-NOTICES.txt)
