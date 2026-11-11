The runtime uses only Windows PowerShell 5.1 and the published changed-byte JSON definitions.

To reproduce the definitions privately, supply a directory with `reference/CorsairCpuIdService.exe`, `reference/cpuidsdk64.dll`, `candidate-all-owners/CorsairCpuIdService.exe` and `candidate-sdk-complete/cpuidsdk64.dll` to `tools/Export-PatchDefinitions.ps1 -PrivateRoot <directory>`. All four input hashes must match the pinned identities. The tool reads these files and writes only JSON into this repository.

`tools/Verify-PrivateFixtures.ps1 -PrivateRoot <directory>` independently applies the public JSON to those original files, verifies both exact target hashes, and removes its temporary outputs. These tools never change installed service files or services. Never commit or distribute the private images.

Run each `tests/core*.ps1` script with Windows PowerShell 5.1. Recovery and lifecycle tests extract functions from the manager AST and use disposable files and service mocks; they do not invoke the manager entry point or change a real service. There is no production test switch or hash bypass.
