$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$code=Join-Path $repo 'Manage-iCUEMemoryGuard.ps1'
if(-not (Test-Path $code)){throw 'ASSERT: lifecycle manager has not been implemented'}
$errors=$null;$tokens=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($code,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Manager syntax errors'}
foreach($node in $ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){. ([scriptblock]::Create($node.Extent.Text))}
$root=Join-Path ([IO.Path]::GetTempPath()) ('icue-lifecycle-'+[guid]::NewGuid().ToString('n'))
$null=New-Item -ItemType Directory $root
$script:passed=0
function Assert($Condition,$Message){if(-not $Condition){throw ('ASSERT: '+$Message)};$script:passed++}
function Reject([scriptblock]$Code,$Message){$rejected=$false;try{& $Code|Out-Null}catch{$rejected=$true};Assert $rejected $Message}
try{
 $target=Join-Path $root 'CorsairCpuIdService.exe';$sdk=Join-Path $root 'cpuidsdk64.dll'
 Assert ((Resolve-ServiceTarget ('"'+$target+'"')) -eq $target) 'accept absolute quoted service path'
 Assert ((Resolve-ServiceTarget $target) -eq $target) 'accept absolute unquoted service path'
 foreach($path in @('CorsairCpuIdService.exe',($target+' -arg'),('"'+$target+'" -arg'),(Join-Path $root 'different.exe'),'\\server\share\CorsairCpuIdService.exe','C:relative\CorsairCpuIdService.exe')){Reject {Resolve-ServiceTarget $path} 'reject unsafe service path'}
 # AST-only mocks: production pins stay intact. Never call the real service or installed files.
 $script:exeOriginal='EAB48C956727C5183E42BA053660DF4005ADFBC2372EDD66AD2BD512B1A67943'
 $script:exePatched='1FA7ABD748B0052E2DA54717E2FAEC2954AC9B8B061160F6D744F656FBF5B57B'
 $script:sdkOriginal='C51DDF2325592AAF91DCD2A814BC2A282269F305353EB04C9C8621C9BC791483'
 $script:sdkPatched='19A4579A06567DDDBE399314499177CE0FDCCF0A029CD01D313F6108229A7879'
 $oldProgramData=$env:ProgramData;$env:ProgramData=$root
 $script:fakeService=[pscustomobject]@{State='Running';ProcessId=123;PathName=('"'+$target+'"');Name='CorsairCpuIdService'}
 $script:stops=0;$script:writes=0
 function Get-CimInstance {param($ClassName,$Filter)$script:fakeService}
 function StopCpuId {$script:stops++;throw 'Unexpected stop of service in idempotent/read-only test'}
 function AssertAdministrator {}
 function EnsureRoot {$script:writes++;throw 'Unexpected managed write'}
 function ValidateRoot {param($ExpectedTarget)}
 function Hash([string]$Path){if($Path -eq $target){$script:currentExe}elseif($Path -eq $sdk){$script:currentSdk}elseif($Path -like '*.exe'){$script:exeOriginal}else{$script:sdkOriginal}}
 function AssertManagedFile([string]$Path){}
 [IO.File]::WriteAllText($target,'synthetic');[IO.File]::WriteAllText($sdk,'synthetic')
 $dataRoot=Join-Path $root 'JZBApps-CorsairCpuIdFix';$null=New-Item -ItemType Directory $dataRoot
 [IO.File]::WriteAllText((Join-Path $dataRoot ('CorsairCpuIdService.original-'+$exeOriginal.ToLowerInvariant()+'.exe')),'synthetic')
 [IO.File]::WriteAllText((Join-Path $dataRoot ('cpuidsdk64.original-'+$sdkOriginal.ToLowerInvariant()+'.dll')),'synthetic')
 $script:currentExe=$exePatched;$script:currentSdk=$sdkPatched
 $result=Invoke-MemoryGuard -RequestedAction Install -RepositoryRoot $repo
 Assert $result.Succeeded 'already installed with backups succeeds'
 Assert ($script:stops -eq 0 -and $script:writes -eq 0) 'idempotent install does not restart or rewrite'
 $result=Invoke-MemoryGuard -RequestedAction Check -RepositoryRoot $repo
 Assert $result.Succeeded 'check accepts both verified patched images and original backups'
 $sdkBackup=Join-Path $dataRoot ('cpuidsdk64.original-'+$sdkOriginal.ToLowerInvariant()+'.dll')
 Remove-Item -LiteralPath $sdkBackup
 Reject {Invoke-MemoryGuard -RequestedAction Check -RepositoryRoot $repo} 'check rejects missing original backup for patched image'
 Reject {Invoke-MemoryGuard -RequestedAction Uninstall -RepositoryRoot $repo} 'uninstall refuses to strand a patch without backup'
 [IO.File]::WriteAllText($sdkBackup,'synthetic')
 $script:currentSdk='UNKNOWN'
 Reject {Invoke-MemoryGuard -RequestedAction Install -RepositoryRoot $repo} 'reject unsupported install'
 Reject {Invoke-MemoryGuard -RequestedAction Uninstall -RepositoryRoot $repo} 'mixed unknown and owned patch blocks uninstall'
 Assert ($script:stops -eq 0 -and $script:writes -eq 0) 'unsafe operations fail before lifecycle writes'
 $script:currentExe='UNKNOWN'
 function SetOwnershipInactive {$script:inactive=$true}
 $script:inactive=$false
 $result=Invoke-MemoryGuard -RequestedAction Uninstall -RepositoryRoot $repo
 Assert ($result.Succeeded -and $result.VendorImagesPreserved -and $script:inactive) 'both vendor images preserved and ownership inactive'
 $script:currentExe=$exeOriginal;$script:currentSdk=$sdkOriginal
 $result=Invoke-MemoryGuard -RequestedAction Restore -RepositoryRoot $repo
 Assert ($result.Succeeded -and $script:stops -eq 0) 'already original restore idempotent'
 $script:fakeService=$null
 $result=Invoke-MemoryGuard -RequestedAction Uninstall -RepositoryRoot $repo
 Assert $result.Succeeded 'missing iCUE uninstall preserves recovery and succeeds'
 [pscustomobject]@{Suite='lifecycle';Passed=$script:passed}|ConvertTo-Json -Compress
}finally{$env:ProgramData=$oldProgramData;Remove-Item -LiteralPath $root -Recurse -Force}
