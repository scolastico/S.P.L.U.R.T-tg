param(
    [ValidateSet('status','save','stop','inspect','find','call','set_var','spawn','delete')][string]$Action='status',
    [hashtable]$Payload,
    [int]$Port=1351,
    [Parameter(Mandatory=$true)][string]$ConfigDirectory
)
$ErrorActionPreference='Stop'
$keyFile=Join-Path $ConfigDirectory 'comms.txt'
$keyMatch=[regex]::Match([IO.File]::ReadAllText($keyFile),'(?m)^COMMS_KEY\s+(\S+)')
if(-not $keyMatch.Success){throw 'Babylon control key is missing.'}
$query='babylon_control=1&format=json&key='+[uri]::EscapeDataString($keyMatch.Groups[1].Value)+'&action='+$Action
if($Payload){$query+='&payload='+[uri]::EscapeDataString(($Payload|ConvertTo-Json -Depth 30 -Compress))}
$bytes=[Text.Encoding]::UTF8.GetBytes($query)
$packetLength=$bytes.Length+6
if($packetLength -gt 65535){throw 'Control request is too large.'}
[byte[]]$packet=@(0,131,($packetLength -shr 8),($packetLength -band 255),0,0,0,0,0)+$bytes+@(0)
function Read-Exact($stream,[int]$count){
    $buffer=New-Object byte[] $count
    $offset=0
    while($offset -lt $count){$read=$stream.Read($buffer,$offset,$count-$offset);if(!$read){throw 'Server disconnected.'};$offset+=$read}
    return ,$buffer
}
$connection=New-Object Net.Sockets.TcpClient
try{
    $connection.ReceiveTimeout=180000
    $connection.SendTimeout=5000
    $connection.Connect('127.0.0.1',$Port)
    $stream=$connection.GetStream()
    $stream.Write($packet,0,$packet.Length)
    $header=Read-Exact $stream 4
    if($header[0] -ne 0 -or $header[1] -ne 131){throw 'Invalid server response.'}
    $body=Read-Exact $stream (([int]$header[2] -shl 8)+[int]$header[3])
    if($body[0] -ne 6){throw 'Expected a text response.'}
    $json=[Text.Encoding]::UTF8.GetString($body,1,$body.Length-1).TrimEnd([char]0)
    $json | ConvertFrom-Json | ConvertTo-Json -Depth 30
}finally{$connection.Dispose()}
