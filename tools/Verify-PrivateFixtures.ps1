# Development only. Derive temporary images, prove the exact pins, then remove them.
#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory)][string]$PrivateRoot,[ValidateSet('5.52.93','5.54.46')][string]$ServiceBuild='5.52.93')
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $repo 'src/BytePatch.psm1') -Force -DisableNameChecking
$temp=Join-Path ([IO.Path]::GetTempPath()) ('icue-equivalence-'+[guid]::NewGuid().ToString('n'))
$null=New-Item -ItemType Directory -Path $temp
try{
 $pairs=@(
  @{Name='service';File='CorsairCpuIdService.exe';Original='EAB48C956727C5183E42BA053660DF4005ADFBC2372EDD66AD2BD512B1A67943';Patched='1FA7ABD748B0052E2DA54717E2FAEC2954AC9B8B061160F6D744F656FBF5B57B'},
  @{Name='sdk';File='cpuidsdk64.dll';Original='C51DDF2325592AAF91DCD2A814BC2A282269F305353EB04C9C8621C9BC791483';Patched='19A4579A06567DDDBE399314499177CE0FDCCF0A029CD01D313F6108229A7879'}
 )
 if($ServiceBuild -eq '5.54.46'){
  $pairs[0].Name='service-5.54.46'
  $pairs[0].Original='8E57FD673FB93F3944C840DEC3604FDC225E981175059D7C7C038D558A30566C'
  $pairs[0].Patched='8601196529C4535B0407034416F980D0A6E83E75DD97455334E7FE073AC23DF2'
 }
 foreach($pair in $pairs){
  $output=Join-Path $temp $pair.File
  Apply-BytePatch -SourcePath (Join-Path $PrivateRoot ('reference/'+$pair.File)) -DefinitionPath (Join-Path $repo ('patches/'+$pair.Name+'.json')) -OutputPath $output -ExpectedSourceHash $pair.Original -ExpectedTargetHash $pair.Patched
  $hash=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
  if($hash -ne $pair.Patched){throw 'Private fixture output failed binding SHA-256 verification'}
  [pscustomobject]@{Image=$pair.Name;ExactOutputVerified=$true;Sha256=$hash}
 }
}finally{Remove-Item -LiteralPath $temp -Recurse -Force}
