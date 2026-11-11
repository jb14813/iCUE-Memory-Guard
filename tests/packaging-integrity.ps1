$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$verify=Join-Path $root 'tools/Verify-ReleaseManifest.ps1'
if(-not(Test-Path -LiteralPath $verify)){throw 'Missing release manifest verifier'}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('icue-integrity-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $temp
$key=[Security.Cryptography.RSA]::Create(2048)
$request=New-Object Security.Cryptography.X509Certificates.CertificateRequest('CN=Synthetic release test',$key,[Security.Cryptography.HashAlgorithmName]::SHA256,[Security.Cryptography.RSASignaturePadding]::Pkcs1)
$cert=$request.CreateSelfSigned([DateTimeOffset]::UtcNow.AddDays(-1),[DateTimeOffset]::UtcNow.AddDays(1))
$sha=[Security.Cryptography.SHA256]::Create()
$pin=([BitConverter]::ToString($sha.ComputeHash($cert.RawData))).Replace('-','').ToLowerInvariant()
$certPath=Join-Path $temp 'test.cer';[IO.File]::WriteAllBytes($certPath,$cert.RawData)
$manifest=Join-Path $temp 'SHA256SUMS'
$payload=Join-Path $temp 'payload.txt';[IO.File]::WriteAllText($payload,'synthetic')
function Write-Manifest([string]$Text){
 [IO.File]::WriteAllText($manifest,$Text,(New-Object Text.UTF8Encoding($false)))
 $signature=$key.SignData([IO.File]::ReadAllBytes($manifest),[Security.Cryptography.HashAlgorithmName]::SHA256,[Security.Cryptography.RSASignaturePadding]::Pkcs1)
 [IO.File]::WriteAllText(($manifest+'.sig'),[Convert]::ToBase64String($signature))
}
function Must-Fail([scriptblock]$Action,[string]$Name){$failed=$false;try{& $Action | Out-Null}catch{$failed=$true};if(-not $failed){throw ('Verifier accepted '+$Name)}}
try{
 $line=(Get-FileHash -LiteralPath $payload).Hash.ToLowerInvariant()+'  payload.txt'+"`n"
 Write-Manifest $line
 $result=& $verify -Manifest $manifest -CertificatePath $certPath -ExpectedCertificateSha256 $pin -CheckFiles
 if(-not $result.SignatureVerified -or $result.CheckedFiles -ne 1){throw 'Valid signed manifest was not verified'}
 $releaseVerifier=Join-Path $temp 'Verify-ReleaseManifest.ps1'
 Copy-Item -LiteralPath $verify -Destination $releaseVerifier
 Copy-Item -LiteralPath $certPath -Destination (Join-Path $temp 'JZBApps.cer')
 $project=Join-Path $temp 'project'
 $null=New-Item -ItemType Directory -Path (Join-Path $project 'tools'),(Join-Path $project 'signing')
 $projectVerifier=Join-Path $project 'tools/Verify-ReleaseManifest.ps1'
 Copy-Item -LiteralPath $verify -Destination $projectVerifier
 Copy-Item -LiteralPath $certPath -Destination (Join-Path $project 'signing/JZBApps.cer')
 foreach($script in @($releaseVerifier,$projectVerifier)){
  $previous=$ErrorActionPreference
  try{$ErrorActionPreference='Continue';$output=& powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script -Manifest $manifest -ExpectedCertificateSha256 $pin -CheckFiles 2>&1;$exitCode=$LASTEXITCODE}finally{$ErrorActionPreference=$previous}
  if($exitCode -ne 0 -or ($output -join "`n") -notmatch 'True'){throw ('Standalone manifest verifier did not discover its public certificate: '+($output -join "`n"))}
 }
 Must-Fail {& $verify -Manifest $manifest -CertificatePath $certPath -CheckFiles} 'a substituted certificate'
 [IO.File]::AppendAllText($payload,'tamper')
 Must-Fail {& $verify -Manifest $manifest -CertificatePath $certPath -ExpectedCertificateSha256 $pin -CheckFiles} 'tampered payload'
 [IO.File]::WriteAllText($payload,'synthetic')
 Write-Manifest ($line+$line)
 Must-Fail {& $verify -Manifest $manifest -CertificatePath $certPath -ExpectedCertificateSha256 $pin -CheckFiles} 'duplicate filenames'
 Write-Manifest (('0'*64)+'  ../escape.txt'+"`n")
 Must-Fail {& $verify -Manifest $manifest -CertificatePath $certPath -ExpectedCertificateSha256 $pin -CheckFiles} 'path traversal'
 Write-Manifest ''
 Must-Fail {& $verify -Manifest $manifest -CertificatePath $certPath -ExpectedCertificateSha256 $pin -CheckFiles} 'empty manifest'
 Write-Manifest $line
 [IO.File]::AppendAllText($manifest,'tamper')
 Must-Fail {& $verify -Manifest $manifest -CertificatePath $certPath -ExpectedCertificateSha256 $pin} 'tampered manifest'
 Write-Output 'PASS release integrity: valid signature; certificate substitution, file tamper, duplicate, traversal, empty and manifest tamper rejected'
}finally{
 $cert.Dispose();$key.Dispose();$sha.Dispose()
 $resolved=[IO.Path]::GetFullPath($temp)
 if(-not $resolved.StartsWith(([IO.Path]::GetFullPath([IO.Path]::GetTempPath())),[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'icue-integrity-*'){throw 'Unsafe test cleanup target'}
 Remove-Item -LiteralPath $resolved -Recurse -Force
}
