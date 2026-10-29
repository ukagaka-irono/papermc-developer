<#
.SYNOPSIS
  Builds the plugin and (re)starts a test Paper server with it, in the background.
.DESCRIPTION
  The test server is separate from any server of the user: it lives in the home folder
  (<home>/servers/<project>-<hash>/), listens on 127.0.0.1 only (game port from 25566, RCON from 25576),
  uses a flat world, and keeps its world between runs. The script:
  1. builds the jar (gradlew assemble / mvn package -DskipTests) unless -NoBuild,
  2. stops the test server if it runs (RCON "stop": the world is saved, onDisable runs),
  3. gets the Paper (or Folia) server jar of the project's Minecraft version (cached, SHA-256 checked),
  4. copies the plugin jar (and -ExtraPlugin jars) into plugins/, replacing the previous copy,
  5. starts the server and waits for "Done", then reports whether the plugin was enabled and the
     errors and the warnings about the plugin in logs/latest.log.
  Needs the user's agreement to the Minecraft EULA, recorded by scripts/setup.ps1 -AcceptEula.
  Afterwards: scripts/rcon.ps1 sends commands, scripts/server-log.ps1 reads the log.
  The user can join with their own client at the printed address (localhost:<port>).
  -Stop       stops the test server     -Status   shows whether it runs
  -Fresh      deletes the test world before starting (the plugin's data in plugins/<name>/ is kept)
  -JdwpPort   opens a Java debugger port (attach the IDE: Remote JVM Debug, 127.0.0.1:<port>)
  -JavaPath   the java (or JDK folder) to run the server with; by default an installed JDK the version runs on
              (Paper 1.16.5 and earlier: Java 8-11; scripts/setup.ps1 -Jdk <n> installs one)
  Exit codes: 0 started, plugin enabled, no errors / 1 build failed or the server did not start /
              2 started but the plugin was not enabled or the log has errors / 3 no EULA agreement, java or server jar.
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-server.ps1
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-server.ps1 -Stop
#>
param(
    [string]$ProjectRoot,
    [switch]$Stop,
    [switch]$Status,
    [switch]$NoBuild,
    [switch]$Fresh,
    [string]$Minecraft,
    [ValidateSet('', 'paper', 'folia')][string]$Platform = '',
    [string]$Memory = '2G',
    [string[]]$ExtraPlugin = @(),
    [int]$JdwpPort = 0,
    [int]$TimeoutSeconds = 300,
    [string]$JavaPath
)
. (Join-Path $PSScriptRoot 'lib/common.ps1')
. (Join-Path $PSScriptRoot 'lib/server.ps1')
Initialize-PaperDevConsole

$project = Resolve-PaperDevProject $ProjectRoot
if (-not $project) { Write-PaperDevStatus 'error' 'no Gradle or Maven project found (pass -ProjectRoot)'; exit 1 }
if ($project.Kind -eq 'velocity') {
    # A Velocity plugin runs on a test proxy with a Paper server behind it.
    & (Join-Path $PSScriptRoot 'run-proxy.ps1') @PSBoundParameters
    exit $LASTEXITCODE
}
$serverDir = Get-PaperDevServerDir $project
$session = Get-PaperDevSession $project
$running = Test-PaperDevServerRunning $session

if ($Status) {
    if ($running) {
        Write-PaperDevStatus 'ok' ('running: ' + $session.platform + ' ' + $session.minecraft + ' build ' + $session.build + ', pid ' + $session.pid)
        Write-Host ('          game: localhost:' + $session.port + '   rcon: 127.0.0.1:' + $session.rconPort + '   folder: ' + $serverDir)
        exit 0
    }
    Write-PaperDevStatus 'stopped' ('the test server is not running (folder: ' + $serverDir + ')')
    exit 0
}

if ($Stop) {
    if (Stop-PaperDevServer $session) { Write-PaperDevStatus 'ok' 'the test server stopped' }
    else { Write-PaperDevStatus 'ok' 'the test server was not running' }
    exit 0
}

$cfg = Get-PaperDevLocalConfig
if (-not ($cfg.PSObject.Properties['eulaAccepted'] -and $cfg.eulaAccepted -eq $true)) {
    Write-PaperDevStatus 'missing' ('the Minecraft EULA has not been agreed to: ' + $PaperDevEulaUrl)
    Write-Host '          Ask the user to read it. Only if they agree: scripts/setup.ps1 -AcceptEula'
    exit 3
}

$versions = Get-PaperDevProjectVersions $project
# Folia: when the build uses folia-api, or when asked (-Platform folia) for a plugin with "folia-supported: true".
# (PowerShell names are case-insensitive: $platform below is the -Platform parameter itself.)
if (-not $Platform) {
    $Platform = 'paper'
    if ($versions.Platform -eq 'folia') { $Platform = 'folia' }
}
$platform = $Platform
if ($platform -eq 'folia' -and -not $versions.FoliaSupported) {
    Write-PaperDevStatus 'error' 'Folia loads only plugins with "folia-supported: true" in plugin.yml / paper-plugin.yml (references/paper-api.md, Folia)'
    exit 1
}
$mc = $Minecraft
if (-not $mc) { $mc = $versions.Minecraft }
try {
    if (-not $mc) { $mc = Get-PaperDevLatestMinecraft -Project $platform; Write-PaperDevStatus 'note' ('no Minecraft version in the build files; using the latest stable ' + $mc) }
    if ($platform -eq 'folia' -and (Get-PaperDevMinecraftVersions 'folia') -notcontains $mc) {
        Write-PaperDevStatus 'missing' ('Folia has no build for ' + $mc + ' (Folia versions: ' + ((Get-PaperDevMinecraftVersions 'folia') -join ', ') + '); pass -Minecraft <version>')
        exit 3
    }
    $javaNeeded = (Get-PaperDevVersionInfo -Minecraft $mc -Project $platform).JavaMinimum
} catch { Write-PaperDevStatus 'error' ('cannot look up ' + $platform + ' ' + $mc + ': ' + $_.Exception.Message); exit 3 }

# Two javas: one that runs Gradle (17+), and the one the server of this version runs on (old servers do not
# start on new Java: 1.16.5 and earlier need Java 8 to 11, see Get-PaperDevEra).
$era = Get-PaperDevEra -Minecraft $mc -JavaMinimum ([int]$javaNeeded)
$java = Get-PaperDevJava
if (-not $java) { Write-PaperDevStatus 'missing' 'java not found (scripts/doctor.ps1)'; exit 3 }
$serverJava = Get-PaperDevServerJava -Minecraft $mc -JavaMinimum ([int]$javaNeeded) -JavaPath $JavaPath
if (-not $serverJava) {
    $range = [string]$era.JavaMin
    if ($era.JavaMax -ge 99) { $range += '+' } elseif ($era.JavaMax -ne $era.JavaMin) { $range += '-' + $era.JavaMax }
    Write-PaperDevStatus 'missing' ($platform + ' ' + $mc + ' runs on Java ' + $range + '; no such JDK is installed')
    Write-Host ('          Ask the user, then: scripts/setup.ps1 -Jdk ' + $era.JavaPreferred + '  (downloads Eclipse Temurin ' + $era.JavaPreferred + ' into the home folder)')
    exit 3
}
if ($serverJava.Major -lt $era.JavaMin -or $serverJava.Major -gt $era.JavaMax) { Write-PaperDevStatus 'warn' ($platform + ' ' + $mc + ' expects Java ' + $era.JavaMin + '-' + $era.JavaMax + '; starting with ' + $serverJava.Version + ' as asked') }

$pluginName = Get-PaperDevPluginName $project
$package = Get-PaperDevPluginPackage $project

# 1. build
if (-not $NoBuild) {
    Write-Host ('build: ' + $project.BuildTool + ' assemble')
    $r = Invoke-PaperDevBuild -Project $project -Tasks @('assemble') -JavaHome (Split-Path -Parent (Split-Path -Parent $java.Path))
    if (-not $r) { Write-PaperDevStatus 'missing' 'no gradlew / gradle (or mvnw / mvn) found'; exit 3 }
    if ($r.ExitCode -ne 0) {
        $msgs = @(Get-PaperDevCompilerMessages ($r.StdOut + "`n" + $r.StdErr) | Where-Object { $_.Level -eq 'error' })
        foreach ($m in $msgs) { Write-PaperDevStatus 'error' ($m.File + ':' + $m.Line + ': ' + $m.Message) }
        if ($msgs.Count -eq 0) { Write-Host (($r.StdOut + "`n" + $r.StdErr) -split "`r?`n" | Select-Object -Last 30 | Out-String) }
        Write-PaperDevStatus 'error' 'build failed; the server was not started (scripts/check.ps1 shows details)'
        exit 1
    }
}
$jar = Find-PaperDevPluginJar $project
if (-not $jar) { Write-PaperDevStatus 'error' 'no plugin jar in build/libs or target (build first)'; exit 1 }

# 2. stop
if ($running) {
    Write-Host 'stopping the running test server'
    Stop-PaperDevServer $session | Out-Null
} elseif ($session -and (Test-PaperDevProcessAlive ([int]$session.pid))) {
    Stop-PaperDevProcessTree ([int]$session.pid)
}

# 3. server jar
try { $server = Get-PaperDevServerJar -Minecraft $mc -Project $platform }
catch { Write-PaperDevStatus 'error' ('cannot get the ' + $platform + ' server jar: ' + $_.Exception.Message); exit 3 }

# 4. folder, properties, plugins
$port = 0; $rconPort = 0; $password = $null
if ($session) { $port = [int]$session.port; $rconPort = [int]$session.rconPort; $password = [string]$session.rconPassword }
if ($port -le 0 -or -not (Test-PaperDevPortFree $port)) { $port = Find-PaperDevFreePort 25566 25575 }
if ($rconPort -le 0 -or -not (Test-PaperDevPortFree $rconPort)) { $rconPort = Find-PaperDevFreePort 25576 25599 @($port) }
if ($port -le 0 -or $rconPort -le 0) { Write-PaperDevStatus 'error' 'no free port in 25566-25599'; exit 1 }
if (-not $password) { $password = New-PaperDevPassword }
Initialize-PaperDevPaperFolder -Directory $serverDir -Minecraft $mc -Era $era -Port $port -RconPort $rconPort -Password $password -Motd ('papermc-developer test server: ' + $pluginName) -Fresh:$Fresh

$pluginsDir = Join-Path $serverDir 'plugins'
$deployed = @()
if ($session -and $session.PSObject.Properties['deployed']) { $deployed = @($session.deployed) }
foreach ($old in $deployed) {
    $p = Join-Path $pluginsDir $old
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
}
$newDeployed = @()
foreach ($src in (@($jar) + $ExtraPlugin)) {
    if (-not (Test-Path -LiteralPath $src)) { Write-PaperDevStatus 'error' ('not found: ' + $src); exit 1 }
    $leaf = Split-Path -Leaf $src
    Copy-Item -LiteralPath $src -Destination (Join-Path $pluginsDir $leaf) -Force
    $newDeployed += $leaf
}
Write-Host ('plugins: ' + ($newDeployed -join ', '))

# 5. start
$logPath = Join-Path $serverDir 'logs/latest.log'
if (Test-Path -LiteralPath $logPath) { Remove-Item -LiteralPath $logPath -Force }
$consolePath = Join-Path $serverDir 'console.log'
$jvm = @(('-Xms' + $Memory), ('-Xmx' + $Memory), '-Dterminal.jline=false', '-Dterminal.ansi=false', '-Dfile.encoding=UTF-8')
if ($JdwpPort -gt 0) { $jvm += ('-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=127.0.0.1:' + $JdwpPort) }
$jvm += @('-jar', $server.Path, (Get-PaperDevNoGuiArgument $mc))
$proc = Start-PaperDevServerProcess -Directory $serverDir -Java $serverJava.Path -Arguments $jvm -ConsolePath $consolePath
$session = [PSCustomObject]@{
    pid = $proc.Id; port = $port; rconPort = $rconPort; rconPassword = $password; platform = $platform; minecraft = $mc
    build = $server.Build.Build; pluginName = $pluginName; package = $package; deployed = $newDeployed
    startedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK'); jdwpPort = $JdwpPort; project = $project.Root
}
Save-PaperDevSession $project $session
Write-Host ('starting ' + $platform + ' ' + $mc + ' build ' + $server.Build.Build + ' (pid ' + $proc.Id + ', java ' + $serverJava.Version + '); the first start takes longer')

$done = Wait-PaperDevServerDone -LogPath $logPath -ProcessId $proc.Id -TimeoutSeconds $TimeoutSeconds

if (-not $done) {
    if (Test-PaperDevProcessAlive $proc.Id) {
        Write-PaperDevStatus 'error' ('the server did not finish starting within ' + $TimeoutSeconds + 's; stopping it')
        Stop-PaperDevProcessTree $proc.Id
    } else {
        Write-PaperDevStatus 'error' 'the server stopped while starting'
    }
    $entries = Get-PaperDevLogEntries $logPath
    if ($entries.Count -gt 0) { Write-PaperDevServerReport -Entries $entries -PluginName $pluginName -Package $package | Out-Null }
    if (Test-Path -LiteralPath $consolePath) {
        Write-Host '---- console.log (last lines)'
        Get-Content -LiteralPath $consolePath -Tail 25 | ForEach-Object { Write-Host $_ }
    }
    exit 1
}

$entries = Get-PaperDevLogEntries $logPath
$problems = Write-PaperDevServerReport -Entries $entries -PluginName $pluginName -Package $package -RequireEnabled
Write-Host ('server: localhost:' + $port + ' (join with a Minecraft ' + $mc + ' client)   rcon: scripts/rcon.ps1 "<command>"   log: scripts/server-log.ps1')
if ($JdwpPort -gt 0) { Write-Host ('debugger: attach to 127.0.0.1:' + $JdwpPort) }
Write-Host 'stop: scripts/run-server.ps1 -Stop'
if ($problems -gt 0) { exit 2 }
exit 0
