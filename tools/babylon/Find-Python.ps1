param([string]$Python)
$ErrorActionPreference='Stop'
$candidate=$Python
if(!$candidate -and (Get-Command uv -ErrorAction SilentlyContinue)){
    $found=& uv python find 2>$null
    if($LASTEXITCODE -eq 0){$candidate=$found|Select-Object -Last 1}
}
if(!$candidate -and (Get-Command py -ErrorAction SilentlyContinue)){
    $found=& py -3 -c 'import sys; print(sys.executable)' 2>$null
    if($LASTEXITCODE -eq 0){$candidate=$found|Select-Object -Last 1}
}
if(!$candidate -and (Get-Command python -ErrorAction SilentlyContinue)){
    $candidate=(Get-Command python).Source
}
if(!$candidate){throw 'Python 3.11 or newer is required. Install Python/uv, or pass -Python with its executable path.'}
$resolved=(Resolve-Path -LiteralPath $candidate).Path
& $resolved -c 'import sys; raise SystemExit(0 if sys.version_info >= (3,11) else 1)'
if($LASTEXITCODE -ne 0){throw 'Python 3.11 or newer is required.'}
Write-Output $resolved
