# Validation coverage

Version 0.1.0 is an experimental release for Windows 11 x64. Local validation used Windows 11 Pro x64, version 10.0.26300, build 26300, with the exact image pair below. These finite observations do not establish compatibility with every iCUE version, Windows policy, CPU, sensor, game or workload.

## Exact image contract

The service and adjacent SDK must match the tested pair by SHA-256. Version resources are descriptive; a matching label alone does not establish compatibility. A different label alone should not reject otherwise matching file contents.

| Image | Tested version label | State | SHA-256 |
| --- | --- | --- | --- |
| CorsairCpuIdService.exe | 5.52.93.0 | Original | `EAB48C956727C5183E42BA053660DF4005ADFBC2372EDD66AD2BD512B1A67943` |
| CorsairCpuIdService.exe | 5.52.93.0 | Patched | `1FA7ABD748B0052E2DA54717E2FAEC2954AC9B8B061160F6D744F656FBF5B57B` |
| cpuidsdk64.dll | 1.3.4.7 | Original | `C51DDF2325592AAF91DCD2A814BC2A282269F305353EB04C9C8621C9BC791483` |
| cpuidsdk64.dll | 1.3.4.7 | Patched | `19A4579A06567DDDBE399314499177CE0FDCCF0A029CD01D313F6108229A7879` |

The public patch definitions describe changed bytes. Original and modified vendor images and private diagnostic captures are not distributed.

## Local observations

- An approximately eight-minute heap trace with the tested patched pair showed BSTR counts of **9 → 9 → 9 → 9 → 9** across the sampled observations, with **zero continuing growth stacks** in that trace.
- CPU temperature and load reporting, and fan response, were exercised locally after the change.

These results support the identified patch paths under those conditions. They do not prove that all memory leaks are fixed, establish zero overhead, cover prolonged use across all workloads, or demonstrate comprehensive game compatibility.

## Recovery and update limits

The tool validates exact original and patched hashes, retains verified originals, and applies the service/SDK pair transactionally. Restore is limited to exact files owned by this patch. Unsupported files or a concurrent vendor update must not be replaced with older vendor images.

Even a small update may change the contents or replace the fix. Check Status and Check after updating. This release installs no background watcher and does not automatically reapply patches to an unfamiliar image. Modified vendor images no longer carry a valid vendor signature, and some Windows application-control policies may block them.

## Release verification

The following checks passed locally for the same tested pair:

- The signed installer adopted an existing matching patch without changing the CPU-ID service process. Actual uninstall restored both exact original hashes and removed the app and uninstall entry. Reinstall restored both exact patched hashes, and Check verified both original backups.
- Windows remained in the same boot session. Other Corsair service states and processes were unchanged across the cycle.
- The installed uninstaller passed pinned-certificate signature verification. Tamper tests rejected changed installer and checksum-manifest copies.
- Isolated Inno Setup failure fixtures verified activation failure exit code 10 with recovery retained, unsafe uninstall refusal with files retained, and failed preflight without an installation.

The release checksums and public signing certificate support download verification; see [SIGNING.md](SIGNING.md). Synthetic tests and CI builds exercise isolated inputs. These local integration checks do not extend compatibility beyond the tested file contents and environment.
