param([Parameter(Mandatory=$true)][string]$Python)
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$pythonPath=(Resolve-Path -LiteralPath $Python).Path
$supervisorFile=Join-Path $root 'babylon-supervisor-config.json'
$lobbyFile=Join-Path $root 'babylon-lobby-config.json'
$config=Get-Content -LiteralPath $supervisorFile -Raw|ConvertFrom-Json
$lobby=Get-Content -LiteralPath $lobbyFile -Raw|ConvertFrom-Json
foreach($name in @('babylon.dmb','babylon.rsc','babylon-lobby.dmb')){
    if(!(Test-Path -LiteralPath (Join-Path $root $name))){throw "Missing $name; compile the production and lobby builds first."}
}
foreach($port in @($config.listen_port,$lobby.port)){
    if(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue){throw "Port $port is already in use."}
}
New-Item -ItemType Directory -Path $config.data_directory -Force|Out-Null
$service=Join-Path $root 'services\supervisor\supervisor.py'
$serviceArguments=@(('"{0}"' -f $service),'--config',('"{0}"' -f $supervisorFile))
$supervisor=Start-Process $pythonPath -ArgumentList $serviceArguments -WorkingDirectory $root -WindowStyle Hidden -RedirectStandardOutput (Join-Path $config.data_directory 'supervisor.log') -RedirectStandardError (Join-Path $config.data_directory 'supervisor-errors.log') -PassThru
$deadline=(Get-Date).AddSeconds(15)
do{
    Start-Sleep -Milliseconds 200
    if($supervisor.HasExited){throw 'Supervisor failed. Check supervisor-errors.log.'}
    $ready=Get-NetTCPConnection -State Listen -LocalPort $config.listen_port -ErrorAction SilentlyContinue
}while(!$ready -and (Get-Date) -lt $deadline)
if(!$ready){throw 'Supervisor did not open its API port; inspect its logs.'}
$menuArguments=@('babylon-lobby.dmb',"$($lobby.port)",'-ip',$config.bind_address,'-trusted','-close','-params',('"lobby-config={0}"' -f $lobbyFile))
$menu=Start-Process $config.dreamdaemon -ArgumentList $menuArguments -WorkingDirectory $root -WindowStyle Hidden -RedirectStandardOutput (Join-Path $config.data_directory 'lobby.log') -RedirectStandardError (Join-Path $config.data_directory 'lobby-errors.log') -PassThru
@{supervisor_pid=$supervisor.Id;lobby_pid=$menu.Id;lobby=$config.lobby_address}|ConvertTo-Json|Set-Content (Join-Path $config.data_directory 'cluster-processes.json')
Write-Host "Lobby: $($config.lobby_address)"
Write-Host "Supervisor PID: $($supervisor.Id); Lobby PID: $($menu.Id). Child worlds start when players join."
