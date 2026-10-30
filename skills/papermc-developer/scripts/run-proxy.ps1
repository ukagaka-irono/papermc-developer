<#
.SYNOPSIS
  Builds a Velocity plugin and (re)starts a test Velocity proxy with it, with a Paper server behind the proxy.
.DESCRIPTION
  scripts/run-server.ps1 runs this for Velocity projects; it can also be called directly.
  Everything lives in <home>/servers/<project>-<hash>/: proxy/ (Velocity) and backend/ (Paper). Both listen on
  127.0.0.1 only. The proxy (ports 25610+) forwards players to the backend (25620+, RCON 25630+) with Velocity's
  modern forwarding (a shared secret; the backend runs with online-mode=false and accepts only the proxy).
  1. builds the jar unless -NoBuild,
  2. stops the proxy and the backend if they run,
  3. gets the Velocity jar (the project's velocity-api version, or -VelocityVersion) and the Paper jar
     (-Minecraft, default the latest stable; 1.19 or later) - cached, SHA-256 checked,
  4. writes velocity.toml (from the jar's defaults: bind, forwarding, the one backend server), forwarding.secret,
     the backend's server.properties and config/paper-global.yml, and copies the plugin jar (and -ExtraPlugin
     jars) into proxy/plugins/ and -BackendPlugin jars into backend/plugins/,
  5. starts the backend, then the proxy through lib/console-bridge.ps1 (Velocity has no RCON: console commands
     go through it, scripts/rcon.ps1), waits for "Done", and reports whether the plugin was loaded and the
     errors in the proxy's log.
  The user joins the proxy (localhost:<proxy port>) with their client and lands on the backend.
  Needs the user's agreement to the Minecraft EULA (the backend is a Minecraft server).
  -Stop / -Status / -Fresh (deletes the backend world) / -JdwpPort (debugger on the proxy) as in run-server.ps1.
  Exit codes: 0 started, plugin loaded, no errors / 1 build failed or a server did not start /
              2 started but the plugin was not loaded or the log has errors / 3 no EULA agreement, java or jar.
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-proxy.ps1
#>
param(
    [string]$ProjectRoot,
    [switch]$Stop,
    [switch]$Status,
    [switch]$NoBuild,
    [switch]$Fresh,
    [string]$Minecraft,
    [string]$VelocityVersion,
    [string]$Platform,
    [string]$Memory = '1G',
    [string[]]$ExtraPlugin = @(),
    [string[]]$BackendPlugin = @(),
    [int]$JdwpPort = 0,
    [int]$TimeoutSeconds = 300,
    [string]$JavaPath
)
. (Join-Path $PSScriptRoot 'lib/common.ps1')
. (Join-Path $PSScriptRoot 'lib/server.ps1')
Initialize-PaperDevConsole

$project = Resolve-PaperDevProject $ProjectRoot
if (-not $project) { Write-PaperDevStatus 'error' 'no Gradle or Maven project found (pass -ProjectRoot)'; exit 1 }
if ($project.Kind -ne 'velocity') { Write-PaperDevStatus 'error' 'not a Velocity project (no velocity-api in the build); use scripts/run-server.ps1'; exit 1 }
$serverDir = Get-PaperDevServerDir $project
$proxyDir = Join-Path $serverDir 'proxy'
$backendDir = Join-Path $serverDir 'backend'
$session = Get-PaperDevSession $project
$running = Test-PaperDevServerRunning $session

if ($Status) {
    if ($running) {
        Write-PaperDevStatus 'ok' ('running: velocity ' + $session.velocity + ' build ' + $session.build + ' (pid ' + $session.pid + '), backend paper ' + $session.backend.minecraft + ' (pid ' + $session.backend.pid + ')')
        Write-Host ('          join: localhost:' + $session.port + '   backend: 127.0.0.1:' + $session.backend.port + ' (rcon ' + $session.backend.rconPort + ')   folder: ' + $serverDir)
        exit 0
    }
    Write-PaperDevStatus 'stopped' ('the test proxy is not running (folder: ' + $serverDir + ')')
    exit 0
}
if ($Stop) {
    if (Stop-PaperDevServer $session) { Write-PaperDevStatus 'ok' 'the test proxy and its backend stopped' }
    else { Write-PaperDevStatus 'ok' 'the test proxy was not running' }
    exit 0
}

$cfg = Get-PaperDevLocalConfig
if (-not ($cfg.PSObject.Properties['eulaAccepted'] -and $cfg.eulaAccepted -eq $true)) {
    Write-PaperDevStatus 'missing' ('the Minecraft EULA has not been agreed to: ' + $PaperDevEulaUrl + ' (the backend behind the proxy is a Minecraft server)')
    Write-Host '          Ask the user to read it. Only if they agree: scripts/setup.ps1 -AcceptEula'
    exit 3
}

# Versions: Velocity from the project's velocity-api (or the latest stable), the backend from -Minecraft.
$versions = Get-PaperDevProjectVersions $project
try {
    $velocity = $VelocityVersion
    $known = Get-PaperDevMinecraftVersions 'velocity'
    if (-not $velocity -and $versions.Velocity -and $known -contains $versions.Velocity) { $velocity = $versions.Velocity }
    if (-not $velocity) {
        $velocity = Get-PaperDevLatestVelocity
        if ($versions.Velocity) { Write-PaperDevStatus 'note' ('no Velocity build for velocity-api ' + $versions.Velocity + '; using ' + $velocity) }
    }
    $velocityJava = [int](Get-PaperDevVersionInfo -Minecraft $velocity -Project 'velocity').JavaMinimum
    $mc = $Minecraft
    if (-not $mc) { $mc = Get-PaperDevLatestMinecraft }
    if (-not (Test-PaperDevVersionAtLeast $mc '1.19')) { Write-PaperDevStatus 'error' ('the test backend needs Paper 1.19 or later (modern forwarding in config/paper-global.yml); got ' + $mc); exit 1 }
    $mcJava = [int](Get-PaperDevVersionInfo -Minecraft $mc).JavaMinimum
} catch { Write-PaperDevStatus 'error' ('version lookup failed: ' + $_.Exception.Message); exit 3 }

$java = Get-PaperDevJava
if (-not $java) { Write-PaperDevStatus 'missing' 'java not found (scripts/doctor.ps1)'; exit 3 }
$proxyJava = $null
if ($JavaPath) { $proxyJava = Get-PaperDevJava $JavaPath }
else {
    $jdks = @(Find-PaperDevJdks | Where-Object { $_.Major -ge $velocityJava } | Sort-Object Major)
    if ($jdks.Count -gt 0) { $proxyJava = Get-PaperDevJava $jdks[0].Java }
}
if (-not $proxyJava) {
    Write-PaperDevStatus 'missing' ('Velocity ' + $velocity + ' needs Java ' + $velocityJava + '+; no such JDK is installed')
    Write-Host ('          Ask the user, then: scripts/setup.ps1 -Jdk ' + $velocityJava)
    exit 3
}
$backendJava = Get-PaperDevServerJava -Minecraft $mc -JavaMinimum $mcJava
if (-not $backendJava) {
    $era0 = Get-PaperDevEra -Minecraft $mc -JavaMinimum $mcJava
    Write-PaperDevStatus 'missing' ('Paper ' + $mc + ' (the backend) runs on Java ' + (Format-PaperDevJavaRange $era0) + '; no such JDK is installed')
    Write-Host ('          Ask the user, then: scripts/setup.ps1 -Jdk ' + $era0.JavaPreferred)
    exit 3
}

$plugin = Get-PaperDevVelocityPlugin $project
$pluginId = Get-PaperDevPluginName $project
$package = $null
if ($plugin -and $plugin.Main -match '^(.+)\.[^.]+$') { $package = $Matches[1] }

# 1. build
if (-not $NoBuild) {
    Write-Host ('build: ' + $project.BuildTool + ' assemble')
    $r = Invoke-PaperDevBuild -Project $project -Tasks @('assemble') -JavaHome (Split-Path -Parent (Split-Path -Parent $java.Path))
    if (-not $r) { Write-PaperDevStatus 'missing' 'no gradlew / gradle (or mvnw / mvn) found'; exit 3 }
    if ($r.ExitCode -ne 0) {
        $msgs = @(Get-PaperDevCompilerMessages ($r.StdOut + "`n" + $r.StdErr) | Where-Object { $_.Level -eq 'error' })
        foreach ($m in $msgs) { Write-PaperDevStatus 'error' ($m.File + ':' + $m.Line + ': ' + $m.Message) }
        if ($msgs.Count -eq 0) { Write-Host (($r.StdOut + "`n" + $r.StdErr) -split "`r?`n" | Select-Object -Last 30 | Out-String) }
        Write-PaperDevStatus 'error' 'build failed; nothing was started (scripts/check.ps1 shows details)'
        exit 1
    }
}
$jar = Find-PaperDevPluginJar $project
if (-not $jar) { Write-PaperDevStatus 'error' 'no plugin jar in build/libs or target (build first)'; exit 1 }

# 2. stop
if ($session) {
    if ($running -or ($session.PSObject.Properties['backend'] -and $session.backend -and (Test-PaperDevProcessAlive ([int]$session.backend.pid)))) {
        Write-Host 'stopping the running test proxy and backend'
        Stop-PaperDevServer $session | Out-Null
    }
}

# 3. jars
try {
    $velocityJar = Get-PaperDevServerJar -Minecraft $velocity -Project 'velocity'
    $paperJar = Get-PaperDevServerJar -Minecraft $mc -Project 'paper'
} catch { Write-PaperDevStatus 'error' ('cannot get the server jars: ' + $_.Exception.Message); exit 3 }

# 4. ports, secret, folders
$old = $null
if ($session -and $session.PSObject.Properties['backend']) { $old = $session.backend }
$proxyPort = 0; $backendPort = 0; $rconPort = 0; $password = $null
if ($session) { $proxyPort = [int]$session.port }
if ($old) { $backendPort = [int]$old.port; $rconPort = [int]$old.rconPort; $password = [string]$old.rconPassword }
if ($proxyPort -le 0 -or -not (Test-PaperDevPortFree $proxyPort)) { $proxyPort = Find-PaperDevFreePort 25610 25619 }
if ($backendPort -le 0 -or -not (Test-PaperDevPortFree $backendPort)) { $backendPort = Find-PaperDevFreePort 25620 25629 }
if ($rconPort -le 0 -or -not (Test-PaperDevPortFree $rconPort)) { $rconPort = Find-PaperDevFreePort 25630 25639 }
if ($proxyPort -le 0 -or $backendPort -le 0 -or $rconPort -le 0) { Write-PaperDevStatus 'error' 'no free port in 25610-25639'; exit 1 }
if (-not $password) { $password = New-PaperDevPassword }
New-Item -ItemType Directory -Path (Join-Path $proxyDir 'plugins') -Force | Out-Null
$secretPath = Join-Path $proxyDir 'forwarding.secret'
if (-not (Test-Path -LiteralPath $secretPath)) { Write-PaperDevText -Path $secretPath -Text (New-PaperDevPassword) }
$secret = (Get-Content -LiteralPath $secretPath -Raw).Trim()

$era = Get-PaperDevEra -Minecraft $mc -JavaMinimum $mcJava
Initialize-PaperDevPaperFolder -Directory $backendDir -Minecraft $mc -Era $era -Port $backendPort -RconPort $rconPort -Password $password -Motd 'papermc-developer test backend' -OnlineMode $false -Fresh:$Fresh
Set-PaperDevVelocityForwarding -Directory $backendDir -Secret $secret

# velocity.toml: the defaults from the Velocity jar, with our bind address, forwarding, and one backend.
$tomlPath = Join-Path $proxyDir 'velocity.toml'
if (-not (Test-Path -LiteralPath $tomlPath)) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($velocityJar.Path)
    try {
        $entry = $zip.GetEntry('default-velocity.toml')
        if (-not $entry) { Write-PaperDevStatus 'error' 'default-velocity.toml is not in the Velocity jar'; exit 1 }
        $reader = New-Object System.IO.StreamReader($entry.Open(), [System.Text.Encoding]::UTF8)
        try { Write-PaperDevText -Path $tomlPath -Text $reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally { $zip.Dispose() }
}
$toml = Read-PaperDevText $tomlPath
$toml = $toml -replace '(?m)^bind\s*=.*$', ('bind = "127.0.0.1:' + $proxyPort + '"')
$toml = $toml -replace '(?m)^motd\s*=.*$', ('motd = "papermc-developer test proxy: ' + $pluginId + '"')
$toml = $toml -replace '(?m)^player-info-forwarding-mode\s*=.*$', 'player-info-forwarding-mode = "MODERN"'
$toml = $toml -replace '(?m)^forwarding-secret-file\s*=.*$', 'forwarding-secret-file = "forwarding.secret"'
$toml = [regex]::Replace($toml, '(?ms)^\[servers\]\r?\n.*?(?=^\[)', ('[servers]' + "`n" + 'backend = "127.0.0.1:' + $backendPort + '"' + "`n" + 'try = [' + "`n" + '    "backend"' + "`n" + ']' + "`n`n"))
$toml = [regex]::Replace($toml, '(?ms)^\[forced-hosts\]\r?\n.*?(?=^\[)', ('[forced-hosts]' + "`n`n"))
Write-PaperDevText -Path $tomlPath -Text $toml

function Copy-Plugins {
    param([string]$Directory, [string[]]$Jars, [string[]]$Previous)
    $plugins = Join-Path $Directory 'plugins'
    New-Item -ItemType Directory -Path $plugins -Force | Out-Null
    foreach ($p in $Previous) { $f = Join-Path $plugins $p; if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force } }
    $names = @()
    foreach ($src in $Jars) {
        if (-not (Test-Path -LiteralPath $src)) { throw ('not found: ' + $src) }
        Copy-Item -LiteralPath $src -Destination (Join-Path $plugins (Split-Path -Leaf $src)) -Force
        $names += (Split-Path -Leaf $src)
    }
    return ,$names
}
$prevProxy = @(); $prevBackend = @()
if ($session -and $session.PSObject.Properties['deployed']) { $prevProxy = @($session.deployed) }
if ($old -and $old.PSObject.Properties['deployed']) { $prevBackend = @($old.deployed) }
try {
    $proxyPlugins = Copy-Plugins -Directory $proxyDir -Jars (@($jar) + $ExtraPlugin) -Previous $prevProxy
    $backendPlugins = Copy-Plugins -Directory $backendDir -Jars $BackendPlugin -Previous $prevBackend
} catch { Write-PaperDevStatus 'error' $_.Exception.Message; exit 1 }
Write-Host ('proxy plugins: ' + ($proxyPlugins -join ', ') + $(if ($backendPlugins.Count) { '   backend plugins: ' + ($backendPlugins -join ', ') } else { '' }))

# 5. backend, then proxy
$backendLog = Join-Path $backendDir 'logs/latest.log'
if (Test-Path -LiteralPath $backendLog) { Remove-Item -LiteralPath $backendLog -Force }
$bjvm = @('-Xms1G', '-Xmx1G', '-Dterminal.jline=false', '-Dterminal.ansi=false', '-Dfile.encoding=UTF-8', '-jar', $paperJar.Path, (Get-PaperDevNoGuiArgument $mc))
$backendProc = Start-PaperDevServerProcess -Directory $backendDir -Java $backendJava.Path -Arguments $bjvm -ConsolePath (Join-Path $backendDir 'console.log')
$backend = [PSCustomObject]@{
    pid = $backendProc.Id; port = $backendPort; rconPort = $rconPort; rconPassword = $password; platform = 'paper'; minecraft = $mc
    build = $paperJar.Build.Build; deployed = $backendPlugins
}
Write-Host ('starting the backend: paper ' + $mc + ' build ' + $paperJar.Build.Build + ' (pid ' + $backendProc.Id + ', java ' + $backendJava.Version + ')')
if (-not (Wait-PaperDevServerDone -LogPath $backendLog -ProcessId $backendProc.Id -TimeoutSeconds $TimeoutSeconds)) {
    Write-PaperDevStatus 'error' 'the backend Paper server did not start'
    if (Test-PaperDevProcessAlive $backendProc.Id) { Stop-PaperDevProcessTree $backendProc.Id }
    $entries = Get-PaperDevLogEntries $backendLog
    if ($entries.Count -gt 0) { Write-PaperDevServerReport -Entries $entries -PluginName 'backend' -Package '' | Out-Null }
    exit 1
}

$proxyLog = Join-Path $proxyDir 'logs/latest.log'
if (Test-Path -LiteralPath $proxyLog) { Remove-Item -LiteralPath $proxyLog -Force }
$queue = Join-Path $proxyDir 'papermc-developer-console.txt'
$pjvm = @(('-Xms' + $Memory), ('-Xmx' + $Memory), '-Dterminal.jline=false', '-Dterminal.ansi=false', '-Dfile.encoding=UTF-8')
if ($JdwpPort -gt 0) { $pjvm += ('-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=127.0.0.1:' + $JdwpPort) }
$pjvm += @('-jar', $velocityJar.Path)
$started = Start-PaperDevBridgedProcess -Directory $proxyDir -Java $proxyJava.Path -Arguments $pjvm -ConsolePath (Join-Path $proxyDir 'console.log') -Queue $queue
$session = [PSCustomObject]@{
    pid = $started.JavaPid; bridgePid = $started.Bridge.Id; queue = $queue; port = $proxyPort; platform = 'velocity'; velocity = $velocity
    build = $velocityJar.Build.Build; pluginName = $pluginId; package = $package; deployed = $proxyPlugins; backend = $backend
    startedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK'); jdwpPort = $JdwpPort; project = $project.Root
}
Save-PaperDevSession $project $session
if ($started.JavaPid -le 0) {
    Write-PaperDevStatus 'error' 'the proxy did not start (lib/console-bridge.ps1)'
    $c = Join-Path $proxyDir 'console.log'
    if (Test-Path -LiteralPath $c) { Get-Content -LiteralPath $c -Tail 20 | ForEach-Object { Write-Host $_ } }
    exit 1
}
Write-Host ('starting the proxy: velocity ' + $velocity + ' build ' + $velocityJar.Build.Build + ' (pid ' + $started.JavaPid + ', java ' + $proxyJava.Version + ')')
if (-not (Wait-PaperDevServerDone -LogPath $proxyLog -ProcessId $started.JavaPid -TimeoutSeconds $TimeoutSeconds)) {
    Write-PaperDevStatus 'error' 'the proxy did not finish starting'
    if (Test-PaperDevProcessAlive $started.JavaPid) { Stop-PaperDevProcessTree $started.Bridge.Id }
    $entries = Get-PaperDevLogEntries $proxyLog
    if ($entries.Count -gt 0) { Write-PaperDevServerReport -Entries $entries -PluginName $pluginId -Package $package -Velocity | Out-Null }
    $c = Join-Path $proxyDir 'console.log'
    if (Test-Path -LiteralPath $c) { Write-Host '---- console.log (last lines)'; Get-Content -LiteralPath $c -Tail 20 | ForEach-Object { Write-Host $_ } }
    exit 1
}

$entries = Get-PaperDevLogEntries $proxyLog
$problems = Write-PaperDevServerReport -Entries $entries -PluginName $pluginId -Package $package -RequireEnabled -Velocity
Write-Host ('join: localhost:' + $proxyPort + ' (Minecraft ' + $mc + ' client; the proxy sends you to the backend)')
Write-Host 'proxy console: scripts/rcon.ps1 "<command>"   backend: scripts/rcon.ps1 -Backend "<command>"   log: scripts/server-log.ps1 [-Backend]'
if ($JdwpPort -gt 0) { Write-Host ('debugger: attach to 127.0.0.1:' + $JdwpPort) }
Write-Host 'stop: scripts/run-server.ps1 -Stop'
if ($problems -gt 0) { exit 2 }
exit 0
