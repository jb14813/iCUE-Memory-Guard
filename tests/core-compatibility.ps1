$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'Manage-iCUEMemoryGuard.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Manager parse errors'}
foreach($node in $ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){. ([scriptblock]::Create($node.Extent.Text))}
$root=Join-Path ([IO.Path]::GetTempPath()) ('icue-compatibility-'+[guid]::NewGuid().ToString('n'))
$null=New-Item -ItemType Directory -Path $root
$previous=$env:ProgramData;$env:ProgramData=$root;$script:passed=0
function Assert($Condition,$Message){if(-not $Condition){throw ('ASSERT: '+$Message)};$script:passed++}
function Reject([scriptblock]$Code,$Message){$rejected=$false;try{& $Code|Out-Null}catch{$rejected=$true};Assert $rejected $Message}
try {
 $script:newOriginal='8E57FD673FB93F3944C840DEC3604FDC225E981175059D7C7C038D558A30566C'
 $script:newPatched='8601196529C4535B0407034416F980D0A6E83E75DD97455334E7FE073AC23DF2'
 $script:sdkOriginal='C51DDF2325592AAF91DCD2A814BC2A282269F305353EB04C9C8621C9BC791483'
 $script:sdkPatched='19A4579A06567DDDBE399314499177CE0FDCCF0A029CD01D313F6108229A7879'
 $definition=Get-Content -LiteralPath (Join-Path $repo 'patches/service-5.54.46.json') -Raw|ConvertFrom-Json
 Assert ($definition.sourceSha256 -eq $newOriginal -and $definition.targetSha256 -eq $newPatched) 'new definition matches manager content pins'
 Assert ((Get-Item -LiteralPath (Join-Path $repo 'patches/service-5.54.46.json')).Length -le 524288) 'definition fits installer payload limit'
 $target=Join-Path $root 'CorsairCpuIdService.exe';$sdk=Join-Path $root 'cpuidsdk64.dll'
 [IO.File]::WriteAllText($target,'fixture');[IO.File]::WriteAllText($sdk,'fixture')
 $script:currentExe=$newOriginal;$script:currentSdk=$sdkOriginal;$script:writes=0
 function Get-CimInstance {param($ClassName,$Filter)[pscustomobject]@{State='Running';ProcessId=123;PathName=('"'+$target+'"');Name='CorsairCpuIdService'}}
 function ValidateRoot {param($ExpectedTarget)}
 function AssertManagedFile([string]$Path){}
 function Hash([string]$Path){if($Path -eq $target){$script:currentExe}elseif($Path -eq $sdk){$script:currentSdk}elseif($Path -like '*.exe'){$script:newOriginal}else{$script:sdkOriginal}}
 function StopCpuId {$script:writes++;throw 'Unexpected service change'}
 function EnsureRoot {$script:writes++;throw 'Unexpected file change'}
 function AssertAdministrator {}
 $r=Invoke-MemoryGuard -RequestedAction Status -RepositoryRoot $repo
 Assert ($r.Images[0].Supported -and -not $r.Images[0].Patched) 'new vendor original recognized without modification'
 Assert ((Invoke-MemoryGuard -RequestedAction Check -RepositoryRoot $repo).Succeeded) 'new original pair passes read-only check'
 $data=Join-Path $root 'JZBApps-CorsairCpuIdFix';$null=New-Item -ItemType Directory -Path $data
 [IO.File]::WriteAllText((Join-Path $data ('CorsairCpuIdService.original-'+$newOriginal.ToLowerInvariant()+'.exe')),'fixture')
 [IO.File]::WriteAllText((Join-Path $data ('cpuidsdk64.original-'+$sdkOriginal.ToLowerInvariant()+'.dll')),'fixture')
 $script:currentExe=$newPatched;$script:currentSdk=$sdkPatched
 $r=Invoke-MemoryGuard -RequestedAction Install -RepositoryRoot $repo
 Assert ($r.Succeeded -and $r.Images[0].Patched -and $r.Images[1].Patched) 'new patched pair adopted idempotently'
 Assert (@($r.Images|Where-Object {-not $_.OriginalBackupVerified}).Count -eq 0) 'both originals verified'
 $script:currentExe='UNRECOGNIZED'
 Reject {Invoke-MemoryGuard -RequestedAction Install -RepositoryRoot $repo} 'unknown service never patched'
 Reject {Invoke-MemoryGuard -RequestedAction Restore -RepositoryRoot $repo} 'unknown service with owned SDK patch preserved as conflict'
 $script:currentExe=$newOriginal;$script:currentSdk='UNRECOGNIZED'
 Reject {Invoke-MemoryGuard -RequestedAction Install -RepositoryRoot $repo} 'new service does not relax SDK identity'
 Assert ($script:writes -eq 0) 'read-only and unsupported operations never change files or services'
 [pscustomobject]@{Suite='compatibility';Passed=$script:passed}|ConvertTo-Json -Compress
}finally{$env:ProgramData=$previous;Remove-Item -LiteralPath $root -Recurse -Force}
