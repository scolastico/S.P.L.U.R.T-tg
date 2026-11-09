param(
    [Parameter(Mandatory=$true)][string]$DreamDaemon,
    [Parameter(Mandatory=$true)][string]$ConfigDirectory,
    [string]$PublicHost='127.0.0.1',
    [string[]]$Admins=@(),
    [int]$ApiPort=1360,
    [int]$LobbyPort=1361
)
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$supervisorFile=Join-Path $root 'babylon-supervisor-config.json'
$lobbyFile=Join-Path $root 'babylon-lobby-config.json'
if((Test-Path -LiteralPath $supervisorFile) -or (Test-Path -LiteralPath $lobbyFile)){
    throw 'Cluster configuration already exists. Edit it directly; initialization will not overwrite credentials.'
}
$config=Get-Content (Join-Path $root 'services\supervisor\config.example.json') -Raw|ConvertFrom-Json
$random=New-Object byte[] 32
$rng=[Security.Cryptography.RandomNumberGenerator]::Create()
try{$rng.GetBytes($random)}finally{$rng.Dispose()}
$secret=[Convert]::ToBase64String($random)
$config.lobby_secret=$secret
$config.admins=@($Admins)
$config.public_host=$PublicHost
$config.listen_port=$ApiPort
$config.lobby_address="byond://${PublicHost}:$LobbyPort"
$config.template_directory=$root
$config.config_directory=(Resolve-Path -LiteralPath $ConfigDirectory).Path
$config.dreamdaemon=(Resolve-Path -LiteralPath $DreamDaemon).Path
$config.data_directory=Join-Path $root 'data\babylon-supervisor'
$utf8=New-Object Text.UTF8Encoding $false
[IO.File]::WriteAllText($supervisorFile,($config|ConvertTo-Json -Depth 10),$utf8)
[IO.File]::WriteAllText($lobbyFile,(@{api="http://127.0.0.1:$ApiPort";secret=$secret;port=$LobbyPort}|ConvertTo-Json),$utf8)
Write-Host 'Created private cluster configurations. Review limits in babylon-supervisor-config.json, then run Start-Cluster.ps1.'
