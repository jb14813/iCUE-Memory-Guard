[CmdletBinding()]
param([string]$CompilerPath)
$ErrorActionPreference='Stop'
if(-not $CompilerPath){$CompilerPath=Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6/ISCC.exe'}
if(-not(Test-Path -LiteralPath $CompilerPath)){throw 'Inno Setup 6 required for package build tests'}
$root=Split-Path $PSScriptRoot -Parent
$temp=Join-Path ([IO.Path]::GetTempPath()) ('icue-package-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $temp
try{
 foreach($name in @('tools','installer','branding','signing')){Copy-Item -LiteralPath (Join-Path $root $name) -Destination $temp -Recurse}
 foreach($name in @('VERSION','LICENSE','README.md','VALIDATION.md','SIGNING.md','SECURITY.md','CHANGELOG.md','THIRD-PARTY-NOTICES.txt')){Copy-Item -LiteralPath (Join-Path $root $name) -Destination $temp}
 $null=New-Item -ItemType Directory -Path (Join-Path $temp 'src'),(Join-Path $temp 'patches')
 [IO.File]::WriteAllText((Join-Path $temp 'Manage-iCUEMemoryGuard.ps1'),'param($Action,[switch]$Quiet) exit 99')
 [IO.File]::WriteAllText((Join-Path $temp 'src/BytePatch.psm1'),'# Synthetic packaging-only fixture')
 [IO.File]::WriteAllText((Join-Path $temp 'patches/service.json'),'{}')
 [IO.File]::WriteAllText((Join-Path $temp 'patches/sdk.json'),'{}')
 $build=Join-Path $temp 'tools/Build-Installer.ps1'
 [IO.File]::WriteAllText((Join-Path $temp 'src/vendor.dll'),'forbidden')
 $rejected=$false;try{& $build -CompilerPath $CompilerPath | Out-Null}catch{$rejected=$_.Exception.Message -match 'Unexpected installer payload'}
 if(-not $rejected){throw 'Builder accepted a vendor binary payload'}
 Remove-Item -LiteralPath (Join-Path $temp 'src/vendor.dll')
 $certificatePath=Join-Path $temp 'signing/JZBApps.cer'
 $publicBytes=[IO.File]::ReadAllBytes($certificatePath)
 $testKey=[Security.Cryptography.RSA]::Create(2048)
 $request=New-Object Security.Cryptography.X509Certificates.CertificateRequest('CN=Unrelated synthetic signer',$testKey,[Security.Cryptography.HashAlgorithmName]::SHA256,[Security.Cryptography.RSASignaturePadding]::Pkcs1)
 $testCert=$request.CreateSelfSigned([DateTimeOffset]::UtcNow.AddDays(-1),[DateTimeOffset]::UtcNow.AddDays(1))
 try{
  [IO.File]::WriteAllBytes($certificatePath,$testCert.RawData)
  $rejected=$false;try{& $build -CompilerPath $CompilerPath -SelfSign | Out-Null}catch{$rejected=$_.Exception.Message -match 'pinned JZB Apps certificate'}
  if(-not $rejected){throw 'Builder accepted an unrelated signing identity'}
 }finally{[IO.File]::WriteAllBytes($certificatePath,$publicBytes);$testCert.Dispose();$testKey.Dispose()}
 $release=& (Join-Path $temp 'tools/Build-Release.ps1') -CompilerPath $CompilerPath
 $exe=Join-Path $release.Directory 'iCUEMemoryGuard-Setup-0.1.0.exe'
 $info=[Diagnostics.FileVersionInfo]::GetVersionInfo($exe)
 if($info.ProductName.Trim() -ne 'iCUE Memory Guard' -or $info.CompanyName.Trim() -ne 'JZB Apps' -or $info.ProductVersion.Trim() -ne '0.1.0'){throw ('Installer metadata is incorrect: '+$info.ProductName+' / '+$info.CompanyName+' / '+$info.ProductVersion)}
 if((Get-AuthenticodeSignature -LiteralPath $exe).Status -ne 'NotSigned'){throw 'CI build must be unsigned'}
 $files=@(Get-ChildItem -LiteralPath $release.Directory -File)
 if($files.Count -ne 5){throw 'Unsigned release payload allowlist changed'}
 foreach($line in Get-Content -LiteralPath (Join-Path $release.Directory 'SHA256SUMS')){
  if($line -notmatch '^([a-f0-9]{64})  (.+)$'){throw 'Malformed generated checksum'}
  if((Get-FileHash -LiteralPath (Join-Path $release.Directory $Matches[2])).Hash.ToLowerInvariant() -ne $Matches[1]){throw 'Release checksum calculated before final bytes'}
 }
 $rejected=$false;try{& (Join-Path $temp 'tools/Build-Release.ps1') -CompilerPath $CompilerPath | Out-Null}catch{$rejected=$_.Exception.Message -match 'already exists'}
 if(-not $rejected){throw 'Builder overwrote existing release assets'}
 function Assert-UnsignedRejection([string]$Verifier,[string]$Certificate){
  $arguments=@('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$Verifier,'-Path',$exe)
  if($Certificate){$arguments+=@('-CertificatePath',$Certificate)}
  $previous=$ErrorActionPreference
  try{$ErrorActionPreference='Continue';$output=& powershell.exe @arguments 2>&1;$exitCode=$LASTEXITCODE}finally{$ErrorActionPreference=$previous}
  if($exitCode -eq 0 -or ($output -join "`n") -notmatch 'Missing Authenticode signature'){throw ('Unsigned verifier did not reach signature rejection: '+($output -join "`n"))}
 }
 Assert-UnsignedRejection (Join-Path $temp 'tools/Verify-Release.ps1') $certificatePath
 Assert-UnsignedRejection (Join-Path $temp 'tools/Verify-Release.ps1') ''
 Assert-UnsignedRejection (Join-Path $release.Directory 'Verify-Release.ps1') ''
 Write-Output 'PASS package build: vendor payload and unrelated signer rejected; unsigned EXE metadata and final checksums; overwrite and unsigned verification refused'
}finally{
 $resolved=[IO.Path]::GetFullPath($temp)
 if(-not $resolved.StartsWith(([IO.Path]::GetFullPath([IO.Path]::GetTempPath())),[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'icue-package-*'){throw 'Unsafe test cleanup target'}
 Remove-Item -LiteralPath $resolved -Recurse -Force
}
