param(
    [Parameter(Mandatory=$true)][string]$DreamDaemon,
    [Parameter(Mandatory=$true)][string]$ConfigDirectory,
    [int]$Port=1351
)
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$daemon=(Resolve-Path -LiteralPath $DreamDaemon).Path
$configPath=(Resolve-Path -LiteralPath $ConfigDirectory).Path
if($Port -eq 1339){throw 'Do not use the private local server port.'}
if(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue){throw 'Test port is occupied.'}
if(Test-Path "$root\data\babylon\saves\latest.json"){throw 'This smoke test requires a disposable checkout with no saved world.'}
function BB($a,[hashtable]$p=@{}){
    $r=& "$PSScriptRoot\Control-World.ps1" -Action $a -Payload $p -Port $Port -ConfigDirectory $configPath|ConvertFrom-Json
    if($r.error){throw $r.error};$r
}
function Check($v,$m){if(!$v){throw $m}}
function V($t,$n){(BB inspect @{target=$t;vars=@($n)}).vars.$n}
function SetV($t,$n,$v){[void](BB set_var @{target=$t;var=$n;value=$v})}
function Call($t,$p,$a=@()){BB call @{target=$t;proc=$p;args=$a}}
function Launch {
    $script:child=Start-Process $daemon -ArgumentList @('babylon-test.dmb',"$Port",'-ip','127.0.0.1','-trusted','-close','-params',"config-directory=$configPath&babylon-owner=babylonsmoketest&babylon-hold=1") -WorkingDirectory $root -WindowStyle Hidden -RedirectStandardOutput "$root\babylon-smoke-out.log" -RedirectStandardError "$root\babylon-smoke-error.log" -PassThru
    $deadline=(Get-Date).AddMinutes(4)
    do{
        Start-Sleep -Seconds 2
        if($child.HasExited){throw 'Test server stopped during boot.'}
        if(!(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)){continue}
        $s=BB status
        if($s.ready){break}
    }while((Get-Date) -lt $deadline)
    Check ($s.ready -and $s.paused) 'Test server must finish restoration before paused simulation.'
}
function Stop-Test {
    if($child -and !$child.HasExited){
        $p=Get-CimInstance Win32_Process -Filter "ProcessId=$($child.Id)"
        if($p.ExecutablePath -ne $daemon){throw 'Test process identity changed.'}
        Stop-Process -Id $child.Id
        $child.WaitForExit(10000)|Out-Null
    }
}
Push-Location $root
try{
    & "$PSScriptRoot\Prepare-World.ps1" -Root $root
    Launch
    Check ((V 'session' 'owner_ckey') -eq 'babylonsmoketest') 'Owner was not configured from world parameters.'
    $shells=(BB find @{type='/obj/effect/mob_spawn/ghost_role/drone/derelict/babylon';limit=100}).matches|Where-Object z -EQ 2
    Check (@($shells).Count -eq 0) 'Fresh Babylon shell props remain.'
    SetV 'builder' 'picked' 1;SetV 'builder' 'colour' 'pink';SetV 'builder' 'icon_living' 'drone_maint_pink';SetV 'builder' 'icon_state' 'drone_maint_pink'
    $bag=(BB spawn @{type='/obj/item/storage/backpack';target='builder'}).object
    $iron=(BB spawn @{type='/obj/item/stack/sheet/iron';location=@{ref=$bag.ref}}).object
    SetV $iron.ref 'amount' 37
    Check ((Call 'builder' 'put_in_hand' @(@{ref=$bag.ref},2,1)).result -eq 2) 'Could not hold test backpack.'
    $doorA=(BB spawn @{type='/obj/machinery/door/airlock';location=@{turf=@(200,104,2)}}).object
    $doorB=(BB spawn @{type='/obj/machinery/door/airlock';location=@{turf=@(200,106,2)}}).object
    foreach($door in @($doorA,$doorB)){
        SetV $door.ref 'closeOtherId' 'smoke_cycle'
        $board=(BB spawn @{type='/obj/item/electronics/airlock';location=@{ref=$door.ref}}).object
        SetV $door.ref 'electronics' @{ref=$board.ref}
        SetV $board.ref 'passed_name' 'Named smoke door'
        SetV $board.ref 'passed_cycle_id' 'smoke_cycle'
        SetV $board.ref 'one_access' 1
    }
    $vent=(BB spawn @{type='/obj/machinery/atmospherics/components/unary/vent_pump';location=@{turf=@(200,101,2)}}).object
    SetV $vent.ref 'external_pressure_bound' 4321.25;SetV $vent.ref 'pump_direction' 1
    $scrubber=(BB spawn @{type='/obj/machinery/atmospherics/components/unary/vent_scrubber';location=@{turf=@(200,102,2)}}).object
    SetV $scrubber.ref 'widenet' 1
    $first=BB save
    Check $first.ok 'Initial checkpoint failed.'
    $before=Get-Content "$root\data\babylon\saves\$($first.generation)\state.json" -Raw|ConvertFrom-Json
    Check ($before.version -eq 6) 'Wrong checkpoint format.'
    Stop-Test
    & "$PSScriptRoot\Prepare-World.ps1" -Root $root
    Launch
    Check ((V 'builder' 'icon_living') -eq 'drone_maint_pink') 'Appearance changed after reload.'
    Check ((V 'builder' 'held_items').entries[1].entry.type -eq '/obj/item/storage/backpack') 'Held backpack did not survive.'
    $second=BB save
    $after=Get-Content "$root\data\babylon\saves\$($second.generation)\state.json" -Raw|ConvertFrom-Json
    $index=@{};foreach($r in $after.records){$index[$r.id]=$r}
    foreach($r in $before.records){
        Check $index[$r.id] "Lost object $($r.id)."
        foreach($field in @('parent','materials','reagents','device_airs','pipeline_gas','air_contents')){
            Check (($r.$field|ConvertTo-Json -Depth 30 -Compress) -ceq ($index[$r.id].$field|ConvertTo-Json -Depth 30 -Compress)) "Changed $field for $($r.id)."
        }
        foreach($field in @('amount','picked','icon_living','passed_name','passed_cycle_id','one_access','closeOtherId','external_pressure_bound','pump_direction','widenet')){
            Check (($r.fields.$field|ConvertTo-Json -Depth 20 -Compress) -ceq ($index[$r.id].fields.$field|ConvertTo-Json -Depth 20 -Compress)) "Changed $field for $($r.id)."
        }
    }
    Check (($before.turfs|ConvertTo-Json -Depth 30 -Compress) -ceq ($after.turfs|ConvertTo-Json -Depth 30 -Compress)) 'Room gases or temperatures changed.'
    $doors=(BB find @{type='/obj/machinery/door/airlock';limit=100}).matches|Where-Object {$_.x -eq 200 -and $_.y -in @(104,106) -and $_.z -eq 2}
    Check (@($doors).Count -eq 2) 'Test doors missing.'
    foreach($door in $doors){Check ((V $door.ref 'close_others').length -eq 1) 'Cycle group membership was not reconstructed.'}
    $result=@{passed=$true;objects=$before.records.Count;room_tiles=$before.turfs.Count;first=$first.generation;second=$second.generation;owner_configured=$true;inventory=$true;machine_settings=$true;airlock_groups=$true;exact_gases=$true}
    [IO.File]::WriteAllText("$root\data\babylon\smoke-result.json",($result|ConvertTo-Json -Depth 10))
    $result|ConvertTo-Json
}finally{Stop-Test;Pop-Location}
