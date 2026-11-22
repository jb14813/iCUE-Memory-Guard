The runtime uses only Windows PowerShell 5.1 and the published changed-byte JSON definitions.

To reproduce the definitions privately, supply a directory with `reference/CorsairCpuIdService.exe`, `reference/cpuidsdk64.dll`, `candidate-all-owners/CorsairCpuIdService.exe` and `candidate-sdk-complete/cpuidsdk64.dll` to `tools/Export-PatchDefinitions.ps1 -PrivateRoot <directory>`. All four input hashes must match the pinned identities. The tool reads these files and writes only JSON into this repository.

`tools/Verify-PrivateFixtures.ps1 -PrivateRoot <directory>` independently applies the public JSON to those original files, verifies both exact target hashes, and removes its temporary outputs. These tools never change installed service files or services. Never commit or distribute the private images.

For the identified 5.54.46 service, supply its separate private input tree with the same directory layout and pass `-ServiceBuild 5.54.46` to either tool. The selector chooses an exact pinned definition; it does not relax input hashes. The SDK definition is shared because its vendor file contents are identical in the two tested packages.

Run each `tests/core*.ps1` script with Windows PowerShell 5.1. Recovery and lifecycle tests extract functions from the manager AST and use disposable files and service mocks; they do not invoke the manager entry point or change a real service. There is no production test switch or hash bypass.

The 5.54.46 service generator is `development/patch_service_554.py`. It accepts the pinned vendor original and a new output path, adds separate executable/read-only cleanup code and non-executable import data, and preserves original instructions outside the verified ownership sites. Python and `pefile` are development tools only; neither is installed or required by the guard.

Private ABI regressions additionally use `pytest` and `unicorn`. Set `ICUE_SERVICE_REFERENCE` to the original service and `ICUE_TEST_IMAGE` to the derived candidate, then run `python -m pytest development/test_service_554.py -p no:faulthandler`. The checks cover copy-before-free, null forwarding and failed-query output, all ten query arguments, return values, nonvolatile registers, stack alignment, imports, security flags and loader-visible unwind records. The string converter is mocked; these checks establish wrapper behavior rather than native conversion or null safety. They complement live service/heap validation. Keep all vendor inputs, candidates and diagnostics private.
