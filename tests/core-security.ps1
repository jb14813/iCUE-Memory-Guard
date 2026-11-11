$ErrorActionPreference='Stop'
$code=Join-Path (Split-Path $PSScriptRoot -Parent) 'Manage-iCUEMemoryGuard.ps1'
$errors=$null;$tokens=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($code,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Manager syntax errors'}
foreach($name in @('AssertSafeParents','AssertManagedFile','Hash','CopyNewFile','SecureStage','ValidateRoot','RestorePreparedImage')){
 $node=$ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)|Where-Object Name -eq $name
 . ([scriptblock]::Create($node.Extent.Text))
}
$root=Join-Path ([IO.Path]::GetTempPath()) ('icue-security-'+[guid]::NewGuid().ToString('n'))
$managedRoot=Join-Path $root 'data';$null=New-Item -ItemType Directory $managedRoot -Force
$marker=Join-Path $managedRoot 'owner.json';$target=Join-Path $root 'CorsairCpuIdService.exe';$script:passed=0
function Reject([scriptblock]$Code,[string]$Message){$failed=$false;try{& $Code|Out-Null}catch{$failed=$true};if(-not $failed){throw ('ASSERT: '+$Message)};$script:passed++}
try{
 $source=Join-Path $root 'source.bin';[IO.File]::WriteAllBytes($source,[byte[]](1..100));$expected=Hash $source
 $stage=Join-Path $managedRoot 'stage.bin';[IO.File]::WriteAllBytes($stage,[byte[]](101..200))
 function SecureFile([string]$Path){AssertManagedFile $Path}
 Reject {SecureStage $source $expected 'stage.bin'} 'corrupt existing stage must be refused'
 Remove-Item -LiteralPath $stage
 $null=New-Item -ItemType HardLink -Path $stage -Target $source
 Reject {SecureStage $source $expected 'stage.bin'} 'hardlinked stage must be refused'
 Reject {RestorePreparedImage $stage $expected $expected $target} 'hardlinked recovery must be refused'
 Remove-Item -LiteralPath $stage
 $junction=Join-Path $managedRoot 'junction';$null=New-Item -ItemType Junction -Path $junction -Target $root
 Reject {AssertManagedFile (Join-Path $junction 'source.bin')} 'reparse ancestor must be refused'
 Reject {ValidateRoot $target} 'missing owner record must be refused'
 # Mock only the fixture ACL owner; no ACL or security state is changed.
 $script:ownerSid='S-1-5-32-544'
 function Get-Acl {param($LiteralPath)$acl=[pscustomobject]@{};$acl|Add-Member ScriptMethod GetOwner {param($Type)[pscustomobject]@{Value=$script:ownerSid}};$acl}
 [IO.File]::WriteAllText($marker,'{broken')
 Reject {ValidateRoot $target} 'corrupt ownership JSON must be refused'
 [IO.File]::WriteAllText($marker,('{"Owner":"other","Schema":1,"Target":'+($target|ConvertTo-Json -Compress)+'}'))
 Reject {ValidateRoot $target} 'foreign owner must be refused'
 [IO.File]::WriteAllText($marker,('{"Owner":"JZBApps-CorsairCpuIdFix","Schema":1,"Target":'+($target|ConvertTo-Json -Compress)+'}'))
 ValidateRoot $target;$script:passed++
 Reject {ValidateRoot ($target+'.other')} 'different installation marker must be refused'
 $script:ownerSid='S-1-5-18'
 Reject {ValidateRoot $target} 'unexpected directory owner must be refused'
 $script:ownerSid='S-1-5-32-544'
 $linkedMarker=Join-Path $root 'owner-alias.json';$null=New-Item -ItemType HardLink -Path $linkedMarker -Target $marker
 Reject {ValidateRoot $target} 'hardlinked owner record must be refused'
 [pscustomobject]@{Suite='security';Passed=$script:passed}|ConvertTo-Json -Compress
}finally{
 # Remove the junction explicitly before recursively cleaning this disposable fixture tree.
 if(Test-Path -LiteralPath $junction){[IO.Directory]::Delete($junction)}
 Remove-Item -LiteralPath $root -Recurse -Force
}
