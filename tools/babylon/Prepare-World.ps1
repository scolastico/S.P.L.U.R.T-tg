param([string]$Root=(Join-Path $PSScriptRoot '..\..'), [string]$Python)
$ErrorActionPreference='Stop'
$rootPath=(Resolve-Path -LiteralPath $Root).Path
$saveRoot=Join-Path $rootPath 'data\babylon'
$active=Join-Path $rootPath '_maps\babylon\active.dmm'
New-Item -ItemType Directory -Path (Split-Path $active),$saveRoot -Force|Out-Null
$manifestFile=Join-Path $saveRoot 'saves\latest.json'
$resume=Join-Path $saveRoot 'resume-state.json'
if(Test-Path -LiteralPath $manifestFile){
    $manifest=Get-Content -LiteralPath $manifestFile -Raw|ConvertFrom-Json
    if($manifest.generation -notmatch '^save-[0-9]{8}-[0-9]{6}-[0-9]+$'){throw 'Invalid checkpoint generation.'}
    $checkpoint=Join-Path $saveRoot ('saves\'+$manifest.generation)
    foreach($name in @('map.dmm','state.json')){if(!(Test-Path -LiteralPath (Join-Path $checkpoint $name))){throw "Incomplete checkpoint: $name"}}
    Copy-Item -LiteralPath (Join-Path $checkpoint 'map.dmm') -Destination $active -Force
    Copy-Item -LiteralPath (Join-Path $checkpoint 'state.json') -Destination $resume -Force
    Write-Host "Prepared checkpoint $($manifest.generation)."
}else{
    if(!$Python){
        if(Get-Command uv -ErrorAction SilentlyContinue){$Python=(& uv python find)}
        else{$Python=(Get-Command python -ErrorAction Stop).Source}
    }
    & $Python (Join-Path $rootPath 'services\supervisor\map_overlay.py') --root $rootPath --output $active
    if($LASTEXITCODE -ne 0){throw 'Babylon map preparation failed.'}
    if(Test-Path -LiteralPath $resume){Remove-Item -LiteralPath $resume}
    Write-Host 'Prepared the upstream Babylon wreck with its lore additions.'
}
