<#
.SYNOPSIS
  Sends console commands to the test server (RCON) and shows the reply and what the log gained meanwhile.
.DESCRIPTION
  Works only with the test server started by scripts/run-server.ps1 (it reads the port and password from
  its session file). Commands are written without the leading slash, as on the server console.
  Several commands run in order. After each, the script waits -WaitSeconds and prints the log entries
  that appeared (exceptions thrown by the plugin's command handler show up there, not in the reply).
  Commands run as the console: there is no player. To test something that needs a player, the user joins
  with their client (or use MockBukkit tests, references/testing.md).
  Exit codes: 0 / 1 RCON error / 2 the log gained an ERROR / 3 the test server is not running.
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/rcon.ps1 "hello"
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/rcon.ps1 "plugins" "version SleepVote"
#>
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)][string[]]$Command,
    [string]$ProjectRoot,
    [double]$WaitSeconds = 1.5
)
. (Join-Path $PSScriptRoot 'lib/common.ps1')
. (Join-Path $PSScriptRoot 'lib/server.ps1')
Initialize-PaperDevConsole

if (-not $Command -or $Command.Count -eq 0) { Write-PaperDevStatus 'error' 'no command (example: scripts/rcon.ps1 "plugins")'; exit 1 }
$project = Resolve-PaperDevProject $ProjectRoot
if (-not $project) { Write-PaperDevStatus 'error' 'no Gradle or Maven project found (pass -ProjectRoot)'; exit 1 }
$session = Get-PaperDevSession $project
if (-not $session -or -not (Test-PaperDevProcessAlive ([int]$session.pid))) {
    Write-PaperDevStatus 'stopped' 'the test server is not running (scripts/run-server.ps1)'
    exit 3
}
$logPath = Join-Path (Get-PaperDevServerDir $project) 'logs/latest.log'
$exitCode = 0
foreach ($c in $Command) {
    $c = $c.TrimStart('/')
    $before = Get-PaperDevLogLineCount $logPath
    Write-Host ('> ' + $c)
    try {
        $reply = Invoke-PaperDevRcon -Port ([int]$session.rconPort) -Password ([string]$session.rconPassword) -Command $c
    } catch {
        Write-PaperDevStatus 'error' $_.Exception.Message
        $exitCode = 1
        continue
    }
    # Strip legacy color codes that some replies still carry.
    $reply = $reply -replace ([string][char]0x00A7 + '.'), ''
    if ($reply.Trim()) { foreach ($l in ($reply.TrimEnd() -split "`r?`n")) { Write-Host ('  ' + $l) } }
    else { Write-Host '  (no reply text)' }
    if ($WaitSeconds -gt 0) { Start-Sleep -Milliseconds ([int]($WaitSeconds * 1000)) }
    $newAll = Get-PaperDevLogEntries $logPath $before
    $new = @($newAll | Where-Object { $_.Thread -notmatch '^RCON' -or $_.Level -ne 'INFO' })
    $new = @($new | Where-Object { $_.Message -notmatch '^(Thread RCON Client|Rcon issued server command|\[Rcon\])' })
    if ($new.Count -gt 0) {
        Write-Host '  log:'
        foreach ($e in $new) { foreach ($l in ($e.Lines | Select-Object -First 30)) { Write-Host ('    ' + $l) } }
        if (@($new | Where-Object { $_.Level -eq 'ERROR' -or $_.Level -eq 'FATAL' }).Count -gt 0 -and $exitCode -eq 0) { $exitCode = 2 }
    }
}
exit $exitCode
