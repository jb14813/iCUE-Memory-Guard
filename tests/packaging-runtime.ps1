[CmdletBinding()]
param([switch]$RunInstallerFixtures,[string]$CompilerPath)
$ErrorActionPreference='Stop'
if(-not $RunInstallerFixtures){Write-Output 'SKIP installer runtime fixtures (opt in with -RunInstallerFixtures from elevated Windows PowerShell 5.1)';return}
if([IntPtr]::Size -ne 8){throw 'Run fixture tests using 64-bit Windows PowerShell'}
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$principal=New-Object Security.Principal.WindowsPrincipal($identity)
if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Opt-in installer fixtures require an elevated Windows PowerShell session'}
if(-not $CompilerPath){$CompilerPath=Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6/ISCC.exe'}
if(-not(Test-Path -LiteralPath $CompilerPath -PathType Leaf)){throw 'Inno Setup 6 is required for installer fixtures'}
$root=Split-Path $PSScriptRoot -Parent
$runId=[guid]::NewGuid().ToString('N')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('icue-inno-fixtures-'+$runId)
$null=New-Item -ItemType Directory -Path $temp
$fixtures=New-Object Collections.Generic.List[object]
$completed=$false
function Assert-Fixture([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Wait-FixtureUninstalled([string]$Manager,[string]$Uninstaller,[string]$RegistryPath,[ValidateRange(0,60000)][int]$TimeoutMilliseconds=15000){
 $timer=[Diagnostics.Stopwatch]::StartNew()
 while($true){
  $pending=@($Manager,$Uninstaller,$RegistryPath | Where-Object {Test-Path -LiteralPath $_})
  if($pending.Count -eq 0){return}
  if($timer.ElapsedMilliseconds -ge $TimeoutMilliseconds){throw ('Timed out waiting for fixture uninstall cleanup: '+($pending -join ', '))}
  Start-Sleep -Milliseconds ([Math]::Min(100,[Math]::Max(1,$TimeoutMilliseconds-$timer.ElapsedMilliseconds)))
 }
}
function Invoke-FixtureProcess([string]$Executable,[string]$Log){
 $process=Start-Process -FilePath $Executable -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-',('/LOG="'+$Log+'"')) -WindowStyle Hidden -PassThru
 try{
  $null=$process.Handle
  if(-not $process.WaitForExit(60000)){throw ('Fixture process did not finish within 60 seconds; inspect '+$Log)}
  $process.Refresh()
  return $process.ExitCode
 }finally{$process.Dispose()}
}
function New-InstallerFixture([string]$Kind,[int]$CheckExit){
 $directory=Join-Path $temp $Kind
 $null=New-Item -ItemType Directory -Path $directory,(Join-Path $directory 'installer'),(Join-Path $directory 'src'),(Join-Path $directory 'patches'),(Join-Path $directory 'build')
 $name='iCUE Memory Guard Fixture '+$runId+' '+$Kind
 $appId=[guid]::NewGuid().ToString().ToUpperInvariant()
 $installPath=Join-Path ${env:ProgramW6432} ('JZB Apps\'+$name)
 $registryPath='Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{'+$appId+'}_is1'
 Assert-Fixture (-not(Test-Path -LiteralPath $installPath)) 'Fixture install directory unexpectedly exists'
 Assert-Fixture (-not(Test-Path -LiteralPath $registryPath)) 'Fixture uninstall entry unexpectedly exists'
 $fixture=[pscustomobject]@{Name=$name;Path=$directory;InstallPath=$installPath;RegistryPath=$registryPath;Installer=(Join-Path $directory 'build/iCUEMemoryGuard-Setup-0.1.0.exe')}
 $fixtures.Add($fixture)
 Copy-Item -LiteralPath (Join-Path $root 'branding') -Destination $directory -Recurse
 foreach($file in @('README.md','VALIDATION.md','SIGNING.md','SECURITY.md','CHANGELOG.md','THIRD-PARTY-NOTICES.txt','LICENSE','VERSION')){Copy-Item -LiteralPath (Join-Path $root $file) -Destination $directory}
 Copy-Item -LiteralPath (Join-Path $root 'installer/SetupNotes.txt') -Destination (Join-Path $directory 'installer/SetupNotes.txt')
 $script=[IO.File]::ReadAllText((Join-Path $root 'installer/iCUEMemoryGuard.iss'))
 $script=$script.Replace('iCUE Memory Guard',$name)
 $script=[regex]::Replace($script,'(?m)^AppId=.*$',('AppId={{'+$appId+'}'))
 [IO.File]::WriteAllText((Join-Path $directory 'installer/iCUEMemoryGuard.iss'),$script,(New-Object Text.UTF8Encoding($false)))
 # This fixture manager has no imports, service APIs, vendor paths or patching code.
 $manager=@'
param([string]$Action,[switch]$Quiet)
$ErrorActionPreference='Stop'
switch($Action){
 'Check' { exit __CHECK_EXIT__ }
 'Install' { exit 29 }
 'Uninstall' { if(Test-Path -LiteralPath (Join-Path $PSScriptRoot 'allow-fixture-uninstall.tag')){exit 0};exit 31 }
 default { exit 99 }
}
'@
 [IO.File]::WriteAllText((Join-Path $directory 'Manage-iCUEMemoryGuard.ps1'),$manager.Replace('__CHECK_EXIT__',[string]$CheckExit),(New-Object Text.UTF8Encoding($false)))
 [IO.File]::WriteAllText((Join-Path $directory 'src/BytePatch.psm1'),'# Synthetic fixture only')
 [IO.File]::WriteAllText((Join-Path $directory 'patches/service.json'),'{}')
 [IO.File]::WriteAllText((Join-Path $directory 'patches/sdk.json'),'{}')
 $arguments=@('/Qp','/DAppVersion=0.1.0',('/DSourceRoot='+$directory),('/DBuildRoot='+(Join-Path $directory 'build')),(Join-Path $directory 'installer/iCUEMemoryGuard.iss'))
 $output=& $CompilerPath @arguments 2>&1
 if($LASTEXITCODE -ne 0){throw ('Fixture compile failed: '+($output -join "`n"))}
 Assert-Fixture (Test-Path -LiteralPath $fixture.Installer -PathType Leaf) 'Fixture installer was not compiled'
 return $fixture
}
function Enable-FixtureUninstall($Fixture){
 $expected=Join-Path ${env:ProgramW6432} ('JZB Apps\iCUE Memory Guard Fixture '+$runId+' '+[IO.Path]::GetFileName($Fixture.Path))
 Assert-Fixture ([IO.Path]::GetFullPath($Fixture.InstallPath) -eq [IO.Path]::GetFullPath($expected)) 'Unsafe fixture recovery path'
 if(Test-Path -LiteralPath $Fixture.InstallPath -PathType Container){[IO.File]::WriteAllText((Join-Path $Fixture.InstallPath 'allow-fixture-uninstall.tag'),'fixture-only')}
}
try{
 $activation=New-InstallerFixture 'activation' 0
 $exitCode=Invoke-FixtureProcess $activation.Installer (Join-Path $temp 'activation-setup.log')
 Assert-Fixture ($exitCode -eq 10) ('Failed activation must return 10, received '+$exitCode)
 Assert-Fixture ([IO.File]::ReadAllText((Join-Path $temp 'activation-setup.log')).Contains('Setup failed')) 'Failed activation did not record an explicit failed result'
 $manager=Join-Path $activation.InstallPath 'Manage-iCUEMemoryGuard.ps1'
 $uninstaller=Join-Path $activation.InstallPath 'unins000.exe'
 Assert-Fixture (Test-Path -LiteralPath $manager -PathType Leaf) 'Failed activation removed the recovery manager'
 Assert-Fixture (Test-Path -LiteralPath $uninstaller -PathType Leaf) 'Failed activation removed the uninstaller'
 Assert-Fixture (Test-Path -LiteralPath $activation.RegistryPath) 'Failed activation removed the uninstall entry'
 $entry=Get-ItemProperty -LiteralPath $activation.RegistryPath
 Assert-Fixture ($entry.DisplayName -like ($activation.Name+'*')) 'Fixture uninstall entry has an unexpected identity'
 $exitCode=Invoke-FixtureProcess $uninstaller (Join-Path $temp 'activation-uninstall-refused.log')
 Assert-Fixture ($exitCode -ne 0) 'Failed restoration returned successful uninstall'
 Assert-Fixture ((Test-Path -LiteralPath $manager -PathType Leaf) -and (Test-Path -LiteralPath $uninstaller -PathType Leaf) -and (Test-Path -LiteralPath $activation.RegistryPath)) 'Failed uninstall removed recovery files or its entry'
 Enable-FixtureUninstall $activation
 $exitCode=Invoke-FixtureProcess $uninstaller (Join-Path $temp 'activation-uninstall-success.log')
 Assert-Fixture ($exitCode -eq 0) ('Safe fixture uninstall failed: '+$exitCode)
 Wait-FixtureUninstalled $manager $uninstaller $activation.RegistryPath
 # The marker was created by this test, so Inno correctly leaves the nonempty directory.
 $marker=Join-Path $activation.InstallPath 'allow-fixture-uninstall.tag'
 if(Test-Path -LiteralPath $marker){Remove-Item -LiteralPath $marker}
 if(Test-Path -LiteralPath $activation.InstallPath){Remove-Item -LiteralPath $activation.InstallPath}
 $check=New-InstallerFixture 'check' 23
 $exitCode=Invoke-FixtureProcess $check.Installer (Join-Path $temp 'check-setup.log')
 Assert-Fixture ($exitCode -ne 0) 'Failed compatibility Check returned success'
 Assert-Fixture (-not(Test-Path -LiteralPath $check.InstallPath) -and -not(Test-Path -LiteralPath $check.RegistryPath)) 'Failed compatibility Check installed files or an uninstall entry'
 $completed=$true
 Write-Output 'PASS real Inno fixtures: activation exit10 retained recovery; failed uninstall retained recovery; allowed uninstall cleaned payload/entry; failed Check installed nothing'
}finally{
 if(-not $completed){
  # Recover only this GUID run through its own uninstaller; retain logs on any failure.
  foreach($fixture in $fixtures){
   $uninstaller=Join-Path $fixture.InstallPath 'unins000.exe'
   if(Test-Path -LiteralPath $uninstaller -PathType Leaf){
    try{Enable-FixtureUninstall $fixture;$null=Invoke-FixtureProcess $uninstaller (Join-Path $temp ([IO.Path]::GetFileName($fixture.Path)+'-cleanup.log'))}catch{Write-Warning $_.Exception.Message}
   }
  }
  Write-Warning ('Fixture failure evidence retained at '+$temp)
 }else{
  $resolved=[IO.Path]::GetFullPath($temp)
  $parent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
  if(-not $resolved.StartsWith($parent,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -ne ('icue-inno-fixtures-'+$runId)){throw 'Unsafe fixture cleanup target'}
  Remove-Item -LiteralPath $resolved -Recurse -Force
 }
}
