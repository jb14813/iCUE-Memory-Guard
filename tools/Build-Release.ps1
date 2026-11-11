[CmdletBinding()]
param([string]$OutputDirectory,[string]$CompilerPath,[switch]$SelfSign,[string]$SignToolPath)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$version=(Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw).Trim()
if($version -notmatch '^\d+\.\d+\.\d+$'){throw 'Invalid version'}
$destination=if($OutputDirectory){[IO.Path]::GetFullPath($OutputDirectory)}else{Join-Path $root ('build/release-'+$version)}
if(Test-Path -LiteralPath $destination){throw 'Release output already exists; choose a new empty output path to avoid overwriting release assets'}
$installer=& (Join-Path $PSScriptRoot 'Build-Installer.ps1') -CompilerPath $CompilerPath -SelfSign:$SelfSign -SignToolPath $SignToolPath
$null=New-Item -ItemType Directory -Path $destination
Copy-Item -LiteralPath $installer.Path -Destination $destination
Copy-Item -LiteralPath (Join-Path $root 'signing/JZBApps.cer') -Destination $destination
foreach($name in @('Verify-Release.ps1','Verify-ReleaseManifest.ps1')){Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $destination}
$files=@(Get-ChildItem -LiteralPath $destination -File | Sort-Object Name)
$lines=@($files | ForEach-Object {((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant())+'  '+$_.Name})
[IO.File]::WriteAllText((Join-Path $destination 'SHA256SUMS'),($lines -join "`n")+"`n",(New-Object Text.UTF8Encoding($false)))
if($SelfSign){$null=& (Join-Path $PSScriptRoot 'Sign-ReleaseManifest.ps1') -Directory $destination}
[pscustomobject]@{Directory=$destination;Installer=[IO.Path]::GetFileName($installer.Path);Sha256=$installer.Sha256;SelfSigned=[bool]$SelfSign;ManifestSigned=[bool]$SelfSign}
