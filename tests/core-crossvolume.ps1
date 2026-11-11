[CmdletBinding()]
param([string]$SecondaryTestRoot=$env:ICUE_TEST_SECOND_VOLUME,[string]$ManagerPath)
$ErrorActionPreference='Stop'
if(-not $ManagerPath){$ManagerPath=Join-Path (Split-Path $PSScriptRoot -Parent) 'Manage-iCUEMemoryGuard.ps1'}
if(-not $SecondaryTestRoot){Write-Output 'SKIP cross-volume: pass -SecondaryTestRoot with a disposable directory on another local volume';exit 0}
$code=$ManagerPath
$errors=$null;$tokens=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($code,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Manager syntax errors'}
foreach($name in @('AssertSafeParents','Hash','AssertManagedFile','CopyNewFile','NewTransactionDirectory','RestorePreparedImage','AtomicReplace','ReplacePreparedImages','RestoreChangedImages')){
 $node=$ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)|Where-Object Name -eq $name
 if($node){. ([scriptblock]::Create($node.Extent.Text))}
}
$managedRoot=Join-Path ([IO.Path]::GetTempPath()) ('icue-cross-source-'+[guid]::NewGuid().ToString('n'))
$secondary=Join-Path ([IO.Path]::GetFullPath($SecondaryTestRoot)) ('icue-cross-target-'+[guid]::NewGuid().ToString('n'))
if([IO.Path]::GetPathRoot($managedRoot) -eq [IO.Path]::GetPathRoot($secondary)){throw 'Secondary fixture must be on a different local volume'}
$null=New-Item -ItemType Directory $managedRoot,$secondary -Force
function SecureFile([string]$Path){AssertManagedFile $Path}
function ProtectDirectory([string]$Path){AssertSafeParents (Join-Path $Path 'fixture.bin')}
try{
 $old=Join-Path $managedRoot 'old.bin';$new=Join-Path $managedRoot 'new.bin'
 [IO.File]::WriteAllBytes($old,[byte[]](1..100));[IO.File]::WriteAllBytes($new,[byte[]](101..200))
 $oldHash=Hash $old;$newHash=Hash $new
 $images=@(1,2|ForEach-Object {
  $destination=Join-Path $secondary ($_.ToString()+'.bin');Copy-Item $old $destination
  $stage=Join-Path $managedRoot ($_.ToString()+'-stage.bin');Copy-Item $new $stage
  [pscustomobject]@{Target=$destination;CurrentHash=$oldHash;DesiredHash=$newHash;Stage=$stage;Recovery=$old;ReplacementAttempted=$false}
 })
 ReplacePreparedImages $images
 if(@($images|Where-Object {(Hash $_.Target) -ne $newHash -or [IO.Path]::GetPathRoot($_.Recovery) -ne [IO.Path]::GetPathRoot($managedRoot)}).Count){throw 'Cross-volume pair replacement or permanent recovery retention failed'}
 RestoreChangedImages $images
 if(@($images|Where-Object {(Hash $_.Target) -ne $oldHash}).Count){throw 'Cross-volume recovery failed'}
 if(@(Get-ChildItem -LiteralPath $secondary -Force -Directory).Count){throw 'Owned adjacent transaction directories were not cleaned'}
 Write-Output 'PASS cross-volume replacement, permanent backup retention, rollback, and adjacent cleanup (3 assertions)'
}finally{Remove-Item -LiteralPath $managedRoot,$secondary -Recurse -Force}
