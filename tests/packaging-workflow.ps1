$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$workflow=[IO.File]::ReadAllText((Join-Path $root '.github/workflows/build.yml'))
$step=[regex]::Match($workflow,'(?m)^      - name: Require installed Inno Setup 6\r?\n        shell: powershell\r?\n        run: \|\r?\n(?<Script>(?:          [^\r\n]*(?:\r?\n|$))+)')
if(-not $step.Success){throw 'Compiler availability workflow step was not found'}
$probe=[regex]::Replace($step.Groups['Script'].Value,'(?m)^          ','')
if($probe -match '(?m)^\s*&\s*\$compiler\s+/\?'){throw 'Compiler help exits nonzero and cannot be used as a successful availability probe'}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('icue-ci-probe-'+[guid]::NewGuid().ToString('N')+'.ps1')
try{
 # GitHub powershell steps propagate the last native exit code after the block.
 $script='$ErrorActionPreference=''Stop'''+"`n"+$probe+"`n"+'if(Test-Path -LiteralPath variable:\LASTEXITCODE){exit $LASTEXITCODE}'
 [IO.File]::WriteAllText($temp,$script,(New-Object Text.UTF8Encoding($false)))
 $previous=$ErrorActionPreference
 try{$ErrorActionPreference='Continue';$output=& powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $temp 2>&1;$exitCode=$LASTEXITCODE}finally{$ErrorActionPreference=$previous}
 if($exitCode -ne 0 -or ($output -join "`n") -notmatch 'Inno Setup compiler version: \d+\.\d+'){throw ('Compiler availability step failed: '+($output -join "`n"))}
 Write-Output 'PASS CI compiler probe: managed version-resource availability check exits successfully'
}finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp}}
