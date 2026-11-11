[CmdletBinding()]
param([string]$CompilerPath,[switch]$SelfSign,[string]$SignToolPath)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$version=(Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw).Trim()
if($version -notmatch '^\d+\.\d+\.\d+$'){throw 'Invalid version'}
if(-not $CompilerPath){$CompilerPath=Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6/ISCC.exe'}
if(-not(Test-Path -LiteralPath $CompilerPath -PathType Leaf)){throw 'Install Inno Setup 6 or pass -CompilerPath'}
# Restrict recursively packaged source to our PowerShell code and tiny definitions.
foreach($folder in @('src','patches')){
 $directory=Get-Item -LiteralPath (Join-Path $root $folder)
 if($directory.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Linked payload directories are forbidden'}
 foreach($item in Get-ChildItem -LiteralPath $directory.FullName -Recurse -Force){
  if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Linked payloads are forbidden'}
  if(-not $item.PSIsContainer){
   if(($folder -eq 'src' -and $item.Extension -notin @('.ps1','.psm1')) -or ($folder -eq 'patches' -and $item.Extension -ne '.json') -or $item.Length -gt 524288){throw ('Unexpected installer payload: '+$item.Name)}
  }
 }
}
$build=Join-Path $root 'build';$null=New-Item -ItemType Directory -Path $build -Force
$arguments=@('/Qp',('/DAppVersion='+$version),('/DSourceRoot='+$root),('/DBuildRoot='+$build))
if($SelfSign){
 $public=New-Object Security.Cryptography.X509Certificates.X509Certificate2((Join-Path $root 'signing/JZBApps.cer'))
 $sha=[Security.Cryptography.SHA256]::Create()
 try{$pin=([BitConverter]::ToString($sha.ComputeHash($public.RawData))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
 if($pin -ne '776d8337e24c2f2d0c5b60d8e3778f34a636c0f8de8e1b54e68d081d4a4f6e90'){throw 'Only the pinned JZB Apps certificate may sign this build'}
 $identity=Get-Item -LiteralPath ('Cert:\CurrentUser\My\'+$public.Thumbprint)
 if(-not $identity.HasPrivateKey -or $identity.Subject -ne 'CN=JZB Apps Radeon Memory Guard Experimental' -or $identity.Issuer -ne $identity.Subject -or [Convert]::ToBase64String($identity.RawData) -ne [Convert]::ToBase64String($public.RawData)){throw 'Only the retained self-signed JZB Apps key may sign this build'}
 if(-not $SignToolPath){$SignToolPath='C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe'}
 if(-not(Test-Path -LiteralPath $SignToolPath -PathType Leaf)){throw 'Provide a Windows SDK SignTool.exe path'}
 $signCommand='$q'+$SignToolPath+'$q sign /fd SHA256 /td SHA256 /tr http://timestamp.digicert.com /s My /sha1 '+$public.Thumbprint+' $f'
 $arguments+='/DSelfSign';$arguments+=('/SJzbOwn='+$signCommand)
}
$arguments+=(Join-Path $root 'installer/iCUEMemoryGuard.iss')
$output=& $CompilerPath @arguments 2>&1
if($LASTEXITCODE -ne 0){throw ('Inno Setup failed: '+($output -join [Environment]::NewLine))}
$exe=Join-Path $build ('iCUEMemoryGuard-Setup-'+$version+'.exe')
if(-not(Test-Path -LiteralPath $exe -PathType Leaf)){throw 'Compiler did not produce an installer'}
if($SelfSign){$null=& (Join-Path $PSScriptRoot 'Verify-Release.ps1') -Path $exe}
elseif((Get-AuthenticodeSignature -LiteralPath $exe).Status.ToString() -ne 'NotSigned'){throw 'Unsigned build unexpectedly has a signing certificate'}
$hash=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()
[pscustomobject]@{Path=$exe;Sha256=$hash;SelfSigned=[bool]$SelfSign}
