# Windows PowerShell 5.1. Definitions contain changed bytes only, never an image.
Set-StrictMode -Version 2
$ErrorActionPreference='Stop'
$script:MaximumImageLength=67108864
function Get-ByteHash([byte[]]$Bytes){
 $algorithm=[Security.Cryptography.SHA256]::Create()
 try{[BitConverter]::ToString($algorithm.ComputeHash($Bytes)).Replace('-','')}finally{$algorithm.Dispose()}
}
function Assert-Fields($Object,[string[]]$Names){
 if($null -eq $Object -or $Object -isnot [pscustomobject]){throw 'Expected a JSON object'}
 $actual=@($Object.PSObject.Properties.Name)
 if($actual.Count -ne $Names.Count -or @($actual|Where-Object {$_ -cnotin $Names}).Count){throw 'Unexpected or missing patch fields'}
}
function Assert-Integer($Value,[long]$Minimum,[long]$Maximum){
 if(($Value -isnot [int] -and $Value -isnot [long]) -or $Value -lt $Minimum -or $Value -gt $Maximum){throw 'Patch integer outside allowed bounds'}
}
function Read-BoundedImage([string]$Path){
 $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
 try{
  if($stream.Length -lt 1 -or $stream.Length -gt $script:MaximumImageLength){throw 'Image length outside allowed bounds'}
  $bytes=New-Object byte[] ([int]$stream.Length);$offset=0
  while($offset -lt $bytes.Length){$read=$stream.Read($bytes,$offset,$bytes.Length-$offset);if(-not $read){throw 'Image changed while reading'};$offset+=$read}
  return ,$bytes
 }finally{$stream.Dispose()}
}
function Apply-BytePatch {
 [CmdletBinding()]
 param([Parameter(Mandatory)][string]$SourcePath,[Parameter(Mandatory)][string]$DefinitionPath,[Parameter(Mandatory)][string]$OutputPath,[string]$ExpectedSourceHash,[string]$ExpectedTargetHash)
 if([IO.Path]::GetFullPath($SourcePath) -eq [IO.Path]::GetFullPath($OutputPath)){throw 'Output must differ from source'}
 if((Get-Item -LiteralPath $DefinitionPath).Length -gt 4194304){throw 'Patch definition too large'}
 $data=Get-Content -LiteralPath $DefinitionPath -Raw|ConvertFrom-Json
 Assert-Fields $data @('schema','sourceLength','targetLength','sourceSha256','targetSha256','edits')
 Assert-Integer $data.schema 1 1
 Assert-Integer $data.sourceLength 1 $script:MaximumImageLength
 Assert-Integer $data.targetLength 1 $script:MaximumImageLength
 foreach($hash in @($data.sourceSha256,$data.targetSha256)){if($hash -isnot [string] -or $hash -cnotmatch '^[A-Fa-f0-9]{64}$'){throw 'Invalid SHA-256 field'}}
 if($ExpectedSourceHash -and $data.sourceSha256 -ne $ExpectedSourceHash){throw 'Patch source does not match the pinned SHA-256'}
 if($ExpectedTargetHash -and $data.targetSha256 -ne $ExpectedTargetHash){throw 'Patch target does not match the pinned SHA-256'}
 if($data.edits -isnot [array] -or $data.edits.Count -gt 65536){throw 'Invalid edit list'}
 $end=0L
 foreach($edit in $data.edits){
  Assert-Fields $edit @('offset','bytes')
  Assert-Integer $edit.offset 0 ($data.targetLength-1)
  if($edit.bytes -isnot [string] -or $edit.bytes.Length -eq 0 -or $edit.bytes.Length%2 -or $edit.bytes -cnotmatch '^[A-Fa-f0-9]+$'){throw 'Invalid hexadecimal edit bytes'}
  $length=$edit.bytes.Length/2
  if($edit.offset -lt $end -or $length -gt ($data.targetLength-$edit.offset)){throw 'Overlapping or out-of-bounds edit'}
  $end=[long]$edit.offset+[long]$length
 }
 $source=Read-BoundedImage $SourcePath
 if($source.Length -ne $data.sourceLength -or (Get-ByteHash $source) -ne $data.sourceSha256){throw 'Original image SHA-256 or length mismatch'}
 $result=New-Object byte[] ([int]$data.targetLength)
 [Array]::Copy($source,$result,[Math]::Min($source.Length,$result.Length))
 foreach($edit in $data.edits){for($index=0;$index -lt $edit.bytes.Length;$index+=2){$result[$edit.offset+$index/2]=[Convert]::ToByte($edit.bytes.Substring($index,2),16)}}
 if((Get-ByteHash $result) -ne $data.targetSha256){throw 'Patched image SHA-256 mismatch'}
 # CreateNew prevents clobbering an existing output, including a link.
 $stream=[IO.File]::Open($OutputPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try{$stream.Write($result,0,$result.Length);$stream.Flush($true)}finally{$stream.Dispose()}
}
function Export-BytePatch {
 [CmdletBinding()]
 param([Parameter(Mandatory)][string]$SourcePath,[Parameter(Mandatory)][string]$TargetPath,[Parameter(Mandatory)][string]$OutputPath)
 $source=Read-BoundedImage $SourcePath;$target=Read-BoundedImage $TargetPath
 $edits=New-Object 'Collections.Generic.List[object]'
 $index=0
 while($index -lt $target.Length){
  # Appended zero bytes need no edit: the bounded result buffer is zero initialized.
  $prior=if($index -lt $source.Length){$source[$index]}else{0}
  if($prior -eq $target[$index]){$index++;continue}
  $start=$index;$hex=New-Object Text.StringBuilder
  do{
   $null=$hex.Append($target[$index].ToString('X2'));$index++
   $prior=if($index -lt $source.Length){$source[$index]}else{0}
  }while($index -lt $target.Length -and $prior -ne $target[$index])
  $edits.Add([ordered]@{offset=$start;bytes=$hex.ToString()})
 }
 $data=[ordered]@{schema=1;sourceLength=$source.Length;targetLength=$target.Length;sourceSha256=(Get-ByteHash $source);targetSha256=(Get-ByteHash $target);edits=@($edits.ToArray())}
 [IO.File]::WriteAllText($OutputPath,($data|ConvertTo-Json -Depth 5),(New-Object Text.UTF8Encoding($false)))
}
Export-ModuleMember -Function Apply-BytePatch,Export-BytePatch
