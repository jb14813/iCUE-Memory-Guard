[CmdletBinding()]
param([Parameter(Mandatory)][string]$Directory)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$public=New-Object Security.Cryptography.X509Certificates.X509Certificate2((Join-Path $root 'signing/JZBApps.cer'))
$sha=[Security.Cryptography.SHA256]::Create()
try{$pin=([BitConverter]::ToString($sha.ComputeHash($public.RawData))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
if($pin -ne '776d8337e24c2f2d0c5b60d8e3778f34a636c0f8de8e1b54e68d081d4a4f6e90'){throw 'Public signing identity is not the pinned JZB Apps identity'}
$identity=Get-Item -LiteralPath ('Cert:\CurrentUser\My\'+$public.Thumbprint)
if(-not $identity.HasPrivateKey -or $identity.Subject -ne 'CN=JZB Apps Radeon Memory Guard Experimental' -or $identity.Issuer -ne $identity.Subject -or [Convert]::ToBase64String($identity.RawData) -ne [Convert]::ToBase64String($public.RawData)){throw 'Only the retained self-signed JZB Apps key may sign this manifest'}
$manifest=Join-Path ([IO.Path]::GetFullPath($Directory)) 'SHA256SUMS'
if(-not(Test-Path -LiteralPath $manifest -PathType Leaf)){throw 'Build SHA256SUMS from the final release files before signing'}
$key=[Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($identity)
try{$signature=$key.SignData([IO.File]::ReadAllBytes($manifest),[Security.Cryptography.HashAlgorithmName]::SHA256,[Security.Cryptography.RSASignaturePadding]::Pkcs1)}finally{$key.Dispose()}
[IO.File]::WriteAllText(($manifest+'.sig'),[Convert]::ToBase64String($signature),(New-Object Text.UTF8Encoding($false)))
& (Join-Path $PSScriptRoot 'Verify-ReleaseManifest.ps1') -Manifest $manifest -CertificatePath (Join-Path $root 'signing/JZBApps.cer') -CheckFiles
