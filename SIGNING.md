# Download integrity and signing

The experimental v0.1.0 installer is locally signed using the retained JZB Apps self-signed certificate. A self-signed signature does not establish public Windows trust or SmartScreen reputation. Windows may show an unknown or untrusted publisher warning. No certificate is automatically installed or trusted.

Only use assets from the [official v0.1.0 release](https://github.com/jb14813/iCUE-Memory-Guard/releases/tag/v0.1.0):

- `iCUEMemoryGuard-Setup-0.1.0.exe`
- `SHA256SUMS` and its detached signature `SHA256SUMS.sig`
- `JZBApps.cer` (public certificate only)
- `Verify-Release.ps1` and `Verify-ReleaseManifest.ps1`

The public certificate's SHA-256 fingerprint is:

```text
776D8337E24C2F2D0C5B60D8E3778F34A636C0F8DE8E1B54E68D081D4A4F6E90
```

## Verify a download

Download the installer and verification assets into one folder. In Windows PowerShell, compare the certificate fingerprint and installer SHA-256 with the published values:

```powershell
Get-FileHash .\JZBApps.cer -Algorithm SHA256
Get-FileHash .\iCUEMemoryGuard-Setup-0.1.0.exe -Algorithm SHA256
Get-Content .\SHA256SUMS
Get-AuthenticodeSignature .\iCUEMemoryGuard-Setup-0.1.0.exe |
    Format-List Status, StatusMessage, SignerCertificate, TimeStamperCertificate
```

Confirm that the installer hash matches its entry in `SHA256SUMS`. Hash comparison detects changed bytes; the signed manifest additionally binds the checksum list to the pinned JZB key. Use the release's verification scripts for that check. Their documented parameters are available with:

```powershell
Get-Help .\Verify-Release.ps1 -Full
Get-Help .\Verify-ReleaseManifest.ps1 -Full
```

An untrusted-chain result is possible for this self-signed identity. Inspect the expected certificate and use the pinned-key verifier; do not change Windows trust policy merely to remove that warning. If the verifier rejects the signature or a hash differs, do not run the installer. Download fresh copies from the release and report the mismatch to [support@jzbapps.com](mailto:support@jzbapps.com).

Run both pinned-key checks from the download folder:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\Verify-Release.ps1" -Path ".\iCUEMemoryGuard-Setup-0.1.0.exe" -CertificatePath ".\JZBApps.cer"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\Verify-ReleaseManifest.ps1" -Manifest ".\SHA256SUMS" -CertificatePath ".\JZBApps.cer" -CheckFiles
```

The execution-policy override applies only to each launched process; it does not change the stored Windows policy or certificate trust.

The retained public certificate has subject `CN=JZB Apps Radeon Memory Guard Experimental`. The expected identity is determined by its pinned certificate fingerprint; the certificate is also used for this JZB Apps release.

## What is signed

The installer and generated uninstaller use JZB Apps signing. The manifest signature protects the final release checksums. The modified Corsair/CPUID images are generated locally and do **not** retain valid vendor signatures; signing the installer does not restore trust to those modified images.

The private key stays in the local Windows certificate store. GitHub Actions produces unsigned development artifacts and does not replace the signed experimental release assets.
