param([string]$ManagerPath=(Join-Path (Split-Path $PSScriptRoot -Parent) 'Manage-iCUEMemoryGuard.ps1'))
$ErrorActionPreference='Stop'
if(-not (Test-Path -LiteralPath $ManagerPath)){throw 'ASSERT: lifecycle manager has not been implemented'}
$parseErrors=$null;$tokens=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($ManagerPath,[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count){throw 'Manager did not parse'}
foreach($name in @('AssertSafeParents','Hash','AssertManagedFile','CopyNewFile','NewTransactionDirectory','RestorePreparedImage','AtomicReplace','ReplacePreparedImages','RestoreChangedImages')){
 $node=$ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)|Where-Object Name -eq $name
 if($node){. ([scriptblock]::Create($node.Extent.Text))}
}
$managedRoot=Join-Path ([IO.Path]::GetTempPath()) ('icue-pair-test-'+[guid]::NewGuid().ToString('n'))
$null=New-Item -ItemType Directory -Path $managedRoot
# ACL ownership is exercised by the elevated installer; disposable file tests retain their user's ACL.
function SecureFile([string]$Path){AssertManagedFile $Path}
function ProtectDirectory([string]$Path){AssertSafeParents (Join-Path $Path 'fixture.bin')}
$old=Join-Path $managedRoot 'old.bin';$new=Join-Path $managedRoot 'new.bin'
[IO.File]::WriteAllBytes($old,[byte[]](1..128));[IO.File]::WriteAllBytes($new,[byte[]](129..255))
$oldHash=Hash $old;$newHash=Hash $new;$passed=0
$target=Join-Path $managedRoot 'exe-target.bin';Copy-Item -LiteralPath $new -Destination $target
$sdkTarget=Join-Path $managedRoot 'sdk-target.bin';Copy-Item -LiteralPath $new -Destination $sdkTarget
RestorePreparedImage $old $oldHash $newHash $sdkTarget
if((Hash $sdkTarget) -ne $oldHash -or (Hash $target) -ne $newHash){throw 'Explicit SDK destination recovery failed or changed the EXE'};$passed++
function Image([string]$Name){
 $destination=Join-Path $managedRoot ($Name+'-target.bin');Copy-Item -LiteralPath $old -Destination $destination
 $stage=Join-Path $managedRoot ($Name+'-stage.bin');Copy-Item -LiteralPath $new -Destination $stage
 $recovery=Join-Path $managedRoot ($Name+'-recovery.bin');Copy-Item -LiteralPath $old -Destination $recovery
 [pscustomobject]@{Name=$Name;Target=$destination;CurrentHash=$oldHash;DesiredHash=$newHash;Stage=$stage;Recovery=$recovery;ReplacementAttempted=$false}
}
$images=@((Image 'success-exe'),(Image 'success-sdk'))
ReplacePreparedImages $images
if(@($images|Where-Object{(Hash $_.Target) -ne $newHash}).Count){throw 'Pair installation failed'};$passed++
RestoreChangedImages $images
if(@($images|Where-Object{(Hash $_.Target) -ne $oldHash}).Count){throw 'Pair restore failed'};$passed++
$images=@((Image 'failure-exe'),(Image 'failure-sdk'))
Remove-Item -LiteralPath $images[1].Stage
$failed=$false;try{ReplacePreparedImages $images}catch{$failed=$true;RestoreChangedImages $images}
if(-not $failed -or @($images|Where-Object{(Hash $_.Target) -ne $oldHash}).Count){throw 'Second-file failure did not recover both originals'};$passed++
$images=@((Image 'missing-exe'),(Image 'missing-sdk'))
Remove-Item -LiteralPath $images[1].Target
$failed=$false;try{ReplacePreparedImages $images}catch{$failed=$true;RestoreChangedImages $images}
if(-not $failed -or @($images|Where-Object{(Hash $_.Target) -ne $oldHash}).Count){throw 'Missing second destination recovery failed'};$passed++
$images=@((Image 'external-exe'),(Image 'external-sdk'))
ReplacePreparedImages $images
[IO.File]::WriteAllBytes($images[1].Target,[byte[]](17..33));$externalHash=Hash $images[1].Target
$failed=$false;try{RestoreChangedImages $images}catch{$failed=$true}
if(-not $failed -or (Hash $images[0].Target) -ne $oldHash -or (Hash $images[1].Target) -ne $externalHash){throw 'External SDK update was overwritten or other image was not recovered'};$passed++
$images=@((Image 'race-exe'),(Image 'race-sdk'))
$realHash=${function:Hash};$raceTarget=$images[1].Target;$injected=$false
function Hash([string]$Path){
 $value=& $realHash $Path
 if($Path -eq $raceTarget -and -not $injected){$script:injected=$true;[IO.File]::WriteAllBytes($Path,[byte[]](17..33))}
 $value
}
$failed=$false
try{ReplacePreparedImages $images}catch{$failed=$true;RestoreChangedImages $images}
Set-Item -LiteralPath Function:\Hash -Value $realHash
$expectedExternal=Join-Path $managedRoot 'expected-external.bin';[IO.File]::WriteAllBytes($expectedExternal,[byte[]](17..33))
if(-not $failed -or -not $injected -or (Hash $images[0].Target) -ne $oldHash -or (Hash $images[1].Target) -ne (Hash $expectedExternal)){throw 'Commit-window SDK update was overwritten during recovery'};$passed++
$images=@((Image 'recovery-race-exe'),(Image 'recovery-race-sdk'))
ReplacePreparedImages $images
$realHash=${function:Hash};$raceTarget=$images[1].Target;$injected=$false
function Hash([string]$Path){
 $value=& $realHash $Path
 if($Path -eq $raceTarget -and -not $injected){$script:injected=$true;[IO.File]::WriteAllBytes($Path,[byte[]](17..33))}
 $value
}
$failed=$false
try{RestoreChangedImages $images}catch{$failed=$true}
Set-Item -LiteralPath Function:\Hash -Value $realHash
if(-not $failed -or -not $injected -or (Hash $images[0].Target) -ne $oldHash -or (Hash $images[1].Target) -ne (Hash $expectedExternal)){throw 'Recovery-window external update was overwritten'};$passed++
$images=@((Image 'linked-exe'),(Image 'linked-sdk'))
$alias=Join-Path $managedRoot 'linked-stage.bin';$null=New-Item -ItemType HardLink -Path $alias -Target $images[1].Stage
$failed=$false;try{ReplacePreparedImages $images}catch{$failed=$true;RestoreChangedImages $images}
if(-not $failed -or @($images|Where-Object{(Hash $_.Target) -ne $oldHash}).Count){throw 'Hardlinked second payload did not fail with pair recovery'};$passed++
$images=@((Image 'native-race-exe'),(Image 'native-race-sdk'))
$script:nativeRaceTarget=$images[1].Target
function AtomicReplace([string]$Stage,[string]$Destination,[string]$Backup){
 if($Destination -eq $script:nativeRaceTarget){[IO.File]::WriteAllBytes($Destination,[byte[]](17..33))}
 [IO.File]::Replace($Stage,$Destination,$Backup)
}
$failed=$false;try{ReplacePreparedImages $images}catch{$failed=$true;RestoreChangedImages $images}
if(-not $failed -or (Hash $images[0].Target) -ne $oldHash -or (Hash $images[1].Target) -ne (Hash $expectedExternal)){throw 'Atomic commit-window update was not preserved and recovered'};$passed++
$images=@((Image 'partial-native-exe'),(Image 'partial-native-sdk'))
$script:partialTarget=$images[1].Target
function AtomicReplace([string]$Stage,[string]$Destination,[string]$Backup){
 if($Destination -eq $script:partialTarget){
  # ReplaceFile can fail after moving an external update to its backup.
  [IO.File]::WriteAllBytes($Destination,[byte[]](17..33));[IO.File]::Move($Destination,$Backup)
  throw 'Synthetic native replacement partial failure'
 }
 [IO.File]::Replace($Stage,$Destination,$Backup)
}
$failed=$false;try{ReplacePreparedImages $images}catch{$failed=$true;RestoreChangedImages $images}
if(-not $failed -or (Hash $images[0].Target) -ne $oldHash -or (Hash $images[1].Target) -ne (Hash $expectedExternal)){throw 'Partial native failure did not recover the authoritative captured update'};$passed++
[pscustomobject]@{Passed=$true;PairRecoveryCases=$passed;Evidence=$managedRoot}|ConvertTo-Json

Remove-Item -LiteralPath $managedRoot -Recurse -Force
