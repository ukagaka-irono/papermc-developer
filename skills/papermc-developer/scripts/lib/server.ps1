# The test server: one per project, in <home>/servers/<project id>/, reached through RCON on 127.0.0.1.

function Test-PaperDevServerRunning {
    param($Session)
    if (-not $Session) { return $false }
    if (-not (Test-PaperDevProcessAlive ([int]$Session.pid))) { return $false }
    try {
        Invoke-PaperDevRcon -Port ([int]$Session.rconPort) -Password ([string]$Session.rconPassword) -Command 'list' -TimeoutMs 3000 | Out-Null
        return $true
    } catch { return $false }
}

function Stop-PaperDevServer {
    # "stop" through RCON (saves the world, runs onDisable), then waits; kills the process tree if it hangs.
    param($Session, [int]$TimeoutSeconds = 60)
    if (-not $Session) { return $false }
    $procId = [int]$Session.pid
    if (-not (Test-PaperDevProcessAlive $procId)) { return $false }
    try { Invoke-PaperDevRcon -Port ([int]$Session.rconPort) -Password ([string]$Session.rconPassword) -Command 'stop' -TimeoutMs 5000 | Out-Null } catch { }
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (-not (Test-PaperDevProcessAlive $procId)) { return $true }
        Start-Sleep -Milliseconds 500
    }
    Write-PaperDevStatus 'warn' ('the server did not stop within ' + $TimeoutSeconds + 's; killing it')
    Stop-PaperDevProcessTree $procId
    return $true
}

function Set-PaperDevProperties {
    # Sets keys in a .properties file, keeping the other lines.
    param([string]$Path, [System.Collections.IDictionary]$Values)
    $lines = @()
    if (Test-Path -LiteralPath $Path) { $lines = @((Read-PaperDevText $Path) -split "`r?`n" | Where-Object { $_ -ne '' }) }
    $done = @{}
    $out = foreach ($l in $lines) {
        if ($l -match '^([^#=]+)=' -and $Values.Contains($Matches[1].Trim())) {
            $k = $Matches[1].Trim()
            $done[$k] = $true
            $k + '=' + $Values[$k]
        } else { $l }
    }
    foreach ($k in $Values.Keys) { if (-not $done[$k]) { $out = @($out) + ($k + '=' + $Values[$k]) } }
    Write-PaperDevText -Path $Path -Text ((@($out) -join "`n") + "`n")
}

function New-PaperDevPassword {
    $bytes = New-Object byte[] 18
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return ([Convert]::ToBase64String($bytes) -replace '[+/=]', 'x')
}

function Get-PaperDevPluginPackage {
    param($Project)
    if (-not $Project.Descriptor) { return $null }
    $main = (Read-PaperDevDescriptor $Project.Descriptor).Values['main']
    if ($main -and $main -match '^(.+)\.[^.]+$') { return $Matches[1] }
    return $null
}

function Write-PaperDevServerReport {
    # Prints what the log says about the plugin. Returns the number of problems (ERROR entries, plugin not enabled).
    param([array]$Entries, [string]$PluginName, [string]$Package, [switch]$RequireEnabled, [int]$MaxEntries = 20)
    $problems = 0
    $enabled = @($Entries | Where-Object { $_.Message -match ('^\[' + [regex]::Escape($PluginName) + '\] Enabling ' + [regex]::Escape($PluginName) + ' v') })
    $failedEnable = @($Entries | Where-Object { $_.Message -match ('(Error occurred while enabling|Could not load|Could not enable|Unable to load|Failed to load).*' + [regex]::Escape($PluginName)) })
    if ($RequireEnabled) {
        if ($enabled.Count -gt 0 -and $failedEnable.Count -eq 0) { Write-PaperDevStatus 'ok' ('plugin ' + $PluginName + ' enabled') }
        else { Write-PaperDevStatus 'error' ('plugin ' + $PluginName + ' was not enabled'); $problems++ }
    }
    $errorsList = @($Entries | Where-Object { $_.Level -eq 'ERROR' -or $_.Level -eq 'FATAL' })
    $pluginWarnings = @($Entries | Where-Object { $_.Level -eq 'WARN' -and (Test-PaperDevEntryAboutPlugin $_ $PluginName $Package) })
    $otherWarnings = @($Entries | Where-Object { $_.Level -eq 'WARN' -and -not (Test-PaperDevEntryAboutPlugin $_ $PluginName $Package) })
    $shown = 0
    foreach ($e in ($errorsList + $pluginWarnings | Sort-Object LineNo)) {
        if ($shown -ge $MaxEntries) { break }
        $about = Test-PaperDevEntryAboutPlugin $e $PluginName $Package
        $tag = 'server'
        if ($about) { $tag = 'plugin' }
        Write-Host ('---- ' + $e.Level + ' (' + $tag + ', latest.log line ' + $e.LineNo + ')')
        Write-PaperDevLogEntry $e
        $shown++
    }
    $problems += $errorsList.Count
    if ($errorsList.Count -gt 0 -or $pluginWarnings.Count -gt 0) {
        Write-Host ('log: ' + $errorsList.Count + ' error(s), ' + $pluginWarnings.Count + ' warning(s) about the plugin, ' + $otherWarnings.Count + ' other warning(s)')
    } else {
        Write-Host ('log: no errors; ' + $otherWarnings.Count + ' warning(s) not about the plugin (scripts/server-log.ps1 -Level WARN shows them)')
    }
    return $problems
}
