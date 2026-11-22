# Validation coverage

Version 0.2.0 is an experimental release for Windows 11 x64. Local validation used Windows 11 Pro x64, version 10.0.26300, build 26300, with the exact image pairs below. These finite observations do not establish compatibility with every iCUE version, Windows policy, CPU, sensor, game or workload.

## Exact image contract

The service and adjacent SDK must match the tested pair by SHA-256. Version resources are descriptive; a matching label alone does not establish compatibility. A different label alone should not reject otherwise matching file contents.

| Image | Tested version label | State | SHA-256 |
| --- | --- | --- | --- |
| CorsairCpuIdService.exe | 5.52.93.0 | Original | `EAB48C956727C5183E42BA053660DF4005ADFBC2372EDD66AD2BD512B1A67943` |
| CorsairCpuIdService.exe | 5.52.93.0 | Patched | `1FA7ABD748B0052E2DA54717E2FAEC2954AC9B8B061160F6D744F656FBF5B57B` |
| CorsairCpuIdService.exe | 5.54.46.0 | Original | `8E57FD673FB93F3944C840DEC3604FDC225E981175059D7C7C038D558A30566C` |
| CorsairCpuIdService.exe | 5.54.46.0 | Patched | `8601196529C4535B0407034416F980D0A6E83E75DD97455334E7FE073AC23DF2` |
| cpuidsdk64.dll | 1.3.4.7 | Original | `C51DDF2325592AAF91DCD2A814BC2A282269F305353EB04C9C8621C9BC791483` |
| cpuidsdk64.dll | 1.3.4.7 | Patched | `19A4579A06567DDDBE399314499177CE0FDCCF0A029CD01D313F6108229A7879` |

Each listed service build uses the same listed SDK content. The public patch definitions describe changed bytes. Original and modified vendor images and private diagnostic captures are not distributed.

## Local observations: 5.54.46

- Corsair's native update completed with a successful package-history entry and no reboot required. Both stock files had valid vendor signatures before testing.
- Five stock heap snapshots over approximately eight minutes showed 13 continuing-growth stacks. One BSTR path grew **586 → 11,376 → 22,735 → 34,495 → 45,774** retained allocations. Matching version labels did not establish a native leak fix; the SDK file was byte-identical to the earlier affected build.
- A 90-second stock I/O trace lost zero events and found no iCUE process writes in that observation. This is a bounded idle/workload sample, not a guarantee of no disk writes.
- Thirty-six isolated native-code/PE regressions covered the eleven owned-string copies, failed-query cleanup, ten-argument forwarding, return/register/stack preservation, imports, protection flags and unwind records. The independently applied JSON definition reproduced the exact candidate hash.
- Wrapper tests mock the original string converter; they do not establish native conversion or null safety. Its instructions remain unchanged. Conversion exceptions can unwind through the added records but do not gain extra BSTR cleanup; this release does not claim complete exception-path leak coverage.
- The signed installer activated the pair. Actual Restore reproduced both exact vendor originals with valid signatures, and Install reapplied the pair. The CPU-ID service restarted; Windows stayed in the same boot session, and Radeon External Events and the other active Corsair service processes were unchanged.
- With both patches active, five heap snapshots over approximately eight minutes kept BSTR counts at **7 → 7 → 7 → 7 → 7**, with **zero continuing-growth stacks**. The same CPU-ID process remained alive, every captured allocation had a stack, strict analysis rejected lost events/time inversions, and heap snapshot instrumentation was disabled afterward.
- A separate 90-second I/O trace after a clean CPU-ID service start lost zero events and found no iCUE process writes or targeted Radeon cache writes. Seven untraced private-byte samples included startup/cache growth; a private-byte difference alone is not treated as a leak rate.
- Live CPU temperatures and fan response were not visually verified for this build because desktop access was unavailable.

## Local observations: 5.52.93

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
