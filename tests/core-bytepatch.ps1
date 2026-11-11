$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$module=Join-Path $repo 'src/BytePatch.psm1'
if(-not (Test-Path $module)){throw 'ASSERT: byte patch engine has not been implemented'}
Import-Module $module -Force -DisableNameChecking
$root=Join-Path ([IO.Path]::GetTempPath()) ('icue-core-'+[guid]::NewGuid().ToString('n'))
$null=New-Item -ItemType Directory $root
$script:passed=0
function Assert($Condition,$Message){if(-not $Condition){throw ('ASSERT: '+$Message)};$script:passed++}
function Reject([scriptblock]$Code,[string]$Message){$failed=$false;try{& $Code}catch{$failed=$true};Assert $failed $Message}
try{
 $source=Join-Path $root 'source.bin';$target=Join-Path $root 'target.bin';$output=Join-Path $root 'output.bin';$definition=Join-Path $root 'patch.json'
 [IO.File]::WriteAllBytes($source,[byte[]](1,2,3,4,5,6));[IO.File]::WriteAllBytes($target,[byte[]](1,9,8,4,5,7,0,22))
 Export-BytePatch -SourcePath $source -TargetPath $target -OutputPath $definition
 Apply-BytePatch -SourcePath $source -DefinitionPath $definition -OutputPath $output
 Assert ((Get-FileHash $output).Hash -eq (Get-FileHash $target).Hash) 'edit and extension produce exact target'
 $valid=Get-Content $definition -Raw
 $data=$valid|ConvertFrom-Json
 Assert ($data.edits.Count -eq 3) 'export uses minimal contiguous changed ranges'
 function Bad($Mutate,$Label){$data=$valid|ConvertFrom-Json;& $Mutate $data;[IO.File]::WriteAllText($definition,($data|ConvertTo-Json -Depth 10));Remove-Item $output -ErrorAction SilentlyContinue;Reject {Apply-BytePatch -SourcePath $source -DefinitionPath $definition -OutputPath $output} $Label;Assert (-not (Test-Path $output)) ($Label+' does not emit output')}
 Bad {param($d)$d.sourceSha256=('0'*64)} 'reject source checksum'
 Bad {param($d)$d.targetSha256=('0'*64)} 'reject target checksum'
 Bad {param($d)$d.edits[1].offset=$d.edits[0].offset} 'reject duplicate or overlapping edits'
 Bad {param($d)$d.edits[0].offset=-1} 'reject negative offset'
 Bad {param($d)$d.edits[0].offset=7} 'reject bounds overflow'
 Bad {param($d)$d.targetLength=67108865} 'reject oversized output'
 Bad {param($d)$d.sourceLength=-1} 'reject negative length'
 Bad {param($d)$d.edits[0].offset=1.5} 'reject fractional offset'
 Bad {param($d)$d.edits[0].bytes='xz'} 'reject nonhex bytes'
 Bad {param($d)$d.edits[0].bytes=''} 'reject empty edit'
 Bad {param($d)$d.schema=99} 'reject unknown schema'
 Bad {param($d)$d|Add-Member NoteProperty unexpected 1} 'reject malformed fields'
 [IO.File]::WriteAllText($definition,$valid)
 Reject {Apply-BytePatch -SourcePath $source -DefinitionPath $definition -OutputPath $output -ExpectedSourceHash ('0'*64)} 'binding source pin overrides manifest'
 Reject {Apply-BytePatch -SourcePath $source -DefinitionPath $definition -OutputPath $output -ExpectedTargetHash ('0'*64)} 'binding target pin overrides manifest'
 Reject {Apply-BytePatch -SourcePath $source -DefinitionPath $definition -OutputPath $source} 'source cannot be output'
 [pscustomobject]@{Suite='bytepatch';Passed=$script:passed}|ConvertTo-Json -Compress
}finally{Remove-Item -LiteralPath $root -Recurse -Force}
