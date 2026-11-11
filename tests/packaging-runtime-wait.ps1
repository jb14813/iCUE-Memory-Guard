$ErrorActionPreference='Stop'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'packaging-runtime.ps1'),[ref]$tokens,[ref]$errors)
$helper=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Wait-FixtureUninstalled'},$true)
if(-not $helper){throw 'Missing condition-based fixture uninstall wait'}
Invoke-Expression $helper.Extent.Text
$temp=Join-Path ([IO.Path]::GetTempPath()) ('icue-wait-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $temp
$manager=Join-Path $temp 'manager';$uninstaller=Join-Path $temp 'uninstaller';$entry=Join-Path $temp 'entry'
$job=$null
try{
 Wait-FixtureUninstalled $manager $uninstaller $entry 0
 foreach($path in @($manager,$uninstaller,$entry)){
  [IO.File]::WriteAllText($path,'pending')
  $rejected=$false;try{Wait-FixtureUninstalled $manager $uninstaller $entry 0}catch{$rejected=$_.Exception.Message.Contains('Timed out waiting for fixture uninstall cleanup:') -and $_.Exception.Message.Contains($path)}
  if(-not $rejected){throw ('Wait ignored remaining fixture resource: '+$path)}
  Remove-Item -LiteralPath $path
 }
 foreach($path in @($manager,$uninstaller,$entry)){[IO.File]::WriteAllText($path,'pending')}
 $job=Start-Job -ScriptBlock {param($paths) Start-Sleep -Milliseconds 200;foreach($path in $paths){Remove-Item -LiteralPath $path}} -ArgumentList (,@($manager,$uninstaller,$entry))
 Wait-FixtureUninstalled $manager $uninstaller $entry 15000
 if((Test-Path -LiteralPath $manager) -or (Test-Path -LiteralPath $uninstaller) -or (Test-Path -LiteralPath $entry)){throw 'Wait returned before asynchronous fixture cleanup completed'}
 $null=Wait-Job $job -Timeout 15
 if($job.State -ne 'Completed'){throw 'Synthetic cleanup job did not complete'}
 Receive-Job $job -ErrorAction Stop | Out-Null
 Write-Output 'PASS fixture cleanup wait: immediate absence, each lingering resource timeout, asynchronous cleanup completion'
}finally{
 if($job){Stop-Job $job -ErrorAction SilentlyContinue;Remove-Job $job -Force -ErrorAction SilentlyContinue}
 $resolved=[IO.Path]::GetFullPath($temp)
 if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'icue-wait-*'){throw 'Unsafe wait test cleanup path'}
 Remove-Item -LiteralPath $resolved -Recurse -Force
}
