param([string]$Python)
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$pythonPath=& (Join-Path $PSScriptRoot 'Find-Python.ps1') -Python $Python
$supervisorFile=Join-Path $root 'babylon-supervisor-config.json'
$lobbyFile=Join-Path $root 'babylon-lobby-config.json'
$config=Get-Content -LiteralPath $supervisorFile -Raw|ConvertFrom-Json
$lobby=Get-Content -LiteralPath $lobbyFile -Raw|ConvertFrom-Json
$recordFile=Join-Path $config.data_directory 'cluster-processes.json'
$menu=$null
$service=$null
if(Test-Path -LiteralPath $recordFile){
    $record=Get-Content -LiteralPath $recordFile -Raw|ConvertFrom-Json
    $menu=Get-CimInstance Win32_Process -Filter "ProcessId=$($record.lobby_pid)"
    $service=Get-CimInstance Win32_Process -Filter "ProcessId=$($record.supervisor_pid)"
    if($menu -and ($menu.ExecutablePath -ne $config.dreamdaemon -or !$menu.CommandLine.Contains($lobbyFile))){throw 'Recorded lobby PID belongs to another process; left untouched.'}
    if($service -and (!$service.CommandLine.Contains((Join-Path $root 'services\supervisor\supervisor.py')) -or !$service.CommandLine.Contains($supervisorFile))){throw 'Recorded supervisor PID belongs to another process; left untouched.'}
}
foreach($pair in @(@($lobby.port,$menu),@($config.listen_port,$service))){
    $listener=Get-NetTCPConnection -State Listen -LocalPort $pair[0] -ErrorAction SilentlyContinue
    if($listener -and (!$pair[1] -or $listener.OwningProcess -ne $pair[1].ProcessId)){throw "Port $($pair[0]) belongs to an unrecognized process; left untouched."}
}
# Close the admission entry point first so no new world can start mid-shutdown.
if($menu){Stop-Process -Id $menu.ProcessId}
& $pythonPath (Join-Path $root 'services\supervisor\stop_worlds.py') --config $supervisorFile
if($LASTEXITCODE -ne 0){throw 'World shutdown failed. Supervisor and child processes were left running for recovery.'}
if($service){Stop-Process -Id $service.ProcessId}
Write-Host 'Babylon lobby, supervisor and worlds are stopped.'
