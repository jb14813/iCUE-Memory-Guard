#Requires -Version 5.1
[CmdletBinding()]
param([ValidateSet('Status','Check','Install','Restore','Uninstall')][string]$Action='Status',[switch]$Json,[switch]$Quiet)
$ErrorActionPreference='Stop'
function AssertSafeParents([string]$Path){
 $parent=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path))
 while($parent){
  if(Test-Path -LiteralPath $parent){if((Get-Item -LiteralPath $parent -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'A parent directory is a reparse point'}}
  $next=[IO.Path]::GetDirectoryName($parent);if($next -eq $parent){break};$parent=$next
 }
}
function Resolve-ServiceTarget([string]$PathName){
 $value=$PathName.Trim()
 if($value -match '^"([^"]+)"$'){$value=$Matches[1]}elseif($value.Contains('"')){throw 'Service path contains arguments or unmatched quotes'}
 if($value -notmatch '^[A-Za-z]:\\' -or [IO.Path]::GetFileName($value) -ine 'CorsairCpuIdService.exe' -or $value.Contains('/') -or $value.Substring(2).Contains(':')){throw 'Service requires an absolute local CorsairCpuIdService.exe path without arguments'}
 if([IO.Path]::GetFullPath($value) -ine $value){throw 'Service path must be canonical'}
 AssertSafeParents $value
 $value
}
function AssertAdministrator {
 $principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
 if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Administrator access is required'}
}
function ValidateRoot([string]$ExpectedTarget){
 AssertSafeParents (Join-Path $managedRoot 'owner.json')
 if(-not (Test-Path -LiteralPath $managedRoot)){return}
 $item=Get-Item -LiteralPath $managedRoot -Force
 if(-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Managed directory is not a regular directory'}
 if((Get-Acl -LiteralPath $managedRoot).GetOwner([Security.Principal.SecurityIdentifier]).Value -ne 'S-1-5-32-544'){throw 'Managed directory has an unexpected owner'}
 if(-not (Test-Path -LiteralPath $marker)){throw 'Managed directory has no ownership record'}
 AssertManagedFile $marker
 if((Get-Item -LiteralPath $marker).Length -gt 16384){throw 'Invalid ownership record'}
 $owner=Get-Content -LiteralPath $marker -Raw|ConvertFrom-Json
 if($owner.Owner -ne 'JZBApps-CorsairCpuIdFix' -or $owner.Schema -ne 1 -or ($ExpectedTarget -and $owner.Target -ine $ExpectedTarget)){throw 'Managed directory belongs to a different installation'}
}
function SetOwnershipInactive {
 if(-not (Test-Path -LiteralPath $managedRoot)){return}
 AssertAdministrator
 ValidateRoot $target
 $owner=Get-Content -LiteralPath $marker -Raw|ConvertFrom-Json
 $owner|Add-Member -NotePropertyName Active -NotePropertyValue $false -Force
 WritePrivateJson $marker $owner
}
function ProcessExists([int]$ProcessId){
 try{$process=[Diagnostics.Process]::GetProcessById($ProcessId)}catch [ArgumentException]{return $false}
 try{-not $process.HasExited}finally{$process.Dispose()}
}
function Hash([string]$Path){
 AssertManagedFile $Path
 $stream=[IO.File]::OpenRead($Path);$algorithm=[Security.Cryptography.SHA256]::Create()
 try{[BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-','')}finally{$algorithm.Dispose();$stream.Dispose()}
}
function AssertManagedFile([string]$Path){
 AssertSafeParents $Path
 if(-not (Test-Path -LiteralPath $Path)){return}
 if((Get-Item -LiteralPath $Path -Force).PSIsContainer){throw 'Expected a regular file'}
 if(-not ('JzbCorsairFileGuard' -as [type])){
  Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class JzbCorsairFileGuard {
 [StructLayout(LayoutKind.Explicit,Size=52)]struct Info{[FieldOffset(40)]public uint Links;}
 [DllImport("kernel32.dll",SetLastError=true)]static extern bool GetFileInformationByHandle(SafeFileHandle file,out Info info);
 public static void Check(string path){
  if((File.GetAttributes(path)&FileAttributes.ReparsePoint)!=0)throw new IOException("Managed file is a reparse point");
  using(var file=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete)){
   Info info;if(!GetFileInformationByHandle(file.SafeFileHandle,out info))throw new Win32Exception(Marshal.GetLastWin32Error());
   if(info.Links!=1)throw new IOException("Managed file has multiple hard links");
  }
 }
}
'@
 }
 [JzbCorsairFileGuard]::Check($Path)
}
function SecureFile([string]$Path){
 AssertManagedFile $Path
 $acl=New-Object Security.AccessControl.FileSecurity
 $acl.SetAccessRuleProtection($true,$false);$acl.SetOwner($adminSid)
 foreach($sid in @($adminSid,$systemSid)){$acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid,'FullControl','Allow')))}
 $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($userSid,'ReadAndExecute','Allow')))
 Set-Acl -LiteralPath $Path -AclObject $acl
}
function ProtectDirectory([string]$Path){
 AssertSafeParents (Join-Path $Path 'guard.bin')
 $item=Get-Item -LiteralPath $Path -Force
 if(-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Transaction directory is unsafe'}
 $acl=New-Object Security.AccessControl.DirectorySecurity
 $acl.SetAccessRuleProtection($true,$false);$acl.SetOwner($adminSid)
 foreach($sid in @($adminSid,$systemSid)){$acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow')))}
 $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($userSid,'ReadAndExecute','ContainerInherit,ObjectInherit','None','Allow')))
 Set-Acl -LiteralPath $Path -AclObject $acl
}
function CopyNewFile([string]$Source,[string]$Destination){
 AssertManagedFile $Source;AssertManagedFile $Destination
 $inputStream=[IO.File]::Open($Source,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
 try{
  $outputStream=[IO.File]::Open($Destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try{$inputStream.CopyTo($outputStream);$outputStream.Flush($true)}finally{$outputStream.Dispose()}
 }finally{$inputStream.Dispose()}
 SecureFile $Destination
}
function NewTransactionDirectory([string]$Destination){
 AssertManagedFile $Destination
 $directory=Join-Path (Split-Path $Destination -Parent) ('.jzb-icue-'+[guid]::NewGuid().ToString('n'))
 $null=New-Item -ItemType Directory -Path $directory -ErrorAction Stop
 try{ProtectDirectory $directory}catch{[IO.Directory]::Delete($directory);throw}
 $directory
}
function AtomicReplace([string]$Stage,[string]$Destination,[string]$Backup){
 [IO.File]::Replace($Stage,$Destination,$Backup)
}
function WritePrivateJson([string]$Path,$Value){
 AssertManagedFile $Path
 [IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 10),(New-Object Text.UTF8Encoding($false)))
 SecureFile $Path
}
function EnsureRoot {
 ValidateRoot $target
 if(-not (Test-Path -LiteralPath $managedRoot)){$null=New-Item -ItemType Directory -Path $managedRoot}
 $acl=New-Object Security.AccessControl.DirectorySecurity
 $acl.SetAccessRuleProtection($true,$false);$acl.SetOwner($adminSid)
 foreach($sid in @($adminSid,$systemSid)){$acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow')))}
 $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($userSid,'ReadAndExecute','ContainerInherit,ObjectInherit','None','Allow')))
 Set-Acl -LiteralPath $managedRoot -AclObject $acl
 WritePrivateJson $marker ([pscustomobject]@{Owner='JZBApps-CorsairCpuIdFix';Schema=1;Target=$target;Active=$true})
}
function StopCpuId {
 $dependent=@((Get-Service -Name $serviceName).DependentServices|Where-Object Status -eq Running)
 if($dependent.Count){throw 'CPU-ID has running dependent services; nothing else will be stopped'}
 $controller=New-Object ServiceProcess.ServiceController($serviceName)
 try{if($controller.Status -ne 'Stopped'){
  $oldId=(Get-CimInstance Win32_Service -Filter "Name='$serviceName'").ProcessId
  $script:StoppingCpuIdPid=$oldId
  if($controller.Status -ne 'StopPending'){$controller.Stop()}
  $controller.WaitForStatus('Stopped',[TimeSpan]::FromSeconds(30))
  if($oldId){
   $process=$null
   try{$process=[Diagnostics.Process]::GetProcessById($oldId)}catch [ArgumentException]{}
   if($process){try{if(-not $process.WaitForExit(10000)){throw 'Previous CPU-ID process has not exited; no replacement or additional instance will be started'}}finally{$process.Dispose()}}
  }
  $script:StoppingCpuIdPid=0
 }}finally{$controller.Dispose()}
}
function StartCpuId {
 if($script:StoppingCpuIdPid -and (ProcessExists $script:StoppingCpuIdPid)){
  $existing=Get-CimInstance Win32_Service -Filter "Name='$serviceName'"
  if($existing.State -eq 'Running' -and $existing.ProcessId -eq $script:StoppingCpuIdPid){return $existing}
  throw 'Previous CPU-ID process is still alive; refusing to start another instance'
 }
 $controller=New-Object ServiceProcess.ServiceController($serviceName)
 try{
  if($controller.Status -eq 'StopPending'){$controller.WaitForStatus('Stopped',[TimeSpan]::FromSeconds(30));$controller.Refresh()}
  if($controller.Status -eq 'Stopped'){$controller.Start()}
  $controller.WaitForStatus('Running',[TimeSpan]::FromSeconds(30))
 }finally{$controller.Dispose()}
 Start-Sleep -Seconds 5
 $service=Get-CimInstance Win32_Service -Filter "Name='$serviceName'"
 if($service.State -ne 'Running' -or -not $service.ProcessId){throw 'CPU-ID service did not remain running'}
 $service
}
function SecureStage([string]$Source,[string]$Expected,[string]$Name){
 AssertManagedFile $Source
 $stage=Join-Path $managedRoot $Name
 if(Test-Path -LiteralPath $stage){AssertManagedFile $stage;if((Hash $stage) -ne $Expected){throw 'Existing stage checksum mismatch'};SecureFile $stage}
 else{CopyNewFile $Source $stage}
 if((Hash $stage) -ne $Expected){throw 'Staged image checksum mismatch'}
 $stage
}
function RestorePreparedImage([string]$Recovery,[string]$PreviousHash,[string]$ReplacementHash,[string]$Destination=$target){
 AssertManagedFile $Recovery
 AssertManagedFile $Destination
 if((Hash $Recovery) -ne $PreviousHash){throw 'Prepared recovery image checksum mismatch'}
 if(Test-Path -LiteralPath $Destination){
  $found=Hash $Destination
  if($found -eq $PreviousHash){return}
  if($found -ne $ReplacementHash){throw 'Installed image changed externally; recovery will preserve it'}
 }
 # Recheck through an exclusive writer handle. A path hash followed by Copy
 # leaves a window in which recovery could overwrite an external update.
 $bytes=[IO.File]::ReadAllBytes($Recovery)
 $algorithm=[Security.Cryptography.SHA256]::Create()
 try{
  if([BitConverter]::ToString($algorithm.ComputeHash($bytes)).Replace('-','') -ne $PreviousHash){throw 'Prepared recovery changed while reading'}
  $existed=Test-Path -LiteralPath $Destination
  $mode=if($existed){[IO.FileMode]::Open}else{[IO.FileMode]::CreateNew}
  $stream=[IO.File]::Open($Destination,$mode,[IO.FileAccess]::ReadWrite,[IO.FileShare]::Read)
  try{
   if($existed){
    $found=[BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-','')
    if($found -eq $PreviousHash){return}
    if($found -ne $ReplacementHash){throw 'Installed image changed externally during recovery; preserving it'}
   }
   $stream.Position=0;$stream.Write($bytes,0,$bytes.Length);$stream.SetLength($bytes.Length);$stream.Flush($true)
  }finally{$stream.Dispose()}
 }finally{$algorithm.Dispose()}
 if((Hash $Destination) -ne $PreviousHash){throw 'Recovered image checksum mismatch'}
}
function ReplacePreparedImages($Images){
 foreach($image in $Images){
  if($image.CurrentHash -eq $image.DesiredHash){continue}
  AssertManagedFile $image.Stage
  AssertManagedFile $image.Target
  if((Hash $image.Stage) -ne $image.DesiredHash){throw 'Prepared image checksum mismatch'}
  if((Test-Path -LiteralPath $image.Target) -and (Hash $image.Target) -ne $image.CurrentHash){throw 'Installed image changed before replacement'}
  # ReplaceFile requires all three paths on the destination volume. The
  # permanent originals and captured recovery images remain in ProgramData.
  $transaction=NewTransactionDirectory $image.Target
  $localStage=Join-Path $transaction 'replacement.bin';$localBackup=Join-Path $transaction 'replaced.bin'
  $capturedHash=$null
  try{
   CopyNewFile $image.Stage $localStage
   if((Hash $localStage) -ne $image.DesiredHash){throw 'Local transaction stage checksum mismatch'}
   if((Test-Path -LiteralPath $image.Target) -and (Hash $image.Target) -ne $image.CurrentHash){throw 'Installed image changed during local staging'}
   $image.ReplacementAttempted=$true
   try{AtomicReplace $localStage $image.Target $localBackup}finally{
    # ReplaceFile can fail after moving the old destination. Its captured
    # image is authoritative even in that documented partial-failure state.
    if(Test-Path -LiteralPath $localBackup){
     $image.Recovery=$localBackup
     $capturedHash=Hash $localBackup
     $image|Add-Member -NotePropertyName RecoveryHash -NotePropertyValue $capturedHash -Force
     SecureFile $localBackup
     $permanent=Join-Path $managedRoot ('replaced-'+[guid]::NewGuid().ToString('n')+'.bin')
     CopyNewFile $localBackup $permanent
     if((Hash $permanent) -ne $capturedHash){throw 'Captured recovery retention checksum mismatch'}
     $image.Recovery=$permanent
     AssertManagedFile $localBackup;Remove-Item -LiteralPath $localBackup -Force
    }
   }
   if(-not $capturedHash){throw 'Native replacement did not retain a recovery image'}
   if($capturedHash -ne $image.CurrentHash){throw 'An external image changed during replacement; its captured image is preserved for recovery'}
   if((Hash $image.Target) -ne $image.DesiredHash){throw 'Installed image checksum mismatch'}
  }finally{
   AssertSafeParents $localStage
   if(Test-Path -LiteralPath $localStage){AssertManagedFile $localStage;Remove-Item -LiteralPath $localStage -Force}
   # Never recursively delete a transaction directory. If recovery retention
   # failed, the protected captured image remains available beside the target.
   if(-not @(Get-ChildItem -LiteralPath $transaction -Force).Count){[IO.Directory]::Delete($transaction)}
  }
 }
}
function RestoreChangedImages($Images){
 $errors=New-Object 'Collections.Generic.List[string]'
 for($index=$Images.Count-1;$index -ge 0;$index--){
  $image=$Images[$index]
  if(-not $image.ReplacementAttempted){continue}
  $recoveryHash=if($image.PSObject.Properties['RecoveryHash']){$image.RecoveryHash}else{$image.CurrentHash}
  try{RestorePreparedImage $image.Recovery $recoveryHash $image.DesiredHash $image.Target}catch{$errors.Add($_.Exception.Message)}
 }
 if($errors.Count){throw ($errors -join '; ')}
}
function Invoke-MemoryGuard([string]$RequestedAction,[string]$RepositoryRoot){
 $serviceName='CorsairCpuIdService'
 $managedRoot=Join-Path $env:ProgramData 'JZBApps-CorsairCpuIdFix'
 $marker=Join-Path $managedRoot 'owner.json'
 $adminSid=New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')
 $systemSid=New-Object Security.Principal.SecurityIdentifier('S-1-5-18')
 $userSid=[Security.Principal.WindowsIdentity]::GetCurrent().User
 $script:StoppingCpuIdPid=0
 $service=Get-CimInstance Win32_Service -Filter "Name='$serviceName'"
 if(-not $service){
  if($RequestedAction -eq 'Uninstall'){
   $target=$null;ValidateRoot $null;SetOwnershipInactive
   return [pscustomobject]@{Succeeded=$true;Product='iCUE Memory Guard';Action=$RequestedAction;Installed=$false;RecoveryMaterialPreserved=$true}
  }
  if($RequestedAction -eq 'Status'){return [pscustomobject]@{Succeeded=$true;Product='iCUE Memory Guard';Action=$RequestedAction;Installed=$false}}
  throw 'CorsairCpuIdService is not installed'
 }
 $target=Resolve-ServiceTarget $service.PathName
 $sdk=Join-Path (Split-Path $target -Parent) 'cpuidsdk64.dll'
 ValidateRoot $target
 # Binding content pins. No runtime switch can relax these identities.
 $originalHash='EAB48C956727C5183E42BA053660DF4005ADFBC2372EDD66AD2BD512B1A67943'
 $patchedHash='1FA7ABD748B0052E2DA54717E2FAEC2954AC9B8B061160F6D744F656FBF5B57B'
 $sdkHash='C51DDF2325592AAF91DCD2A814BC2A282269F305353EB04C9C8621C9BC791483'
 $patchedSdkHash='19A4579A06567DDDBE399314499177CE0FDCCF0A029CD01D313F6108229A7879'
 $images=@(
  [pscustomobject]@{Name='Service';Target=$target;OriginalHash=$originalHash;PatchedHash=$patchedHash;Definition=(Join-Path $RepositoryRoot 'patches/service.json');Backup=(Join-Path $managedRoot ('CorsairCpuIdService.original-'+$originalHash.ToLowerInvariant()+'.exe'));CurrentHash=$null;DesiredHash=$null;Stage=$null;Recovery=$null;ReplacementAttempted=$false},
  [pscustomobject]@{Name='Sdk';Target=$sdk;OriginalHash=$sdkHash;PatchedHash=$patchedSdkHash;Definition=(Join-Path $RepositoryRoot 'patches/sdk.json');Backup=(Join-Path $managedRoot ('cpuidsdk64.original-'+$sdkHash.ToLowerInvariant()+'.dll'));CurrentHash=$null;DesiredHash=$null;Stage=$null;Recovery=$null;ReplacementAttempted=$false}
 )
 foreach($image in $images){if(Test-Path -LiteralPath $image.Target){AssertManagedFile $image.Target;$image.CurrentHash=Hash $image.Target}}
 $status=[pscustomobject]@{Succeeded=$true;Product='iCUE Memory Guard';Action=$RequestedAction;Installed=$true;State=$service.State;Pid=$service.ProcessId;Images=@($images|ForEach-Object{
  $verified=$false
  if(Test-Path -LiteralPath $_.Backup){AssertManagedFile $_.Backup;$verified=(Hash $_.Backup) -eq $_.OriginalHash}
  [pscustomobject]@{Name=$_.Name;Hash=$_.CurrentHash;Supported=($_.CurrentHash -in @($_.OriginalHash,$_.PatchedHash));Patched=($_.CurrentHash -eq $_.PatchedHash);OriginalBackupVerified=$verified}
 })}
 if($RequestedAction -eq 'Status'){return $status}
 $unknown=@($images|Where-Object {$_.CurrentHash -notin @($_.OriginalHash,$_.PatchedHash)})
 $owned=@($images|Where-Object {$_.CurrentHash -eq $_.PatchedHash})
 if($unknown.Count){
  if($RequestedAction -in @('Restore','Uninstall') -and -not $owned.Count){
   if($RequestedAction -eq 'Uninstall'){SetOwnershipInactive}
   $status|Add-Member NoteProperty VendorImagesPreserved $true
   $status|Add-Member NoteProperty RecoveryMaterialPreserved $true
   return $status
  }
  if($RequestedAction -in @('Restore','Uninstall')){throw 'A vendor update and an owned patched image form an unsafe mixed pair. Recovery material and manager must be retained; restore a matching vendor pair before uninstalling.'}
  throw 'Unsupported or newer vendor image; refusing to replace it'
 }
 foreach($image in $images){
  if($image.CurrentHash -eq $image.PatchedHash -and -not ($status.Images|Where-Object Name -eq $image.Name).OriginalBackupVerified){throw 'Verified original backup is required for each patched image'}
  $image.DesiredHash=if($RequestedAction -eq 'Install'){$image.PatchedHash}else{$image.OriginalHash}
 }
 if($RequestedAction -eq 'Check'){return $status}
 if(-not @($images|Where-Object {$_.CurrentHash -ne $_.DesiredHash}).Count){
  if($RequestedAction -eq 'Uninstall'){SetOwnershipInactive}
  return $status
 }
 AssertAdministrator
 $dependent=@((Get-Service -Name $serviceName).DependentServices|Where-Object Status -eq Running)
 if($dependent.Count){throw 'CPU-ID has running dependent services; no service was stopped'}
 EnsureRoot
 Import-Module (Join-Path $RepositoryRoot 'src/BytePatch.psm1') -Force -DisableNameChecking
 foreach($image in $images){
  if(Test-Path -LiteralPath $image.Backup){
   AssertManagedFile $image.Backup
   if((Hash $image.Backup) -ne $image.OriginalHash){throw 'Original backup checksum mismatch'}
   SecureFile $image.Backup
  }else{
   if($image.CurrentHash -ne $image.OriginalHash){throw 'Original image unavailable for backup'}
   CopyNewFile $image.Target $image.Backup
   if((Hash $image.Backup) -ne $image.OriginalHash){throw 'Original backup verification failed'}
  }
  if($image.CurrentHash -ne $image.DesiredHash){
   if($RequestedAction -eq 'Install'){
    AssertManagedFile $image.Definition
    $candidate=Join-Path $managedRoot ('candidate-'+[guid]::NewGuid().ToString('n')+'.bin')
    try{
     Apply-BytePatch -SourcePath $image.Backup -DefinitionPath $image.Definition -OutputPath $candidate -ExpectedSourceHash $image.OriginalHash -ExpectedTargetHash $image.PatchedHash
     SecureFile $candidate
     $image.Stage=SecureStage $candidate $image.DesiredHash ('stage-'+$image.DesiredHash.ToLowerInvariant()+'.bin')
    }finally{if(Test-Path -LiteralPath $candidate){AssertManagedFile $candidate;Remove-Item -LiteralPath $candidate -Force}}
   }else{$image.Stage=SecureStage $image.Backup $image.DesiredHash ('stage-'+$image.DesiredHash.ToLowerInvariant()+'.bin')}
  }
  $image.Recovery=SecureStage $image.Target $image.CurrentHash ('recovery-'+$image.CurrentHash.ToLowerInvariant()+'.bin')
 }
 $stopped=$false
 try{
  foreach($image in $images){if((Hash $image.Target) -ne $image.CurrentHash){throw 'Vendor image changed during preparation'}}
  $stopped=$true;StopCpuId
  foreach($image in $images){if((Hash $image.Target) -ne $image.CurrentHash){throw 'Vendor image changed while stopping'}}
  ReplacePreparedImages $images
  foreach($image in $images){if((Hash $image.Target) -ne $image.DesiredHash){throw 'Installed pair checksum mismatch'}}
  $active=StartCpuId
  foreach($image in $images){if((Hash $image.Target) -ne $image.DesiredHash){throw 'Vendor image changed during activation'}}
  if((Resolve-ServiceTarget $active.PathName) -ine $target){throw 'Service executable changed during activation'}
  $result=[pscustomobject]@{Succeeded=$true;Product='iCUE Memory Guard';Action=$RequestedAction;TimeUtc=[DateTime]::UtcNow.ToString('o');ActiveImageHash=$images[0].DesiredHash;ActiveSdkHash=$images[1].DesiredHash;OriginalBackup=$images[0].Backup;OriginalSdkBackup=$images[1].Backup;NewPid=$active.ProcessId;UnsignedLocalPatch=($RequestedAction -eq 'Install')}
  WritePrivateJson (Join-Path $managedRoot 'state.json') $result
  if($RequestedAction -eq 'Uninstall'){SetOwnershipInactive}
  return $result
 }catch{
  $failure=$_.Exception.Message;$rollbackError=$null
  if(@($images|Where-Object ReplacementAttempted).Count){try{StopCpuId;RestoreChangedImages $images}catch{$rollbackError=$_.Exception.Message}}
  try{if($stopped){$null=StartCpuId}}catch{$rollbackError=($rollbackError+'; '+$_.Exception.Message).Trim('; ')}
  $rolledBack=-not @($images|Where-Object {-not (Test-Path -LiteralPath $_.Target) -or (Hash $_.Target) -ne $_.CurrentHash}).Count
  WritePrivateJson (Join-Path $managedRoot 'failure.json') ([pscustomobject]@{Succeeded=$false;Error=$failure;RolledBack=$rolledBack;RollbackError=$rollbackError;RecoveryImages=@($images|Select-Object Name,Target,Recovery,RecoveryHash);TimeUtc=[DateTime]::UtcNow.ToString('o')})
  throw ('Activation failed: '+$failure+'; rollback='+$rolledBack+'; '+$rollbackError)
 }
}
$mutex=$null;$locked=$false
try{
 if($Action -in @('Install','Restore','Uninstall')){
  $mutex=New-Object Threading.Mutex($false,'Global\JZBApps-CorsairCpuIdFix-Manager')
  try{$locked=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$locked=$true}
  if(-not $locked){throw 'Another iCUE Memory Guard operation is in progress'}
 }
 $result=Invoke-MemoryGuard -RequestedAction $Action -RepositoryRoot $PSScriptRoot
 if($Json){$result|ConvertTo-Json -Depth 8}else{if(-not $Quiet){$result}}
 exit 0
}catch{
 $result=[pscustomobject]@{Succeeded=$false;Product='iCUE Memory Guard';Action=$Action;Error=$_.Exception.Message}
 if($Json){$result|ConvertTo-Json -Depth 8}else{[Console]::Error.WriteLine($result.Error)}
 exit 1
}finally{if($locked){$mutex.ReleaseMutex()};if($mutex){$mutex.Dispose()}}
