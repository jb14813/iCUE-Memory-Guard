$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
function Assert($Value,$Message){if(-not $Value){throw $Message}}
$required=@('installer/iCUEMemoryGuard.iss','installer/SetupNotes.txt','tools/Build-Installer.ps1','tools/Build-Release.ps1','tools/Verify-Release.ps1','tools/Verify-ReleaseManifest.ps1','tools/Sign-ReleaseManifest.ps1','signing/JZBApps.cer','branding/jzb-apps.ico','branding/wizard-large.png','branding/wizard-small.png','.github/workflows/build.yml','VERSION','LICENSE')
foreach($name in $required){Assert (Test-Path -LiteralPath (Join-Path $root $name) -PathType Leaf) ('Missing package contract file: '+$name)}
$iss=Get-Content -LiteralPath (Join-Path $root 'installer/iCUEMemoryGuard.iss') -Raw
foreach($text in @('CloseApplications=no','AlwaysRestart=no','RestartApplications=no','SignedUninstaller=yes',"RunGuard('Check'", "RunGuard('Install'", "RunGuard('Uninstall'",'Abort;','AppPublisher=JZB Apps','mailto:support@jzbapps.com','iCUEMemoryGuard-Setup-')){Assert ($iss.Contains($text)) ('Missing installer safety contract: '+$text)}
Assert (-not $iss.Contains('RaiseException')) 'Failed activation must retain the installed manager and uninstaller for recovery'
Assert ($iss.Contains("'Setup failed'") -and $iss.Contains('Result := 10')) 'Failed activation must have an explicit failure result and nonzero exit'
Assert ($iss -notmatch '(?im)^\[Run\]|https?://[^\s]+\.(zip|exe)') 'Installer cannot download dependencies or silently ignore manager exit codes'
$notes=Get-Content -LiteralPath (Join-Path $root 'installer/SetupNotes.txt') -Raw
foreach($text in @('5.52.93.0','1.3.4.7','experimental','update','instability','signature')){Assert ($notes -match [regex]::Escape($text)) ('Missing compatibility warning: '+$text)}
$cert=New-Object Security.Cryptography.X509Certificates.X509Certificate2((Join-Path $root 'signing/JZBApps.cer'))
$sha=[Security.Cryptography.SHA256]::Create()
try{$pin=([BitConverter]::ToString($sha.ComputeHash($cert.RawData))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
Assert ($pin -eq '776d8337e24c2f2d0c5b60d8e3778f34a636c0f8de8e1b54e68d081d4a4f6e90') 'Public signer certificate changed'
Assert (-not $cert.HasPrivateKey) 'Never bundle a private signing key'
$workflow=Get-Content -LiteralPath (Join-Path $root '.github/workflows/build.yml') -Raw
Assert ($workflow -match 'contents: read') 'CI requires least read permissions'
Assert ($workflow -notmatch 'secrets\.|contents: write|gh release|SelfSign') 'CI cannot sign or overwrite public releases'
Write-Output 'PASS packaging source contract'
