# Development only. The private input tree is read-only and is never packaged.
#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory)][string]$PrivateRoot)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $repo 'src/BytePatch.psm1') -Force -DisableNameChecking
$pairs=@(
 @{Name='service';Source='reference/CorsairCpuIdService.exe';Target='candidate-all-owners/CorsairCpuIdService.exe';Original='EAB48C956727C5183E42BA053660DF4005ADFBC2372EDD66AD2BD512B1A67943';Patched='1FA7ABD748B0052E2DA54717E2FAEC2954AC9B8B061160F6D744F656FBF5B57B'},
 @{Name='sdk';Source='reference/cpuidsdk64.dll';Target='candidate-sdk-complete/cpuidsdk64.dll';Original='C51DDF2325592AAF91DCD2A814BC2A282269F305353EB04C9C8621C9BC791483';Patched='19A4579A06567DDDBE399314499177CE0FDCCF0A029CD01D313F6108229A7879'}
)
foreach($pair in $pairs){
 $source=Join-Path $PrivateRoot $pair.Source;$target=Join-Path $PrivateRoot $pair.Target
 if((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $pair.Original -or (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $pair.Patched){throw 'Private input pair does not match the binding content pins'}
 Export-BytePatch -SourcePath $source -TargetPath $target -OutputPath (Join-Path $repo ('patches/'+$pair.Name+'.json'))
}
& (Join-Path $PSScriptRoot 'Verify-PrivateFixtures.ps1') -PrivateRoot $PrivateRoot
if(-not $?){throw 'Generated patch verification failed'}
