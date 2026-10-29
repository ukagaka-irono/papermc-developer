# The test server: one per project, in <home>/servers/<project id>/, reached through RCON on 127.0.0.1.

function Test-PaperDevServerRunning {
    param($Session)
    if (-not $Session) { return $false }
    if (-not (Test-PaperDevProcessAlive ([int]$Session.pid))) { return $false }
    # Velocity has no RCON: a living process is all there is to check.
    if ($Session.platform -eq 'velocity') { return $true }
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
    if ($Session.platform -eq 'velocity') {
        # The proxy first (through its console), then the backend Paper server behind it.
        $stopped = $false
        if (Test-PaperDevProcessAlive $procId) {
            Send-PaperDevConsoleCommand -Session $Session -Command 'shutdown'
            $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
            while ((Get-Date) -lt $deadline -and (Test-PaperDevProcessAlive $procId)) { Start-Sleep -Milliseconds 500 }
            if (Test-PaperDevProcessAlive $procId) { Stop-PaperDevProcessTree ([int]$Session.bridgePid) }
            $stopped = $true
        }
        if ($Session.PSObject.Properties['backend'] -and $Session.backend) {
            if (Stop-PaperDevServer -Session $Session.backend -TimeoutSeconds $TimeoutSeconds) { $stopped = $true }
        }
        return $stopped
    }
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

function Send-PaperDevConsoleCommand {
    # Velocity: appends a line to the queue that lib/console-bridge.ps1 feeds into the proxy's console.
    param($Session, [string]$Command)
    $line = $Command.TrimStart('/') + "`n"
    [System.IO.File]::AppendAllText([string]$Session.queue, $line, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-PaperDevNoGuiArgument {
    # Old CraftBukkit (1.12.2 and earlier) rejects "--nogui" and prints its usage; the plain "nogui" argument is read
    # by the vanilla server code of those versions instead.
    param([string]$Minecraft)
    if (Test-PaperDevVersionAtLeast $Minecraft '1.16') { return '--nogui' }
    return 'nogui'
}

function Start-PaperDevServerProcess {
    # Starts java detached from this script (ShellExecute: no inherited handles), output to $ConsolePath.
    param([string]$Directory, [string]$Java, [string[]]$Arguments, [string]$ConsolePath)
    if (Test-PaperDevWindows) {
        $cmdLine = '/d /s /c ""' + $Java + '" ' + (ConvertTo-PaperDevArgumentString $Arguments) + ' > "' + $ConsolePath + '" 2>&1"'
        return (Start-Process -FilePath $env:ComSpec -ArgumentList $cmdLine -WorkingDirectory $Directory -WindowStyle Hidden -PassThru)
    }
    $quoted = (@($Java) + $Arguments | ForEach-Object { "'" + ($_ -replace "'", "'\''") + "'" }) -join ' '
    return (Start-Process -FilePath 'sh' -ArgumentList @('-c', ('exec ' + $quoted + " > '" + $ConsolePath + "' 2>&1")) -WorkingDirectory $Directory -PassThru)
}

function Start-PaperDevBridgedProcess {
    # Starts java through lib/console-bridge.ps1, which keeps its stdin open and feeds it the lines appended to
    # $Queue (Velocity has no RCON). Returns the bridge process and the java pid (once the bridge reports it).
    param([string]$Directory, [string]$Java, [string[]]$Arguments, [string]$ConsolePath, [string]$Queue)
    $argsFile = Join-Path $Directory 'papermc-developer-args.json'
    Write-PaperDevText -Path $argsFile -Text (ConvertTo-Json -InputObject @($Arguments) -Compress)
    $pidFile = Join-Path $Directory 'papermc-developer-java.pid'
    if (Test-Path -LiteralPath $pidFile) { Remove-Item -LiteralPath $pidFile -Force }
    Write-PaperDevText -Path $Queue -Text ''
    $hostExe = (Get-Process -Id $PID).Path
    $bridge = Join-Path $PSScriptRoot 'console-bridge.ps1'
    if (-not (Test-Path -LiteralPath $bridge)) { $bridge = Join-Path $PSScriptRoot 'lib/console-bridge.ps1' }
    $bridgeArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $bridge, '-Java', $Java, '-ArgsFile', $argsFile, '-WorkDir', $Directory, '-Queue', $Queue, '-ConsoleLog', $ConsolePath, '-PidFile', $pidFile)
    if (Test-PaperDevWindows) {
        $proc = Start-Process -FilePath $hostExe -ArgumentList (ConvertTo-PaperDevArgumentString $bridgeArgs) -WorkingDirectory $Directory -WindowStyle Hidden -PassThru
    } else {
        $proc = Start-Process -FilePath $hostExe -ArgumentList $bridgeArgs -WorkingDirectory $Directory -PassThru
    }
    $javaPid = 0
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $pidFile) { $javaPid = [int]((Get-Content -LiteralPath $pidFile -Raw).Trim()); if ($javaPid -gt 0) { break } }
        if ($proc.HasExited) { break }
        Start-Sleep -Milliseconds 200
    }
    return [PSCustomObject]@{ Bridge = $proc; JavaPid = $javaPid }
}

function Wait-PaperDevServerDone {
    # Waits for "]: Done (" in the log (Paper, Folia and Velocity all print it). $true when it came.
    param([string]$LogPath, [int]$ProcessId, [int]$TimeoutSeconds)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 1
        if (Test-Path -LiteralPath $LogPath) {
            $text = $null
            try {
                $fs = New-Object System.IO.FileStream($LogPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                try { $text = (New-Object System.IO.StreamReader($fs)).ReadToEnd() } finally { $fs.Dispose() }
            } catch { }
            if ($text -and $text -match '\]: Done \(') { return $true }
        }
        if (-not (Test-PaperDevProcessAlive $ProcessId)) { return $false }
    }
    return $false
}

function Initialize-PaperDevPaperFolder {
    # eula.txt, server.properties (127.0.0.1 only, RCON, flat world from 1.19) and plugins/ of a test Paper server.
    param([string]$Directory, [string]$Minecraft, $Era, [int]$Port, [int]$RconPort, [string]$Password, [string]$Motd, [bool]$OnlineMode = $true, [switch]$Fresh)
    New-Item -ItemType Directory -Path (Join-Path $Directory 'plugins') -Force | Out-Null
    if ($Fresh) {
        foreach ($w in @('world', 'world_nether', 'world_the_end')) {
            $p = Join-Path $Directory $w
            if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force }
        }
        Write-Host ('deleted the test world (' + $Directory + ')')
    }
    $cfg = Get-PaperDevLocalConfig
    Write-PaperDevText -Path (Join-Path $Directory 'eula.txt') -Text ("# Agreed by the user (papermc-developer setup.ps1 -AcceptEula, " + $cfg.eulaAcceptedAt + "): " + $PaperDevEulaUrl + "`neula=true`n")
    $props = [ordered]@{
        'server-ip' = '127.0.0.1'; 'server-port' = $Port; 'online-mode' = $(if ($OnlineMode) { 'true' } else { 'false' })
        'enable-rcon' = 'true'; 'rcon.port' = $RconPort; 'rcon.password' = $Password; 'broadcast-rcon-to-ops' = 'false'
        'motd' = $Motd
        'generate-structures' = 'false'; 'spawn-protection' = '0'
        'view-distance' = '6'; 'simulation-distance' = '6'; 'max-players' = '5'
    }
    if ($Era.FlatWorld) {
        # A flat world needs its layers; with the default "{}" the server logs "No key layers" as an ERROR.
        $props['level-type'] = 'minecraft\:flat'
        $props['generator-settings'] = '{"layers":[{"block":"minecraft:bedrock","height":1},{"block":"minecraft:dirt","height":2},{"block":"minecraft:grass_block","height":1}],"biome":"minecraft:plains"}'
    } else {
        # Before 1.19 the flat generator settings had other formats; use a normal world.
        $props['level-type'] = 'default'
        $props['generator-settings'] = ''
    }
    Set-PaperDevProperties -Path (Join-Path $Directory 'server.properties') -Values $props
}

function Set-PaperDevVelocityForwarding {
    # Paper 1.19+ behind Velocity: modern forwarding in config/paper-global.yml (proxies.velocity).
    # A missing file is created with only that section; Paper adds its other defaults on start.
    param([string]$Directory, [string]$Secret)
    $path = Join-Path $Directory 'config/paper-global.yml'
    if (-not (Test-Path -LiteralPath $path)) {
        Write-PaperDevText -Path $path -Text ("proxies:`n  velocity:`n    enabled: true`n    online-mode: true`n    secret: '" + $Secret + "'`n")
        return
    }
    $text = Read-PaperDevText $path
    $m = [regex]::Match($text, '(?m)^  velocity:\r?\n((?:    [^\r\n]*\r?\n)+)')
    if (-not $m.Success) { throw ('no proxies.velocity section in ' + $path) }
    $block = $m.Groups[1].Value
    $block = $block -replace '(?m)^(    enabled:).*$', '$1 true'
    $block = $block -replace '(?m)^(    online-mode:).*$', '$1 true'
    $block = $block -replace '(?m)^(    secret:).*$', ('$1 ''' + $Secret + '''')
    Write-PaperDevText -Path $path -Text ($text.Substring(0, $m.Groups[1].Index) + $block + $text.Substring($m.Groups[1].Index + $m.Groups[1].Length))
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
    $main = $null
    if ($Project.Descriptor) { $main = (Read-PaperDevDescriptor $Project.Descriptor).Values['main'] }
    elseif ($Project.Kind -eq 'velocity') { $v = Get-PaperDevVelocityPlugin $Project; if ($v) { $main = $v.Main } }
    if ($main -and $main -match '^(.+)\.[^.]+$') { return $Matches[1] }
    return $null
}

function Write-PaperDevServerReport {
    # Prints what the log says about the plugin. Returns the number of problems (ERROR entries, plugin not enabled).
    param([array]$Entries, [string]$PluginName, [string]$Package, [switch]$RequireEnabled, [int]$MaxEntries = 20, [switch]$Velocity)
    $problems = 0
    $name = [regex]::Escape($PluginName)
    if ($Velocity) {
        # Velocity: "Loaded plugin <id> <version> by <authors>"; failures name the plugin id.
        $enabled = @($Entries | Where-Object { $_.Message -match ('^Loaded plugin ' + $name + '\b') })
        $failedEnable = @($Entries | Where-Object { ($_.Level -eq 'ERROR') -and ($_.Message -match ('(?i)(can''t|cannot|unable to|failed to|could not)[^\r\n]*' + $name)) })
    } else {
        $enabled = @($Entries | Where-Object { $_.Message -match ('^\[' + $name + '\] Enabling ' + $name + ' v') })
        $failedEnable = @($Entries | Where-Object { $_.Message -match ('(Error occurred while enabling|Could not load|Could not enable|Unable to load|Failed to load).*' + $name) })
    }
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
