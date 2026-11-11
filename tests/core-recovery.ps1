$ErrorActionPreference='Stop'
$code=Join-Path (Split-Path $PSScriptRoot -Parent) 'Manage-iCUEMemoryGuard.ps1'
$errors=$null;$tokens=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($code,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Deployment script has syntax errors'}
foreach($name in @('AssertSafeParents','Hash','AssertManagedFile','RestorePreparedImage','ProcessExists','StopCpuId','StartCpuId')){
 $definition=$ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]},$false)|Where-Object Name -eq $name
 . ([ScriptBlock]::Create($definition.Extent.Text))
}
$root=Join-Path ([IO.Path]::GetTempPath()) ('icue-recovery-test-'+[guid]::NewGuid().ToString('n'))
$null=New-Item -ItemType Directory -Path $root
$old=Join-Path $root 'verified-old.exe';$new=Join-Path $root 'known-new.exe';$other=Join-Path $root 'external.exe'
[IO.File]::WriteAllBytes($old,[byte[]](1..128));[IO.File]::WriteAllBytes($new,[byte[]](129..255));[IO.File]::WriteAllBytes($other,[byte[]](16..32))
$oldHash=Hash $old;$newHash=Hash $new;$otherHash=Hash $other
$target=Join-Path $root 'missing-target.exe';$passed=0
RestorePreparedImage $old $oldHash $newHash
if((Hash $target) -ne $oldHash){throw 'Missing-destination recovery failed'};$passed++
$target=Join-Path $root 'replacement-target.exe';Copy-Item -LiteralPath $new -Destination $target
RestorePreparedImage $old $oldHash $newHash
if((Hash $target) -ne $oldHash){throw 'Replacement recovery failed'};$passed++
RestorePreparedImage $old $oldHash $newHash
if((Hash $target) -ne $oldHash){throw 'Already-original recovery changed the image'};$passed++
$target=Join-Path $root 'external-target.exe';Copy-Item -LiteralPath $other -Destination $target
$rejected=$false;try{RestorePreparedImage $old $oldHash $newHash}catch{$rejected=$true}
if(-not $rejected -or (Hash $target) -ne $otherHash){throw 'External update was not preserved'};$passed++
$rejected=$false;try{RestorePreparedImage $other $oldHash $newHash}catch{$rejected=$true}
if(-not $rejected -or (Hash $target) -ne $otherHash){throw 'Corrupt recovery source was accepted'};$passed++
AssertManagedFile $old;$passed++
$alias=Join-Path $root 'hardlink.exe';$null=New-Item -ItemType HardLink -Path $alias -Target $old
$rejected=$false;try{AssertManagedFile $alias}catch{$rejected=$true}
if(-not $rejected){throw 'Managed hardlink was accepted'};$passed++
$replaceSource=Join-Path $root 'replace-source.bin';$replaceTarget=Join-Path $root 'replace-target.bin';$replaceBackup=Join-Path $root 'replace-backup.bin'
[IO.File]::WriteAllBytes($replaceSource,[byte[]](16..128));[IO.File]::WriteAllBytes($replaceTarget,[byte[]](32..96))
$sourceHash=Hash $replaceSource;$targetHash=Hash $replaceTarget
[IO.File]::Replace($replaceSource,$replaceTarget,$replaceBackup)
if((Hash $replaceTarget) -ne $sourceHash -or (Hash $replaceBackup) -ne $targetHash -or (Test-Path -LiteralPath $replaceSource)){throw 'Native replacement with an explicit backup failed'};$passed++
# Simulate SCM reporting Stopped while the old process remains alive. The
# deliberately tracked process is this test process; no real service is used.
$serviceName='IsolatedTestServiceNeverTouched'
$script:StoppingCpuIdPid=0
$script:fakeService=[pscustomobject]@{State='Running';ProcessId=$PID}
$script:controllerCreates=0
$script:fakeController=[pscustomobject]@{Status='Running'}
$script:fakeController|Add-Member ScriptMethod Stop {$this.Status='Stopped';$script:fakeService.State='Stopped'}
$script:fakeController|Add-Member ScriptMethod WaitForStatus {param($state,$timeout)}
$script:fakeController|Add-Member ScriptMethod Dispose {}
function Get-Service {param($Name)[pscustomobject]@{DependentServices=@()}}
function Get-CimInstance {param($ClassName,$Filter)$script:fakeService}
function New-Object {param($TypeName,$ArgumentList)if($TypeName -ne 'ServiceProcess.ServiceController'){throw 'Unexpected constructor in isolated lifecycle test'};$script:controllerCreates++;$script:fakeController}
$timer=[Diagnostics.Stopwatch]::StartNew();$rejected=$false
try{StopCpuId}catch{if($_.Exception.Message -match 'has not exited'){$rejected=$true}else{throw}}
if(-not $rejected -or $timer.Elapsed.TotalSeconds -gt 15 -or $script:StoppingCpuIdPid -ne $PID){throw 'Live prior-process exit did not fail within its bound'};$passed++
$rejected=$false;try{$null=StartCpuId}catch{if($_.Exception.Message -match 'refusing to start another'){$rejected=$true}else{throw}}
if(-not $rejected -or $script:controllerCreates -ne 1){throw 'Recovery attempted another instance while the old process remained alive'};$passed++
$script:fakeService.State='Running'
$same=StartCpuId
if($same.ProcessId -ne $PID -or $script:controllerCreates -ne 1){throw 'Already-running original service was restarted'};$passed++
[pscustomobject]@{Passed=$true;RecoveryAndFileGuardCases=$passed;Evidence=$root}|ConvertTo-Json

Remove-Item -LiteralPath $root -Recurse -Force
