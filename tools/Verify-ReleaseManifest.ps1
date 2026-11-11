[CmdletBinding()]
param(
 [Parameter(Mandatory)][string]$Manifest,
 [string]$CertificatePath,
 [string]$ExpectedCertificateSha256='776d8337e24c2f2d0c5b60d8e3778f34a636c0f8de8e1b54e68d081d4a4f6e90',
 [switch]$CheckFiles
)
$ErrorActionPreference='Stop'
if(-not $CertificatePath){
 $adjacent=Join-Path $PSScriptRoot 'JZBApps.cer'
 $CertificatePath=if(Test-Path -LiteralPath $adjacent -PathType Leaf){$adjacent}else{Join-Path $PSScriptRoot '../signing/JZBApps.cer'}
}
$certificate=New-Object Security.Cryptography.X509Certificates.X509Certificate2((Get-Item -LiteralPath $CertificatePath).FullName)
$sha=[Security.Cryptography.SHA256]::Create()
try{$fingerprint=([BitConverter]::ToString($sha.ComputeHash($certificate.RawData))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
if($ExpectedCertificateSha256 -notmatch '^[0-9a-fA-F]{64}$' -or $fingerprint -ne $ExpectedCertificateSha256.ToLowerInvariant()){throw 'Public certificate SHA-256 fingerprint mismatch'}
$key=[Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($certificate)
try{$valid=$key.VerifyData([IO.File]::ReadAllBytes($Manifest),[Convert]::FromBase64String([IO.File]::ReadAllText($Manifest+'.sig')),[Security.Cryptography.HashAlgorithmName]::SHA256,[Security.Cryptography.RSASignaturePadding]::Pkcs1)}finally{$key.Dispose()}
if(-not $valid){throw 'Release checksum manifest signature is invalid'}
$directory=Split-Path ([IO.Path]::GetFullPath($Manifest)) -Parent
$seen=@{};$count=0
foreach($line in [IO.File]::ReadAllLines($Manifest)){
 if($line -notmatch '^([0-9a-f]{64})  ([A-Za-z0-9][A-Za-z0-9._-]*)$'){throw 'Invalid checksum manifest entry'}
 $expected=$Matches[1];$name=$Matches[2]
 if($seen.ContainsKey($name)){throw 'Duplicate checksum filename'};$seen[$name]=$true
 if($CheckFiles){
  $file=Get-Item -LiteralPath (Join-Path $directory $name)
  if($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Unsafe checksum payload'}
  if((Get-FileHash -LiteralPath $file.FullName).Hash.ToLowerInvariant() -ne $expected){throw ('Release file checksum mismatch: '+$name)}
 }
 $count++
}
if($count -eq 0){throw 'Empty checksum manifest'}
[pscustomobject]@{SignatureVerified=$true;CheckedFiles=$(if($CheckFiles){$count}else{0});SignerThumbprint=$certificate.Thumbprint;CertificateSha256=$fingerprint;Trust='Pinned public key only; no certificate trust is imported'}
