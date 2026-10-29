<#
.SYNOPSIS
  Reads the test server's log (logs/latest.log). Read only.
.DESCRIPTION
  By default shows the ERROR entries and the WARN entries about the plugin (from the plugin's logger, naming
  it, or with a stack trace through its package), each with its stack trace.
  -Level WARN|INFO  shows everything from that level up
  -Plugin           only entries about the plugin (any level)
  -Tail <n>         the last n entries (after filtering)
  -Pattern <regex>  only entries whose text matches
  -Wait <seconds>   waits for a NEW entry that passes the filters (e.g. a timer task's output), shows it, and stops
  Exit codes: 0 / 1 no log, or -Wait timed out / 2 the shown entries include an ERROR / 3 no test server folder.
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/server-log.ps1
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/server-log.ps1 -Plugin -Pattern "vote" -Wait 60
#>
param(
    [string]$ProjectRoot,
    [ValidateSet('ERROR', 'WARN', 'INFO')][string]$Level,
    [switch]$Plugin,
    [int]$Tail = 40,
    [string]$Pattern,
    [int]$Wait = 0
)
. (Join-Path $PSScriptRoot 'lib/common.ps1')
. (Join-Path $PSScriptRoot 'lib/server.ps1')
Initialize-PaperDevConsole

$project = Resolve-PaperDevProject $ProjectRoot
if (-not $project) { Write-PaperDevStatus 'error' 'no Gradle or Maven project found (pass -ProjectRoot)'; exit 1 }
$serverDir = Get-PaperDevServerDir $project
if (-not (Test-Path -LiteralPath $serverDir)) { Write-PaperDevStatus 'missing' 'no test server yet (scripts/run-server.ps1)'; exit 3 }
$logPath = Join-Path $serverDir 'logs/latest.log'
if (-not (Test-Path -LiteralPath $logPath)) { Write-PaperDevStatus 'error' ('no log: ' + $logPath); exit 1 }
$session = Get-PaperDevSession $project
$pluginName = Get-PaperDevPluginName $project
$package = Get-PaperDevPluginPackage $project

$rank = @{ 'TRACE' = 0; 'DEBUG' = 1; 'INFO' = 2; 'WARN' = 3; 'ERROR' = 4; 'FATAL' = 5 }
function Select-Entries {
    param([array]$Entries)
    $out = @()
    foreach ($e in $Entries) {
        $about = Test-PaperDevEntryAboutPlugin $e $pluginName $package
        $r = 2
        if ($rank.ContainsKey($e.Level)) { $r = $rank[$e.Level] }
        if ($Plugin) { if (-not $about) { continue } }
        if ($Level) { if ($r -lt $rank[$Level]) { continue } }
        elseif (-not $Plugin) { if (-not ($r -ge 4 -or ($r -eq 3 -and $about))) { continue } }
        if ($Pattern -and -not (($e.Lines -join "`n") -match $Pattern)) { continue }
        $out += $e
    }
    return $out
}

if ($Wait -gt 0) {
    $start = Get-PaperDevLogLineCount $logPath
    $deadline = (Get-Date).AddSeconds($Wait)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 700
        $new = @(Select-Entries (Get-PaperDevLogEntries $logPath $start))
        if ($new.Count -gt 0) {
            foreach ($e in $new) { Write-PaperDevLogEntry $e }
            if (@($new | Where-Object { $_.Level -eq 'ERROR' -or $_.Level -eq 'FATAL' }).Count -gt 0) { exit 2 }
            exit 0
        }
    }
    Write-PaperDevStatus 'timeout' ('no new matching entry in ' + $Wait + 's')
    exit 1
}

$all = Get-PaperDevLogEntries $logPath
$selected = @(Select-Entries $all)
$state = 'stopped'
if ($session -and (Test-PaperDevProcessAlive ([int]$session.pid))) { $state = 'running' }
Write-Host ('log: ' + $logPath + ' (' + $all.Count + ' entries, server ' + $state + ')')
$shown = @($selected | Select-Object -Last $Tail)
if ($selected.Count -gt $shown.Count) { Write-Host ('... ' + ($selected.Count - $shown.Count) + ' earlier entr(ies) not shown (-Tail)') }
foreach ($e in $shown) { Write-PaperDevLogEntry $e }
if ($shown.Count -eq 0) { Write-Host 'nothing matched' }
if (@($shown | Where-Object { $_.Level -eq 'ERROR' -or $_.Level -eq 'FATAL' }).Count -gt 0) { exit 2 }
exit 0
