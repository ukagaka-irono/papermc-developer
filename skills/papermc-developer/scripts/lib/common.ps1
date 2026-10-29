# Shared helpers for the papermc-developer scripts.
# Rules for every script: ASCII only (Windows PowerShell 5.1 reads BOM-less files as ANSI),
# no PowerShell 7-only syntax, exit codes 0 OK / 1 failed / 2 needs attention / 3 cannot check (tool missing).

$ErrorActionPreference = 'Stop'

$PaperDevName = 'papermc-developer'
$PaperDevRepo = 'ukagaka-irono/papermc-developer'
$PaperDevUserAgent = 'papermc-developer (+https://github.com/ukagaka-irono/papermc-developer)'
$PaperDevSkillDir = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$PaperDevFillApi = 'https://fill.papermc.io/v3/projects'
$PaperDevMavenPaper = 'https://repo.papermc.io/repository/maven-public'
$PaperDevMavenCentral = 'https://repo1.maven.org/maven2'
$PaperDevPluginPortal = 'https://plugins.gradle.org/m2'
$PaperDevEulaUrl = 'https://aka.ms/MinecraftEULA'
$PaperDevMavenSpigot = 'https://hub.spigotmc.org/nexus/content/repositories/snapshots'
$PaperDevSpigotVersions = 'https://hub.spigotmc.org/versions'
$PaperDevBuildToolsUrl = 'https://hub.spigotmc.org/jenkins/job/BuildTools/lastSuccessfulBuild/artifact/target/BuildTools.jar'

function Initialize-PaperDevConsole {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch { }
    try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
    $global:ProgressPreference = 'SilentlyContinue'
}

function Test-PaperDevWindows {
    return ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT)
}

# ---------------------------------------------------------------- output

function Write-PaperDevStatus {
    param([string]$Status, [string]$Message)
    $tag = '[' + $Status.ToUpperInvariant() + ']'
    Write-Host ($tag.PadRight(10) + $Message)
}

function Write-PaperDevCiAnnotation {
    param([ValidateSet('error', 'warning', 'notice')][string]$Level, [string]$Message, [string]$File, [int]$Line)
    $props = @()
    if ($File) { $props += ('file=' + $File) }
    if ($Line -gt 0) { $props += ('line=' + $Line) }
    $head = '::' + $Level
    if ($props.Count -gt 0) { $head += ' ' + ($props -join ',') }
    $text = $Message -replace '%', '%25' -replace "`r", '%0D' -replace "`n", '%0A'
    Write-Host ($head + '::' + $text)
}

# ---------------------------------------------------------------- home folder

function Get-PaperDevHome {
    $base = $env:PAPERMCDEV_HOME
    if (-not $base) {
        if ($env:LOCALAPPDATA) { $base = Join-Path $env:LOCALAPPDATA $PaperDevName }
        elseif ($env:XDG_DATA_HOME) { $base = Join-Path $env:XDG_DATA_HOME $PaperDevName }
        else { $base = Join-Path (Join-Path $HOME '.local/share') $PaperDevName }
    }
    if (-not (Test-Path -LiteralPath $base)) { New-Item -ItemType Directory -Path $base -Force | Out-Null }
    return (Resolve-Path -LiteralPath $base).Path
}

function Get-PaperDevHomeDir {
    param([string]$Name)
    $dir = Join-Path (Get-PaperDevHome) $Name
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return $dir
}

function Get-PaperDevLocalConfig {
    $path = Join-Path (Get-PaperDevHome) 'local.json'
    if (Test-Path -LiteralPath $path) {
        try { return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { }
    }
    return (New-Object PSObject)
}

function Set-PaperDevLocalConfig {
    param([string]$Key, $Value)
    $config = Get-PaperDevLocalConfig
    if ($config.PSObject.Properties[$Key]) { $config.$Key = $Value }
    else { $config | Add-Member -NotePropertyName $Key -NotePropertyValue $Value }
    $path = Join-Path (Get-PaperDevHome) 'local.json'
    Write-PaperDevText -Path $path -Text ($config | ConvertTo-Json -Depth 5)
}

function Write-PaperDevText {
    # UTF-8 without BOM, LF line endings.
    param([string]$Path, [string]$Text)
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $normalized = $Text -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($Path, $normalized, (New-Object System.Text.UTF8Encoding($false)))
}

function Read-PaperDevText {
    param([string]$Path)
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Get-PaperDevShortHash {
    param([string]$Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text.ToLowerInvariant()))
    return (-join ($bytes[0..3] | ForEach-Object { $_.ToString('x2') }))
}

function Get-PaperDevFileSha256 {
    param([string]$Path)
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        return (-join ($sha.ComputeHash($stream) | ForEach-Object { $_.ToString('x2') }))
    } finally { $stream.Dispose() }
}

# ---------------------------------------------------------------- processes

function ConvertTo-PaperDevArgumentString {
    param([string[]]$Arguments)
    $parts = foreach ($a in $Arguments) {
        if ($null -eq $a) { continue }
        if ($a -eq '') { '""' }
        elseif ($a -notmatch '[\s"]') { $a }
        else { '"' + ($a -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"' }
    }
    return ($parts -join ' ')
}

function Invoke-PaperDevDetachedProcess {
    # Like Invoke-PaperDevProcess, but the program inherits none of this process's handles (ShellExecute) and writes
    # its output to a temporary file. Build tools that leave a daemon behind (Gradle) would otherwise keep the
    # caller's output pipe open through the daemon, and whoever runs this script would never see it return.
    param([string]$FilePath, [string[]]$Arguments, [string]$WorkingDirectory, [hashtable]$Environment)
    $Arguments = @($Arguments | Where-Object { $null -ne $_ -and $_ -ne '' })
    $out = Join-Path ([System.IO.Path]::GetTempPath()) ('papermc-developer-' + [guid]::NewGuid().ToString('N') + '.log')
    if (-not $WorkingDirectory) { $WorkingDirectory = (Get-Location).Path }
    $saved = @{}
    if ($Environment) {
        foreach ($k in $Environment.Keys) {
            $saved[$k] = [System.Environment]::GetEnvironmentVariable($k)
            [System.Environment]::SetEnvironmentVariable($k, [string]$Environment[$k])
        }
    }
    try {
        if (Test-PaperDevWindows) {
            $line = '/d /s /c ""' + $FilePath + '" ' + (ConvertTo-PaperDevArgumentString $Arguments) + ' > "' + $out + '" 2>&1 < NUL"'
            $p = Start-Process -FilePath $env:ComSpec -ArgumentList $line -WorkingDirectory $WorkingDirectory -WindowStyle Hidden -PassThru
        } else {
            $quoted = (@($FilePath) + $Arguments | ForEach-Object { "'" + ($_ -replace "'", "'\''") + "'" }) -join ' '
            $p = Start-Process -FilePath 'sh' -ArgumentList @('-c', ('exec ' + $quoted + " > '" + $out + "' 2>&1 < /dev/null")) -WorkingDirectory $WorkingDirectory -PassThru
        }
        $null = $p.Handle  # Windows PowerShell 5.1 loses ExitCode unless the handle is opened before the exit
        $p.WaitForExit()
        $code = $p.ExitCode
    } finally {
        foreach ($k in $saved.Keys) { [System.Environment]::SetEnvironmentVariable($k, $saved[$k]) }
    }
    $text = ''
    if (Test-Path -LiteralPath $out) {
        $text = Read-PaperDevText $out
        Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue
    }
    return [PSCustomObject]@{ ExitCode = $code; StdOut = $text; StdErr = '' }
}

function Invoke-PaperDevProcess {
    # Runs a program to completion and captures its output (no console window, no deadlock on full pipes).
    # Not for programs that start background processes (Gradle): use Invoke-PaperDevDetachedProcess.
    param([string]$FilePath, [string[]]$Arguments, [string]$WorkingDirectory, [hashtable]$Environment)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = ConvertTo-PaperDevArgumentString $Arguments
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    if ($WorkingDirectory) { $psi.WorkingDirectory = $WorkingDirectory }
    if ($Environment) { foreach ($k in $Environment.Keys) { $psi.EnvironmentVariables[$k] = [string]$Environment[$k] } }
    $p = [System.Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEndAsync()
    $err = $p.StandardError.ReadToEndAsync()
    $p.WaitForExit()
    return [PSCustomObject]@{ ExitCode = $p.ExitCode; StdOut = $out.Result; StdErr = $err.Result }
}

function Test-PaperDevProcessAlive {
    param([int]$ProcessId)
    if ($ProcessId -le 0) { return $false }
    try { $p = Get-Process -Id $ProcessId -ErrorAction Stop; return (-not $p.HasExited) } catch { return $false }
}

function Stop-PaperDevProcessTree {
    param([int]$ProcessId)
    if (-not (Test-PaperDevProcessAlive $ProcessId)) { return }
    if (Test-PaperDevWindows) {
        Invoke-PaperDevProcess -FilePath 'taskkill.exe' -Arguments @('/PID', [string]$ProcessId, '/T', '/F') | Out-Null
    } else {
        try { Stop-Process -Id $ProcessId -Force -ErrorAction Stop } catch { }
    }
}

# ---------------------------------------------------------------- network

function Invoke-PaperDevWeb {
    param([string]$Uri)
    $headers = @{ 'User-Agent' = $PaperDevUserAgent }
    if ($env:GITHUB_TOKEN -and $Uri -match '^https://api\.github\.com/') { $headers['Authorization'] = 'Bearer ' + $env:GITHUB_TOKEN }
    return (Invoke-WebRequest -Uri $Uri -Headers $headers -UseBasicParsing -TimeoutSec 60)
}

function Get-PaperDevJson {
    param([string]$Uri)
    $r = Invoke-PaperDevWeb $Uri
    $text = $r.Content
    if ($text -is [byte[]]) { $text = [System.Text.Encoding]::UTF8.GetString($text) }
    return ($text | ConvertFrom-Json)
}

function Get-PaperDevTextFromWeb {
    param([string]$Uri)
    $r = Invoke-PaperDevWeb $Uri
    $text = $r.Content
    if ($text -is [byte[]]) { $text = [System.Text.Encoding]::UTF8.GetString($text) }
    return $text
}

function Save-PaperDevDownload {
    # Downloads to a temporary name, checks SHA-256 when given, then moves into place.
    param([string]$Uri, [string]$OutFile, [string]$Sha256)
    $dir = Split-Path -Parent $OutFile
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $tmp = $OutFile + '.part'
    # WebClient: Invoke-WebRequest -OutFile is very slow for large files on Windows PowerShell 5.1.
    $wc = New-Object System.Net.WebClient
    try {
        $wc.Headers.Add('User-Agent', $PaperDevUserAgent)
        $wc.DownloadFile($Uri, $tmp)
    } finally { $wc.Dispose() }
    if ($Sha256) {
        $actual = Get-PaperDevFileSha256 $tmp
        if ($actual -ne $Sha256.ToLowerInvariant()) {
            Remove-Item -LiteralPath $tmp -Force
            throw ('SHA-256 mismatch for ' + $Uri + ' (expected ' + $Sha256 + ', got ' + $actual + ')')
        }
    }
    Move-Item -LiteralPath $tmp -Destination $OutFile -Force
}

function Get-PaperDevMavenRelease {
    # Latest <release> (or <latest>) from a maven-metadata.xml.
    param([string]$Repository, [string]$Group, [string]$Artifact)
    $url = $Repository + '/' + ($Group -replace '\.', '/') + '/' + $Artifact + '/maven-metadata.xml'
    [xml]$xml = Get-PaperDevTextFromWeb $url
    $v = $xml.metadata.versioning.release
    if (-not $v) { $v = $xml.metadata.versioning.latest }
    return [string]$v
}

function Get-PaperDevMavenVersions {
    param([string]$Repository, [string]$Group, [string]$Artifact)
    $url = $Repository + '/' + ($Group -replace '\.', '/') + '/' + $Artifact + '/maven-metadata.xml'
    [xml]$xml = Get-PaperDevTextFromWeb $url
    return @($xml.metadata.versioning.versions.version | ForEach-Object { [string]$_ })
}

function Get-PaperDevGradlePluginVersion {
    param([string]$PluginId)
    return (Get-PaperDevMavenRelease -Repository $PaperDevPluginPortal -Group $PluginId -Artifact ($PluginId + '.gradle.plugin'))
}

# ---------------------------------------------------------------- Paper versions (Fill API v3)

function Test-PaperDevPreRelease {
    param([string]$Version)
    return ($Version -match '(?i)-(rc|pre|snapshot)' -or $Version -match '(?i)^\d+w\d+')
}

function Get-PaperDevMinecraftVersions {
    # All versions of a project, newest first (the order of the Fill API).
    param([string]$Project = 'paper')
    $data = Get-PaperDevJson ($PaperDevFillApi + '/' + $Project)
    $list = @()
    foreach ($group in $data.versions.PSObject.Properties) { $list += @($group.Value) }
    return $list
}

function Get-PaperDevVersionInfo {
    param([string]$Minecraft, [string]$Project = 'paper')
    $data = Get-PaperDevJson ($PaperDevFillApi + '/' + $Project + '/versions/' + $Minecraft)
    $java = $null
    try { $java = [int]$data.version.java.version.minimum } catch { }
    $status = $null
    try { $status = [string]$data.version.support.status } catch { }
    return [PSCustomObject]@{ Minecraft = $Minecraft; JavaMinimum = $java; Support = $status }
}

function Get-PaperDevLatestBuild {
    param([string]$Minecraft, [string]$Project = 'paper')
    $b = Get-PaperDevJson ($PaperDevFillApi + '/' + $Project + '/versions/' + $Minecraft + '/builds/latest')
    $d = $b.downloads.'server:default'
    return [PSCustomObject]@{
        Minecraft = $Minecraft; Build = [int]$b.id; Channel = [string]$b.channel
        FileName = [string]$d.name; Url = [string]$d.url; Sha256 = [string]$d.checksums.sha256; Size = [long]$d.size
    }
}

function Get-PaperDevLatestMinecraft {
    # Newest version whose latest build is STABLE (pre-releases skipped unless asked).
    param([string]$Project = 'paper', [switch]$AllowUnstable)
    foreach ($v in (Get-PaperDevMinecraftVersions $Project)) {
        if (-not $AllowUnstable -and (Test-PaperDevPreRelease $v)) { continue }
        try { $build = Get-PaperDevLatestBuild -Minecraft $v -Project $Project } catch { continue }
        if ($AllowUnstable -or $build.Channel -eq 'STABLE') { return $v }
    }
    throw ('No stable version found for ' + $Project)
}

function ConvertTo-PaperDevVersion {
    # "1.7.10" / "26.3" / "1.21.11-rc1" -> [version] of the numeric part, for comparisons.
    param([string]$Minecraft)
    $parts = @(([regex]::Match([string]$Minecraft, '^\d+(\.\d+){0,3}').Value -split '\.') | Where-Object { $_ -ne '' })
    while ($parts.Count -lt 3) { $parts += '0' }
    return [version]($parts[0..2] -join '.')
}

function Test-PaperDevVersionAtLeast {
    param([string]$Minecraft, [string]$Than)
    return ((ConvertTo-PaperDevVersion $Minecraft) -ge (ConvertTo-PaperDevVersion $Than))
}

function Test-PaperDevModernVersion {
    # 26.1 and later use "<version>.build.<n>-<channel>" for paper-api; 1.x used "-R0.1-SNAPSHOT".
    param([string]$Minecraft)
    return (Test-PaperDevVersionAtLeast $Minecraft '26.0')
}

function Get-PaperDevEra {
    # What a Minecraft version offers to a plugin, and the Java it runs on. Paper supports 1.7.10 and later.
    #   Brigadier    commands through the lifecycle API (Paper 1.20.6+); before that plugin.yml "commands:" + CommandExecutor
    #   MiniMessage  in the server API (Paper 1.18.2+); before that legacy "&" color codes
    #   ApiVersion   plugin.yml "api-version" exists (1.13+); with a patch number only from 1.20.5
    #   PaperPlugin  paper-plugin.yml (only offered with Brigadier: a Paper plugin cannot use plugin.yml commands)
    #   FlatWorld    the test server uses a flat world (the generator settings format is the 1.19+ one)
    #   Java*        minimum (Fill API, raised to 8), preferred (the LTS to build and run with), maximum the server runs on
    param([string]$Minecraft, [int]$JavaMinimum = 0)
    $v = ConvertTo-PaperDevVersion $Minecraft
    $preferred = 8; $max = 8
    if ($v -ge [version]'26.0.0') { $preferred = 25; $max = 99 }
    elseif ($v -ge [version]'1.20.5') { $preferred = 21; $max = 25 }
    elseif ($v -ge [version]'1.18.0') { $preferred = 17; $max = 21 }
    elseif ($v -ge [version]'1.17.0') { $preferred = 17; $max = 17 }
    elseif ($v -ge [version]'1.13.0') { $preferred = 8; $max = 11 }
    $min = $JavaMinimum
    if ($min -lt 8) { $min = 8 }
    if ($preferred -lt $min) { $preferred = $min }
    if ($max -lt $preferred) { $max = $preferred }
    return [PSCustomObject]@{
        Minecraft = $Minecraft
        Brigadier = ($v -ge [version]'1.20.6')
        MiniMessage = ($v -ge [version]'1.18.2')
        ApiVersion = ($v -ge [version]'1.13.0')
        PaperPlugin = ($v -ge [version]'1.20.6')
        FlatWorld = ($v -ge [version]'1.19.0')
        JavaMin = $min; JavaPreferred = $preferred; JavaMax = $max
    }
}

function Format-PaperDevJavaRange {
    # "8", "8-11", "25+"
    param($Era)
    if ($Era.JavaMax -ge 99) { return ([string]$Era.JavaMin + '+') }
    if ($Era.JavaMax -eq $Era.JavaMin) { return [string]$Era.JavaMin }
    return ([string]$Era.JavaMin + '-' + $Era.JavaMax)
}

function Get-PaperDevApiDependency {
    # The API to compile against, as the Paper docs and repository name it for each era.
    # Spigot: org.spigotmc:spigot-api. CraftBukkit: org.bukkit:bukkit while it was published (up to 1.15.2),
    # later spigot-api (the Bukkit API plus Spigot's extras, which a CraftBukkit plugin must not use).
    param([string]$Minecraft, [string]$Platform = 'paper')
    $v = ConvertTo-PaperDevVersion $Minecraft
    if ($Platform -eq 'spigot' -or ($Platform -eq 'craftbukkit' -and $v -gt [version]'1.15.2')) {
        return [PSCustomObject]@{ Group = 'org.spigotmc'; Artifact = 'spigot-api'; Version = ($Minecraft + '-R0.1-SNAPSHOT'); Coordinate = ('org.spigotmc:spigot-api:' + $Minecraft + '-R0.1-SNAPSHOT'); Repository = $PaperDevMavenSpigot }
    }
    if ($Platform -eq 'craftbukkit') {
        return [PSCustomObject]@{ Group = 'org.bukkit'; Artifact = 'bukkit'; Version = ($Minecraft + '-R0.1-SNAPSHOT'); Coordinate = ('org.bukkit:bukkit:' + $Minecraft + '-R0.1-SNAPSHOT'); Repository = $PaperDevMavenSpigot }
    }
    if ($v -ge [version]'26.0.0') { $g = 'io.papermc.paper'; $a = 'paper-api'; $ver = $Minecraft + '.build.+' }
    elseif ($v -ge [version]'1.17.0') { $g = 'io.papermc.paper'; $a = 'paper-api'; $ver = $Minecraft + '-R0.1-SNAPSHOT' }
    elseif ($v -ge [version]'1.9.0') { $g = 'com.destroystokyo.paper'; $a = 'paper-api'; $ver = $Minecraft + '-R0.1-SNAPSHOT' }
    else { $g = 'org.github.paperspigot'; $a = 'paperspigot-api'; $ver = $Minecraft + '-R0.1-SNAPSHOT' }
    return [PSCustomObject]@{ Group = $g; Artifact = $a; Version = $ver; Coordinate = ($g + ':' + $a + ':' + $ver); Repository = $PaperDevMavenPaper }
}

# ---------------------------------------------------------------- Spigot / CraftBukkit (BuildTools)

function Get-PaperDevSpigotVersions {
    # Versions BuildTools can build (hub.spigotmc.org/versions/<version>.json), newest first. 1.8 and later.
    $index = Get-PaperDevTextFromWeb ($PaperDevSpigotVersions + '/')
    $names = @([regex]::Matches($index, 'href="(\d+(?:\.\d+)+)\.json"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    return @($names | Sort-Object { ConvertTo-PaperDevVersion $_ } -Descending)
}

function Get-PaperDevSpigotJava {
    # The Java range BuildTools requires for a version (javaVersions in <version>.json are class file versions,
    # major = n - 44). Versions without it build on Java 7-8; this skill uses 8.
    param([string]$Minecraft)
    $info = Get-PaperDevJson ($PaperDevSpigotVersions + '/' + $Minecraft + '.json')
    $min = 8; $max = 8
    if ($info.PSObject.Properties['javaVersions'] -and @($info.javaVersions).Count -eq 2) {
        $min = [int]@($info.javaVersions)[0] - 44
        $max = [int]@($info.javaVersions)[1] - 44
        if ($min -lt 8) { $min = 8 }
    }
    $preferred = $min
    foreach ($lts in @(8, 11, 17, 21, 25)) { if ($lts -ge $min -and $lts -le $max) { $preferred = $lts; break } }
    return [PSCustomObject]@{ JavaMin = $min; JavaMax = $max; JavaPreferred = $preferred }
}

function Get-PaperDevSpigotServerJar {
    # A Spigot / CraftBukkit server jar built earlier by BuildTools (Invoke-PaperDevBuildTools), or $null.
    param([string]$Minecraft, [ValidateSet('spigot', 'craftbukkit')][string]$Flavor)
    $path = Join-Path (Get-PaperDevHomeDir 'cache') ('spigot/' + $Flavor + '-' + $Minecraft + '.jar')
    if (Test-Path -LiteralPath $path) { return $path }
    return $null
}

function Invoke-PaperDevBuildTools {
    # Builds a Spigot or CraftBukkit server jar with SpigotMC's BuildTools (the only way to get one: SpigotMC does
    # not distribute server jars). Downloads BuildTools.jar, then BuildTools downloads the Minecraft server, Git
    # repositories and Maven, and compiles (several minutes, about 1 GB in <home>/bt/). Run only after the user
    # agreed. Returns the jar path; throws on failure (the end of the BuildTools log is in the message).
    param([string]$Minecraft, [ValidateSet('spigot', 'craftbukkit')][string]$Flavor, [string]$Java)
    $toolsDir = Get-PaperDevHomeDir 'cache/buildtools'
    # A short work folder: Spigot's sources are nested deeply, and Windows paths are limited to 260 characters.
    $work = Get-PaperDevHomeDir 'bt'
    $jar = Join-Path $toolsDir 'BuildTools.jar'
    Write-Host ('downloading BuildTools.jar from hub.spigotmc.org')
    Save-PaperDevDownload -Uri $PaperDevBuildToolsUrl -OutFile $jar
    $outDir = Join-Path (Get-PaperDevHomeDir 'cache') 'spigot'
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    Write-Host ('building ' + $Flavor + ' ' + $Minecraft + ' with BuildTools (several minutes; log: ' + (Join-Path $work 'BuildTools.log.txt') + ')')
    $javaHome = Split-Path -Parent (Split-Path -Parent $Java)
    $envs = @{ 'JAVA_HOME' = $javaHome }
    if (Test-PaperDevWindows) {
        # BuildTools checks for "sh" first and otherwise downloads and unpacks PortableGit (which can fail).
        # Git for Windows puts only its cmd\ folder on PATH; sh.exe is in bin\ and usr\bin\.
        $git = Get-Command git -ErrorAction SilentlyContinue | Select-Object -First 1
        $gitRoot = $null
        if ($git) { $gitRoot = Split-Path -Parent (Split-Path -Parent $git.Source) }
        if (-not $gitRoot -or -not (Test-Path -LiteralPath (Join-Path $gitRoot 'bin\sh.exe'))) {
            throw 'BuildTools needs Git for Windows (its sh.exe): install it (winget install --id Git.Git -e), then try again'
        }
        $envs['PATH'] = (Join-Path $gitRoot 'bin') + ';' + (Join-Path $gitRoot 'usr\bin') + ';' + $env:PATH
        # core.longpaths for these git runs only (environment config, Git 2.31+): the user's git config is not changed.
        $envs['GIT_CONFIG_COUNT'] = '1'
        $envs['GIT_CONFIG_KEY_0'] = 'core.longpaths'
        $envs['GIT_CONFIG_VALUE_0'] = 'true'
    }
    $r = Invoke-PaperDevDetachedProcess -FilePath $Java -Arguments @('-jar', $jar, '--nogui', '--rev', $Minecraft, '--compile', $Flavor, '--output-dir', $outDir) -WorkingDirectory $work -Environment $envs
    $built = Join-Path $outDir ($Flavor + '-' + $Minecraft + '.jar')
    if ($r.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $built)) {
        $tail = (($r.StdOut -split "`r?`n") | Where-Object { $_ } | Select-Object -Last 25) -join "`n"
        throw ('BuildTools failed (exit ' + $r.ExitCode + '):' + "`n" + $tail)
    }
    return $built
}

function Get-PaperDevApiCoordinate {
    # The version part only (kept for callers that print it).
    param([string]$Minecraft)
    return (Get-PaperDevApiDependency $Minecraft).Version
}

function Get-PaperDevApiVersionField {
    # The api-version value for plugin.yml / paper-plugin.yml; $null before 1.13 (the key did not exist).
    # Servers before 1.20.5 accept only "1.<minor>".
    param([string]$Minecraft)
    if (-not (Test-PaperDevVersionAtLeast $Minecraft '1.13')) { return $null }
    if (Test-PaperDevModernVersion $Minecraft) { return $Minecraft }
    if (Test-PaperDevVersionAtLeast $Minecraft '1.20.5') { return $Minecraft }
    if ($Minecraft -match '^1\.(\d+)') { return ('1.' + $Matches[1]) }
    return $Minecraft
}

function Get-PaperDevLatestApiBuild {
    # Newest concrete API version for a Minecraft version (e.g. 26.3.build.229-stable, 1.8.8-R0.1-SNAPSHOT).
    # $null when the repository does not have it.
    param([string]$Minecraft, [string]$Platform = 'paper')
    $dep = Get-PaperDevApiDependency -Minecraft $Minecraft -Platform $Platform
    if ($dep.Repository -ne $PaperDevMavenPaper) {
        $url = $dep.Repository + '/' + ($dep.Group -replace '\.', '/') + '/' + $dep.Artifact + '/' + $dep.Version + '/maven-metadata.xml'
        try { Invoke-PaperDevWeb $url | Out-Null; return $dep.Version } catch { return $null }
    }
    if (Test-PaperDevModernVersion $Minecraft) {
        $versions = Get-PaperDevMavenVersions -Repository $PaperDevMavenPaper -Group $dep.Group -Artifact $dep.Artifact
        $prefix = $Minecraft + '.build.'
        $best = $null; $bestN = -1
        foreach ($ver in $versions) {
            if ($ver.StartsWith($prefix) -and $ver -match '\.build\.(\d+)-') {
                $n = [int]$Matches[1]
                if ($n -gt $bestN) { $bestN = $n; $best = $ver }
            }
        }
        return $best
    }
    # Snapshot versions are not always listed in the artifact's metadata; ask for the version folder itself.
    $url = $PaperDevMavenPaper + '/' + ($dep.Group -replace '\.', '/') + '/' + $dep.Artifact + '/' + $dep.Version + '/maven-metadata.xml'
    try { Invoke-PaperDevWeb $url | Out-Null; return $dep.Version } catch { return $null }
}

function Get-PaperDevMockBukkit {
    # The MockBukkit artifact for a Minecraft version: exact (v26.3), then major.minor (v1.21). $null if none.
    param([string]$Minecraft)
    $index = Get-PaperDevTextFromWeb ($PaperDevMavenCentral + '/org/mockbukkit/mockbukkit/')
    $names = @([regex]::Matches($index, 'mockbukkit-v[0-9.]+(?=/)') | ForEach-Object { $_.Value } | Sort-Object -Unique)
    $candidates = @('mockbukkit-v' + $Minecraft)
    if ($Minecraft -match '^(\d+\.\d+)') { $candidates += ('mockbukkit-v' + $Matches[1]) }
    foreach ($c in $candidates) {
        if ($names -contains $c) {
            $ver = Get-PaperDevMavenRelease -Repository $PaperDevMavenCentral -Group 'org.mockbukkit.mockbukkit' -Artifact $c
            return [PSCustomObject]@{ Artifact = $c; Version = $ver }
        }
    }
    return $null
}

function Get-PaperDevGradleCurrent {
    $g = Get-PaperDevJson 'https://services.gradle.org/versions/current'
    return [PSCustomObject]@{ Version = [string]$g.version; Url = [string]$g.downloadUrl; ChecksumUrl = [string]$g.checksumUrl }
}

function Get-PaperDevGradleDistribution {
    # A Gradle distribution in the home folder (downloaded once, SHA-256 checked). Returns the gradle launcher.
    param([string]$Version)
    $cache = Get-PaperDevHomeDir 'cache'
    if (-not $Version) { $Version = (Get-PaperDevGradleCurrent).Version }
    $dir = Join-Path $cache ('gradle/gradle-' + $Version)
    $launcher = Join-Path $dir 'bin/gradle'
    if (Test-PaperDevWindows) { $launcher += '.bat' }
    if (Test-Path -LiteralPath $launcher) { return $launcher }
    $url = 'https://services.gradle.org/distributions/gradle-' + $Version + '-bin.zip'
    $sha = (Get-PaperDevTextFromWeb ($url + '.sha256')).Trim()
    $zip = Join-Path $cache ('gradle/gradle-' + $Version + '-bin.zip')
    Write-Host ('downloading Gradle ' + $Version + ' (once, into ' + $cache + ')')
    Save-PaperDevDownload -Uri $url -OutFile $zip -Sha256 $sha
    Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $cache 'gradle') -Force
    Remove-Item -LiteralPath $zip -Force
    if (-not (Test-PaperDevWindows)) { Invoke-PaperDevProcess -FilePath 'chmod' -Arguments @('+x', $launcher) | Out-Null }
    return $launcher
}

function Get-PaperDevServerJar {
    # The server jar of the latest build of a version, cached in the home folder and checked by SHA-256.
    param([string]$Minecraft, [string]$Project = 'paper')
    $build = Get-PaperDevLatestBuild -Minecraft $Minecraft -Project $Project
    $dir = Join-Path (Get-PaperDevHomeDir 'cache') $Project
    $path = Join-Path $dir $build.FileName
    if (-not (Test-Path -LiteralPath $path) -or (Get-PaperDevFileSha256 $path) -ne $build.Sha256) {
        Write-Host ('downloading ' + $build.FileName + ' (' + [Math]::Round($build.Size / 1MB, 1) + ' MB, ' + $build.Channel + ')')
        Save-PaperDevDownload -Uri $build.Url -OutFile $path -Sha256 $build.Sha256
    }
    return [PSCustomObject]@{ Path = $path; Build = $build }
}

# ---------------------------------------------------------------- Java

function Get-PaperDevJava {
    # Finds java: -JavaPath, PAPERMCDEV_JAVA, local.json javaPath, JAVA_HOME, PATH. Returns $null when none.
    param([string]$JavaPath)
    $exe = 'java'
    if (Test-PaperDevWindows) { $exe = 'java.exe' }
    $candidates = @()
    if ($JavaPath) { $candidates += $JavaPath }
    if ($env:PAPERMCDEV_JAVA) { $candidates += $env:PAPERMCDEV_JAVA }
    $cfg = Get-PaperDevLocalConfig
    if ($cfg.PSObject.Properties['javaPath'] -and $cfg.javaPath) { $candidates += [string]$cfg.javaPath }
    if ($env:JAVA_HOME) { $candidates += (Join-Path (Join-Path $env:JAVA_HOME 'bin') $exe) }
    $cmd = Get-Command $exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { $candidates += $cmd.Source }
    foreach ($c in $candidates) {
        if (-not $c) { continue }
        if (Test-Path -LiteralPath $c -PathType Container) { $c = Join-Path (Join-Path $c 'bin') $exe }
        if (-not (Test-Path -LiteralPath $c)) { continue }
        $r = Invoke-PaperDevProcess -FilePath $c -Arguments @('-version')
        $text = $r.StdErr + $r.StdOut
        if ($text -match 'version "([^"]+)"') {
            $full = $Matches[1]
            $major = 0
            if ($full -match '^1\.(\d+)') { $major = [int]$Matches[1] }
            elseif ($full -match '^(\d+)') { $major = [int]$Matches[1] }
            $vendor = ''
            $lines = @($text -split "`r?`n" | Where-Object { $_ })
            if ($lines.Count -ge 2) { $vendor = $lines[1].Trim() }
            return [PSCustomObject]@{ Path = (Resolve-Path -LiteralPath $c).Path; Version = $full; Major = $major; Vendor = $vendor }
        }
    }
    return $null
}

function Get-PaperDevJdkMajor {
    # The major version of a JDK folder from its "release" file ($null when it is not a JDK).
    param([string]$JdkHome)
    $release = Join-Path $JdkHome 'release'
    if (-not (Test-Path -LiteralPath $release)) { return $null }
    $text = Read-PaperDevText $release
    if ($text -notmatch 'JAVA_VERSION="([^"]+)"') { return $null }
    $full = $Matches[1]
    if ($full -match '^1\.(\d+)') { return [int]$Matches[1] }
    if ($full -match '^(\d+)') { return [int]$Matches[1] }
    return $null
}

function Find-PaperDevJdks {
    # Installed JDKs: local.json "jdks" ({"8": "C:\\path"}), the home folder's jdk/, JAVA_HOME, the java on PATH,
    # and the usual install folders (vendors' folders, Gradle toolchains in ~/.gradle/jdks, IntelliJ's ~/.jdks,
    # /usr/lib/jvm, macOS JavaVirtualMachines, SDKMAN). Returns objects with Major, Home, Java.
    $exe = 'java'
    if (Test-PaperDevWindows) { $exe = 'java.exe' }
    $homes = New-Object System.Collections.ArrayList
    $cfg = Get-PaperDevLocalConfig
    if ($cfg.PSObject.Properties['jdks'] -and $cfg.jdks) { foreach ($p in $cfg.jdks.PSObject.Properties) { [void]$homes.Add([string]$p.Value) } }
    $roots = @((Join-Path (Get-PaperDevHome) 'jdk'))
    $userHome = $env:USERPROFILE
    if (-not $userHome) { $userHome = $HOME }
    $roots += @((Join-Path $userHome '.gradle/jdks'), (Join-Path $userHome '.jdks'), (Join-Path $userHome '.sdkman/candidates/java'))
    if (Test-PaperDevWindows) {
        foreach ($pf in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
            if (-not $pf) { continue }
            foreach ($vendor in @('Eclipse Adoptium', 'Java', 'Zulu', 'Microsoft', 'Amazon Corretto', 'BellSoft', 'Semeru', 'OpenJDK', 'Eclipse Foundation', 'AdoptOpenJDK')) { $roots += (Join-Path $pf $vendor) }
        }
    } else {
        $roots += @('/usr/lib/jvm', '/usr/java', '/opt/java', '/Library/Java/JavaVirtualMachines')
    }
    foreach ($r in $roots) {
        if (-not $r -or -not (Test-Path -LiteralPath $r)) { continue }
        foreach ($d in (Get-ChildItem -LiteralPath $r -Directory -ErrorAction SilentlyContinue)) {
            [void]$homes.Add($d.FullName)
            [void]$homes.Add((Join-Path $d.FullName 'Contents/Home'))
            foreach ($d2 in (Get-ChildItem -LiteralPath $d.FullName -Directory -ErrorAction SilentlyContinue)) { [void]$homes.Add($d2.FullName) }
        }
    }
    if ($env:JAVA_HOME) { [void]$homes.Add($env:JAVA_HOME) }
    $cmd = Get-Command $exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) {
        $real = $cmd.Source
        try { $item = Get-Item -LiteralPath $real; if ($item.Target) { $real = [string]@($item.Target)[0] } } catch { }
        [void]$homes.Add((Split-Path -Parent (Split-Path -Parent $real)))
    }
    $seen = @{}
    $result = @()
    foreach ($h in $homes) {
        if (-not $h -or -not (Test-Path -LiteralPath (Join-Path (Join-Path $h 'bin') $exe))) { continue }
        $full = (Resolve-Path -LiteralPath $h).Path.TrimEnd('\', '/')
        if ($seen.ContainsKey($full)) { continue }
        $seen[$full] = $true
        $major = Get-PaperDevJdkMajor $full
        if (-not $major) { continue }
        $result += [PSCustomObject]@{ Major = $major; Home = $full; Java = (Join-Path (Join-Path $full 'bin') $exe) }
    }
    return $result
}

function Get-PaperDevServerJava {
    # The java to run a server of $Minecraft: -JavaPath when given, else an installed JDK of the preferred
    # version, else any version the server runs on. $null when none is installed (scripts/setup.ps1 -Jdk <n>).
    param([string]$Minecraft, [int]$JavaMinimum, [string]$JavaPath)
    if ($JavaPath) { return (Get-PaperDevJava $JavaPath) }
    $era = Get-PaperDevEra -Minecraft $Minecraft -JavaMinimum $JavaMinimum
    $jdks = @(Find-PaperDevJdks)
    $pick = $jdks | Where-Object { $_.Major -eq $era.JavaPreferred } | Select-Object -First 1
    if (-not $pick) { $pick = $jdks | Where-Object { $_.Major -ge $era.JavaMin -and $_.Major -le $era.JavaMax } | Sort-Object Major | Select-Object -First 1 }
    if (-not $pick) { return $null }
    return (Get-PaperDevJava $pick.Java)
}

function Install-PaperDevJdk {
    # Downloads Eclipse Temurin <major> (JDK) from the Adoptium API into <home>/jdk/temurin-<major>, SHA-256 checked.
    param([int]$Major)
    $os = 'linux'
    if (Test-PaperDevWindows) { $os = 'windows' } elseif ((Invoke-PaperDevProcess -FilePath 'uname' -Arguments @('-s')).StdOut -match 'Darwin') { $os = 'mac' }
    $arch = 'x64'
    $machine = [string]$env:PROCESSOR_ARCHITECTURE
    if (-not (Test-PaperDevWindows)) { $machine = (Invoke-PaperDevProcess -FilePath 'uname' -Arguments @('-m')).StdOut.Trim() }
    if ($machine -match '(?i)arm64|aarch64') { $arch = 'aarch64' }
    $assets = Get-PaperDevJson ('https://api.adoptium.net/v3/assets/latest/' + $Major + '/hotspot?architecture=' + $arch + '&image_type=jdk&os=' + $os + '&vendor=eclipse')
    $asset = @($assets)[0]
    if (-not $asset) { throw ('Temurin ' + $Major + ' is not available for ' + $os + '/' + $arch) }
    $pkg = $asset.binary.package
    $target = Join-Path (Get-PaperDevHomeDir 'jdk') ('temurin-' + $Major)
    $archive = Join-Path (Get-PaperDevHomeDir 'cache') ([string]$pkg.name)
    Write-Host ('downloading ' + $pkg.name + ' (' + [Math]::Round([long]$pkg.size / 1MB, 1) + ' MB) from adoptium.net')
    Save-PaperDevDownload -Uri ([string]$pkg.link) -OutFile $archive -Sha256 ([string]$pkg.checksum)
    $tmp = $target + '.part'
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    if ($archive.EndsWith('.zip')) { Expand-Archive -LiteralPath $archive -DestinationPath $tmp -Force }
    else { $r = Invoke-PaperDevProcess -FilePath 'tar' -Arguments @('-xzf', $archive, '-C', $tmp); if ($r.ExitCode -ne 0) { throw ('tar failed: ' + $r.StdErr) } }
    Remove-Item -LiteralPath $archive -Force
    $inner = Get-ChildItem -LiteralPath $tmp -Directory | Select-Object -First 1
    if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
    Move-Item -LiteralPath $inner.FullName -Destination $target
    Remove-Item -LiteralPath $tmp -Recurse -Force
    if (Test-Path -LiteralPath (Join-Path $target 'Contents/Home')) { return (Join-Path $target 'Contents/Home') }
    return $target
}

# ---------------------------------------------------------------- project

function Find-PaperDevDescriptor {
    param([string]$Dir)
    foreach ($name in @('paper-plugin.yml', 'plugin.yml')) {
        $p = Join-Path $Dir (Join-Path 'src/main/resources' $name)
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

function Test-PaperDevBuildRoot {
    param([string]$Dir)
    foreach ($f in @('settings.gradle.kts', 'settings.gradle', 'build.gradle.kts', 'build.gradle', 'pom.xml')) {
        if (Test-Path -LiteralPath (Join-Path $Dir $f)) { return $true }
    }
    return $false
}

function Resolve-PaperDevProject {
    # Finds the plugin project: -ProjectRoot, PAPERMCDEV_PROJECT_ROOT, then the working folder and its parents.
    # Returns $null when no project is found (the caller decides whether that is an error).
    param([string]$ProjectRoot)
    $start = $ProjectRoot
    if (-not $start) { $start = $env:PAPERMCDEV_PROJECT_ROOT }
    if (-not $start) { $start = (Get-Location).Path }
    if (-not (Test-Path -LiteralPath $start)) { return $null }
    $dir = (Resolve-Path -LiteralPath $start).Path
    $found = $null
    while ($dir) {
        if (Test-PaperDevBuildRoot $dir) { $found = $dir }
        $parent = Split-Path -Parent $dir
        if (-not $parent -or $parent -eq $dir) { break }
        # Stop at the outermost build root that is still inside a git work tree or the start folder.
        if ($found -and -not (Test-PaperDevBuildRoot $parent)) { break }
        $dir = $parent
    }
    if (-not $found) { return $null }
    $descriptor = Find-PaperDevDescriptor $found
    $module = $found
    if (-not $descriptor) {
        foreach ($sub in (Get-ChildItem -LiteralPath $found -Directory -ErrorAction SilentlyContinue)) {
            if ($sub.Name -match '^(\.|build$|run$|out$|target$|gradle$)') { continue }
            $d = Find-PaperDevDescriptor $sub.FullName
            if ($d) { $descriptor = $d; $module = $sub.FullName; break }
        }
    }
    $tool = 'gradle'
    if (-not (Test-Path -LiteralPath (Join-Path $found 'settings.gradle.kts')) -and -not (Test-Path -LiteralPath (Join-Path $found 'settings.gradle')) -and
        -not (Test-Path -LiteralPath (Join-Path $found 'build.gradle.kts')) -and -not (Test-Path -LiteralPath (Join-Path $found 'build.gradle')) -and
        (Test-Path -LiteralPath (Join-Path $found 'pom.xml'))) { $tool = 'maven' }
    $kind = $null
    if ($descriptor) { if ((Split-Path -Leaf $descriptor) -eq 'paper-plugin.yml') { $kind = 'paper' } else { $kind = 'bukkit' } }
    else {
        # A Velocity plugin has no yml: velocity-plugin.json is generated from the @Plugin annotation.
        foreach ($dir in @($found) + @(Get-ChildItem -LiteralPath $found -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '^(\.|build$|run$|out$|target$|gradle$)' } | ForEach-Object { $_.FullName })) {
            foreach ($n in @('build.gradle.kts', 'build.gradle', 'pom.xml', 'gradle/libs.versions.toml')) {
                $p = Join-Path $dir $n
                if ((Test-Path -LiteralPath $p) -and (Read-PaperDevText $p) -match 'velocity-api') { $kind = 'velocity'; $module = $dir; break }
            }
            if ($kind) { break }
        }
    }
    return [PSCustomObject]@{
        Root = $found; Module = $module; BuildTool = $tool; Descriptor = $descriptor; Kind = $kind
        Id = ((Split-Path -Leaf $found) + '-' + (Get-PaperDevShortHash $found))
    }
}

function Get-PaperDevBuildFiles {
    param($Project)
    $files = @()
    foreach ($dir in @($Project.Root, $Project.Module) | Select-Object -Unique) {
        foreach ($n in @('build.gradle.kts', 'build.gradle', 'gradle.properties', 'pom.xml', 'gradle/libs.versions.toml')) {
            $p = Join-Path $dir $n
            if (Test-Path -LiteralPath $p) { $files += $p }
        }
    }
    return $files
}

function Get-PaperDevProjectVersions {
    # What the project targets, read from its build files. Fields are $null when not found.
    param($Project)
    $result = [PSCustomObject]@{ PaperApi = $null; Minecraft = $null; Java = $null; RunPaper = $null; MockBukkit = $null; Platform = 'paper'; Velocity = $null; FoliaSupported = $false }
    if ($Project.Descriptor) {
        $d = Read-PaperDevDescriptor $Project.Descriptor
        $result.FoliaSupported = ($d.Values['folia-supported'] -eq 'true')
    }
    foreach ($f in (Get-PaperDevBuildFiles $Project)) {
        $text = Read-PaperDevText $f
        if (-not $result.Velocity -and $text -match '(?:com\.velocitypowered:velocity-api:|<artifactId>velocity-api</artifactId>\s*<version>)([0-9][^"''<\s)]*)') { $result.Velocity = $Matches[1]; $result.Platform = 'velocity' }
        if (-not $result.RunPaper -and $text -match 'velocityVersion\(\s*"([^"]+)"\s*\)') { $result.RunPaper = $Matches[1] }
        # paper-api (io.papermc.paper from 1.17, com.destroystokyo.paper 1.9-1.16), paperspigot-api (1.7.10, 1.8.8),
        # and spigot-api / bukkit for Spigot projects, which also run on Paper.
        if (-not $result.PaperApi -and $text -match '(?:(?:io\.papermc\.paper|com\.destroystokyo\.paper):paper-api:|org\.github\.paperspigot:paperspigot-api:|org\.spigotmc:spigot-api:|org\.bukkit:bukkit:|(?:paper|paperspigot|spigot)-api["'']?\s*[,:]\s*version\s*=\s*["'']|<artifactId>(?:paper|paperspigot|spigot)-api</artifactId>\s*<version>)([0-9][^"''<\s]*)') { $result.PaperApi = $Matches[1] }
        if (-not $result.PaperApi -and $text -match 'dev\.folia:folia-api:([0-9][^"''\s]*)') { $result.PaperApi = $Matches[1]; $result.Platform = 'folia' }
        if (-not $result.Java -and $text -match 'JavaLanguageVersion\.of\(\s*(\d+)\s*\)') { $result.Java = [int]$Matches[1] }
        if (-not $result.Java -and $text -match '<maven\.compiler\.release>(\d+)<') { $result.Java = [int]$Matches[1] }
        if (-not $result.RunPaper -and $text -match 'minecraftVersion\(\s*"([^"]+)"\s*\)') { $result.RunPaper = $Matches[1] }
        if (-not $result.MockBukkit -and $text -match 'org\.mockbukkit\.mockbukkit:(mockbukkit-v[0-9.]+):([^"''\s]+)') { $result.MockBukkit = $Matches[1] + ':' + $Matches[2] }
    }
    if ($result.Platform -eq 'velocity') { $result.RunPaper = $null; return $result }
    # Spigot / CraftBukkit projects compile against spigot-api / bukkit instead of paper-api. A CraftBukkit project
    # after 1.15.2 also uses spigot-api; new-plugin.ps1 marks it with "papermc-developer: platform=craftbukkit".
    $all = (Get-PaperDevBuildFiles $Project | ForEach-Object { Read-PaperDevText $_ }) -join "`n"
    if ($result.Platform -eq 'paper' -and $all -notmatch '(io\.papermc\.paper|com\.destroystokyo\.paper|org\.github\.paperspigot)[:"''<]|<artifactId>(paper|paperspigot)-api<') {
        if ($all -match 'papermc-developer: platform=craftbukkit' -or $all -match 'org\.bukkit:bukkit:|<artifactId>bukkit</artifactId>') { $result.Platform = 'craftbukkit' }
        elseif ($all -match 'org\.spigotmc:spigot-api:|<artifactId>spigot-api</artifactId>') { $result.Platform = 'spigot' }
    }
    if ($result.PaperApi -and $result.PaperApi -match '^(\d+\.\d+(?:\.\d+)?)(?:\.build|-R0\.1)') { $result.Minecraft = $Matches[1] }
    elseif ($result.RunPaper) { $result.Minecraft = $result.RunPaper }
    return $result
}

function Get-PaperDevVelocityPlugin {
    # The @Plugin annotation of a Velocity plugin: Id, Name, Version (as written), Main class, File, Line. $null if none.
    param($Project)
    foreach ($r in @('src/main/java', 'src/main/kotlin')) {
        $root = Join-Path $Project.Module $r
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($src in (Get-ChildItem -LiteralPath $root -Recurse -File -Include '*.java', '*.kt')) {
            $text = Read-PaperDevText $src.FullName
            $m = [regex]::Match($text, '@Plugin\s*\((?<body>(?:[^()]|\((?:[^()]|\([^()]*\))*\))*)\)\s*(?:@\w+(?:\([^)]*\))?\s*)*(?:public\s+|final\s+|open\s+)*class\s+(?<class>\w+)')
            if (-not $m.Success) { continue }
            $body = $m.Groups['body'].Value
            $id = $null; $name = $null; $version = $null
            if ($body -match 'id\s*=\s*"([^"]*)"') { $id = $Matches[1] }
            if ($body -match '\bname\s*=\s*"([^"]*)"') { $name = $Matches[1] }
            if ($body -match '\bversion\s*=\s*([^,\r\n]+)') { $version = $Matches[1].Trim() }
            $package = ''
            if ($text -match '(?m)^\s*package\s+([\w.]+)') { $package = $Matches[1] + '.' }
            $line = 1 + ([regex]::Matches($text.Substring(0, $m.Index), "`n")).Count
            return [PSCustomObject]@{ Id = $id; Name = $name; Version = $version; Main = ($package + $m.Groups['class'].Value); File = $src.FullName; Line = $line }
        }
    }
    return $null
}

function Get-PaperDevLatestVelocity {
    # Newest Velocity release whose latest build is stable (snapshots skipped).
    foreach ($v in (Get-PaperDevMinecraftVersions 'velocity')) {
        if ($v -match '(?i)snapshot') { continue }
        try { $b = Get-PaperDevLatestBuild -Minecraft $v -Project 'velocity' } catch { continue }
        if ($b.Channel -eq 'STABLE' -or $b.Channel -eq 'RECOMMENDED') { return $v }
    }
    throw 'No stable Velocity version found'
}

function Read-PaperDevDescriptor {
    # A small reader for the parts of plugin.yml / paper-plugin.yml the scripts need:
    # top-level scalars, and the key names under "commands:" and "permissions:".
    param([string]$Path)
    $values = @{}
    $sections = @{ commands = @(); permissions = @() }
    $current = $null
    $childIndent = -1
    $lineNo = 0
    $lines = @{}
    foreach ($raw in ((Read-PaperDevText $Path) -split "`r?`n")) {
        $lineNo++
        if ($raw -match '^\s*(#.*)?$') { continue }
        if ($raw -match '^([A-Za-z0-9_-]+)\s*:\s*(.*)$') {
            $key = $Matches[1]; $value = $Matches[2].Trim()
            $lines[$key] = $lineNo
            $current = $null; $childIndent = -1
            if ($value -match '^#') { $value = '' }
            if ($value -eq '' -and $sections.ContainsKey($key)) { $current = $key; continue }
            $value = $value -replace '\s+#.*$', ''
            if ($value -match '^"(.*)"$' -or $value -match "^'(.*)'$") { $value = $Matches[1] }
            $values[$key] = $value
            continue
        }
        if ($current -and $raw -match '^(\s+)(["'']?)([^"'':\s][^"'':]*)\2\s*:') {
            $indent = $Matches[1].Length
            if ($childIndent -lt 0) { $childIndent = $indent }
            if ($indent -eq $childIndent) { $sections[$current] += $Matches[3].Trim() }
        }
    }
    return [PSCustomObject]@{ Values = $values; Commands = $sections.commands; Permissions = $sections.permissions; Lines = $lines; Path = $Path }
}

function Get-PaperDevPluginName {
    param($Project)
    if ($Project.Descriptor) {
        $d = Read-PaperDevDescriptor $Project.Descriptor
        if ($d.Values['name']) { return $d.Values['name'] }
    }
    if ($Project.Kind -eq 'velocity') {
        # Velocity logs a plugin under its id (the logger name), e.g. "[sleep-vote]".
        $v = Get-PaperDevVelocityPlugin $Project
        if ($v -and $v.Id) { return $v.Id }
    }
    return (Split-Path -Leaf $Project.Root)
}

# ---------------------------------------------------------------- build

function Get-PaperDevGradleCommand {
    # gradlew in the project, then gradle on PATH. $null when neither exists.
    param($Project)
    if (Test-PaperDevWindows) {
        $w = Join-Path $Project.Root 'gradlew.bat'
        if (Test-Path -LiteralPath $w) { return $w }
        $g = Get-Command 'gradle.bat' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($g) { return $g.Source }
    } else {
        $w = Join-Path $Project.Root 'gradlew'
        if (Test-Path -LiteralPath $w) { return $w }
    }
    $g = Get-Command 'gradle' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($g) { return $g.Source }
    return $null
}

function Get-PaperDevMavenCommand {
    param($Project)
    if (Test-PaperDevWindows) {
        $w = Join-Path $Project.Root 'mvnw.cmd'
        if (Test-Path -LiteralPath $w) { return $w }
    } else {
        $w = Join-Path $Project.Root 'mvnw'
        if (Test-Path -LiteralPath $w) { return $w }
    }
    $g = Get-Command 'mvn' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($g) { return $g.Source }
    return $null
}

function Invoke-PaperDevBuild {
    # Runs the build tool. $Tasks are Gradle task names; for Maven they are mapped to phases.
    param($Project, [string[]]$Tasks, [string[]]$Extra, [string]$JavaHome)
    $envs = @{}
    if ($JavaHome) { $envs['JAVA_HOME'] = $JavaHome }
    if ($Project.BuildTool -eq 'maven') {
        $cmd = Get-PaperDevMavenCommand $Project
        if (-not $cmd) { return $null }
        $phases = @()
        foreach ($t in $Tasks) {
            switch ($t) { 'build' { $phases += 'package' } 'assemble' { $phases += 'package'; $phases += '-DskipTests' } 'test' { $phases += 'test' } 'clean' { $phases += 'clean' } default { $phases += $t } }
        }
        return (Invoke-PaperDevDetachedProcess -FilePath $cmd -Arguments (@('-B', '-ntp') + $phases + $Extra) -WorkingDirectory $Project.Root -Environment $envs)
    }
    $cmd = Get-PaperDevGradleCommand $Project
    if (-not $cmd) { return $null }
    if (-not (Test-PaperDevWindows) -and $cmd.EndsWith('gradlew')) {
        return (Invoke-PaperDevDetachedProcess -FilePath 'sh' -Arguments (@($cmd, '--console=plain') + $Tasks + $Extra) -WorkingDirectory $Project.Root -Environment $envs)
    }
    return (Invoke-PaperDevDetachedProcess -FilePath $cmd -Arguments (@('--console=plain') + $Tasks + $Extra) -WorkingDirectory $Project.Root -Environment $envs)
}

function Get-PaperDevCompilerMessages {
    # javac / kotlinc / maven compiler messages from build output.
    param([string]$Output)
    # javac writes the level in the language of the JDK ("error" in English, other words elsewhere), so the level word is
    # matched loosely; Gradle repeats the messages indented under "What went wrong", hence the de-duplication.
    # error, Japanese, Simplified and Traditional Chinese, Korean, German, French, Italian, Portuguese, Russian, Dutch, Polish
    $errorWords = '(?i)^(e|error|fatal|\u30A8\u30E9\u30FC|\u9519\u8BEF|\u932F\u8AA4|\uC624\uB958|fehler|erreur|errore|erro|\u043E\u0448\u0438\u0431\u043A\u0430|fout|b\u0142\u0105d)$'
    $messages = @()
    $seen = @{}
    $lines = @($Output -split "`r?`n")
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $l = $lines[$i]
        $indent = 0
        if ($l -match '^(\s*)') { $indent = $Matches[1].Length }
        $t = $l.Trim()
        $m = $null
        if ($t -match '^(?<file>(?:[A-Za-z]:)?[^:]+\.(?:java|kt|kts)):(?<line>\d+): (?<level>[^:\s]{1,20}): (?<msg>.*)$') { $m = $Matches }
        elseif ($t -match '^(?<level>[ew]): (?:file://)?(?<file>/?(?:[A-Za-z]:)?[^:]+\.(?:kt|kts|java)):(?<line>\d+):\d+ (?<msg>.*)$') { $m = $Matches }
        elseif ($t -match '^\[(?<level>ERROR|WARNING)\] (?<file>(?:[A-Za-z]:)?[^:\[]+\.(?:java|kt)):\[(?<line>\d+),\d+\] (?<msg>.*)$') { $m = $Matches }
        if (-not $m) { continue }
        $level = 'warning'
        if ($m['level'] -match $errorWords) { $level = 'error' }
        $key = $m['file'].Trim() + '|' + $m['line'] + '|' + $m['msg'].Trim()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $context = @()
        $j = $i + 1
        while ($j -lt $lines.Count -and $j -le $i + 4) {
            $n = $lines[$j]
            $nIndent = 0
            if ($n -match '^(\s*)') { $nIndent = $Matches[1].Length }
            if ($n.Trim() -eq '' -or $nIndent -le $indent -or $n.Trim() -match '\.(java|kt|kts):\d+:') { break }
            $context += $n.Substring([Math]::Min($indent, $n.Length))
            $j++
        }
        $messages += [PSCustomObject]@{ Level = $level; File = $m['file'].Trim(); Line = [int]$m['line']; Message = $m['msg'].Trim(); Context = $context }
    }
    return $messages
}

function Get-PaperDevTestResults {
    # Parses JUnit XML reports (Gradle: build/test-results, Maven: target/surefire-reports).
    param($Project)
    $dirs = @()
    foreach ($base in @($Project.Root, $Project.Module) | Select-Object -Unique) {
        foreach ($d in @('build/test-results', 'target/surefire-reports')) {
            $p = Join-Path $base $d
            if (Test-Path -LiteralPath $p) { $dirs += $p }
        }
    }
    $total = 0; $failures = @(); $skipped = 0
    foreach ($d in $dirs) {
        foreach ($f in (Get-ChildItem -LiteralPath $d -Recurse -Filter 'TEST-*.xml' -ErrorAction SilentlyContinue)) {
            try { [xml]$x = Read-PaperDevText $f.FullName } catch { continue }
            foreach ($tc in $x.SelectNodes('//testcase')) {
                $total++
                if ($tc.SelectSingleNode('skipped')) { $skipped++ }
                $fail = $tc.SelectSingleNode('failure')
                if (-not $fail) { $fail = $tc.SelectSingleNode('error') }
                if ($fail) {
                    $msg = [string]$fail.GetAttribute('message')
                    $body = [string]$fail.InnerText
                    $failures += [PSCustomObject]@{ Name = ($tc.GetAttribute('classname') + '.' + $tc.GetAttribute('name')); Message = $msg; Detail = (($body -split "`r?`n" | Select-Object -First 8) -join "`n") }
                }
            }
        }
    }
    return [PSCustomObject]@{ Total = $total; Skipped = $skipped; Failures = $failures; Found = ($dirs.Count -gt 0) }
}

function Find-PaperDevPluginJar {
    # The jar to put in plugins/: the shaded jar when there is one, else the plain jar. Newest wins.
    param($Project)
    $dirs = @()
    foreach ($base in @($Project.Module, $Project.Root) | Select-Object -Unique) {
        foreach ($d in @('build/libs', 'target')) {
            $p = Join-Path $base $d
            if (Test-Path -LiteralPath $p) { $dirs += $p }
        }
    }
    $jars = @()
    foreach ($d in $dirs) {
        $jars += @(Get-ChildItem -LiteralPath $d -Filter '*.jar' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch '-(sources|javadoc|dev|plain|original)\.jar$' -and $_.Name -notmatch '^original-' })
    }
    if ($jars.Count -eq 0) { return $null }
    $shaded = @($jars | Where-Object { $_.Name -match '-all\.jar$' })
    if ($shaded.Count -gt 0) { $jars = $shaded }
    return ($jars | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}

# ---------------------------------------------------------------- test server

function Get-PaperDevServerDir {
    param($Project)
    return (Join-Path (Get-PaperDevHomeDir 'servers') $Project.Id)
}

function Get-PaperDevSession {
    param($Project)
    $path = Join-Path (Get-PaperDevServerDir $Project) 'papermc-developer-session.json'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try { return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function Save-PaperDevSession {
    param($Project, $Session)
    $path = Join-Path (Get-PaperDevServerDir $Project) 'papermc-developer-session.json'
    Write-PaperDevText -Path $path -Text ($Session | ConvertTo-Json -Depth 5)
}

function Test-PaperDevPortFree {
    param([int]$Port)
    $listener = $null
    try {
        $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $Port)
        $listener.Start()
        return $true
    } catch { return $false } finally { if ($listener) { $listener.Stop() } }
}

function Find-PaperDevFreePort {
    param([int]$From, [int]$To, [int[]]$Exclude = @())
    for ($p = $From; $p -le $To; $p++) {
        if ($Exclude -contains $p) { continue }
        if (Test-PaperDevPortFree $p) { return $p }
    }
    return 0
}

function Invoke-PaperDevRcon {
    # Minecraft RCON (Source RCON protocol). Returns the response text; throws on connection or auth failure.
    param([int]$Port, [string]$Password, [string]$Command, [int]$TimeoutMs = 10000)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $ar = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
        if (-not $ar.AsyncWaitHandle.WaitOne($TimeoutMs)) { throw ('RCON: cannot connect to 127.0.0.1:' + $Port) }
        $client.EndConnect($ar)
        $client.ReceiveTimeout = $TimeoutMs
        $client.SendTimeout = $TimeoutMs
        $stream = $client.GetStream()
        Send-PaperDevRconPacket $stream 1 3 $Password
        $auth = Read-PaperDevRconPacket $stream
        if ($auth.Type -ne 2) { $auth = Read-PaperDevRconPacket $stream }
        if ($auth.Id -eq -1) { throw 'RCON: authentication failed' }
        Send-PaperDevRconPacket $stream 2 2 $Command
        # A packet of an unknown type is answered after the command's reply; it marks the end of a split reply.
        Send-PaperDevRconPacket $stream 3 0 ''
        $sb = New-Object System.Text.StringBuilder
        while ($true) {
            $p = Read-PaperDevRconPacket $stream
            if ($p.Id -eq 3) { break }
            [void]$sb.Append($p.Body)
        }
        return $sb.ToString()
    } finally { $client.Close() }
}

function Send-PaperDevRconPacket {
    param($Stream, [int]$Id, [int]$Type, [string]$Body)
    $payload = [System.Text.Encoding]::UTF8.GetBytes($Body)
    $len = 4 + 4 + $payload.Length + 2
    $buf = New-Object byte[] (4 + $len)
    [Array]::Copy([BitConverter]::GetBytes([int]$len), 0, $buf, 0, 4)
    [Array]::Copy([BitConverter]::GetBytes([int]$Id), 0, $buf, 4, 4)
    [Array]::Copy([BitConverter]::GetBytes([int]$Type), 0, $buf, 8, 4)
    [Array]::Copy($payload, 0, $buf, 12, $payload.Length)
    $Stream.Write($buf, 0, $buf.Length)
    $Stream.Flush()
}

function Read-PaperDevRconBytes {
    param($Stream, [int]$Count)
    $buf = New-Object byte[] $Count
    $off = 0
    while ($off -lt $Count) {
        $n = $Stream.Read($buf, $off, $Count - $off)
        if ($n -le 0) { throw 'RCON: connection closed' }
        $off += $n
    }
    return ,$buf
}

function Read-PaperDevRconPacket {
    param($Stream)
    $lenBytes = Read-PaperDevRconBytes $Stream 4
    $len = [BitConverter]::ToInt32($lenBytes, 0)
    $data = Read-PaperDevRconBytes $Stream $len
    $id = [BitConverter]::ToInt32($data, 0)
    $type = [BitConverter]::ToInt32($data, 4)
    $body = ''
    if ($len -gt 10) { $body = [System.Text.Encoding]::UTF8.GetString($data, 8, $len - 10) }
    return [PSCustomObject]@{ Id = $id; Type = $type; Body = $body }
}

function Get-PaperDevLogEntries {
    # Parses logs/latest.log into entries: Time, Thread, Level, Source ([PluginName] prefix), Message, Lines.
    # Lines that do not start with a timestamp (stack traces) belong to the entry above them.
    param([string]$Path, [int]$SkipLines = 0)
    $entries = New-Object System.Collections.ArrayList
    if (-not (Test-Path -LiteralPath $Path)) { return ,@() }
    $fs = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $reader = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
        $all = $reader.ReadToEnd()
    } finally { $fs.Dispose() }
    $lines = @($all -split "`r?`n")
    $current = $null
    for ($i = $SkipLines; $i -lt $lines.Count; $i++) {
        $l = $lines[$i]
        # Paper: "[12:00:00] [Server thread/INFO]: [Plugin] message"
        # Velocity: "[12:00:00] [main/INFO] [logger]: message" (a plugin's logger is named by its id)
        if ($l -match '^\[(\d\d:\d\d:\d\d)\] \[([^\]]*?)/([A-Z]+)\](?: \[([^\]]+)\])?: (.*)$') {
            # Copy the groups first: the next -match replaces $Matches.
            $time = $Matches[1]; $thread = $Matches[2]; $level = $Matches[3]; $logger = $Matches[4]; $msg = $Matches[5]
            $source = ''
            if ($logger) { $source = $logger }
            elseif ($msg -match '^\[([^\]]+)\] ') { $source = $Matches[1] }
            $current = [PSCustomObject]@{ Time = $time; Thread = $thread; Level = $level; Source = $source; Message = $msg; Lines = @($l); LineNo = ($i + 1) }
            [void]$entries.Add($current)
        } elseif ($current -and $l -ne '') {
            $current.Lines += $l
        }
    }
    return ,$entries.ToArray()
}

function Get-PaperDevLogLineCount {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    $fs = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $reader = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
        $n = @($reader.ReadToEnd() -split "`r?`n").Count
        return [Math]::Max(0, $n - 1)
    } finally { $fs.Dispose() }
}

function Write-PaperDevLogEntry {
    param($Entry, [int]$MaxLines = 30)
    $shown = @($Entry.Lines | Select-Object -First $MaxLines)
    foreach ($l in $shown) { Write-Host $l }
    if ($Entry.Lines.Count -gt $MaxLines) { Write-Host ('    ... ' + ($Entry.Lines.Count - $MaxLines) + ' more line(s)') }
}

function Test-PaperDevEntryAboutPlugin {
    # True when a log entry comes from the plugin or its stack trace runs through the plugin's package.
    param($Entry, [string]$PluginName, [string]$Package)
    if ($PluginName -and $Entry.Source -eq $PluginName) { return $true }
    $text = $Entry.Lines -join "`n"
    if ($PluginName -and $text -match ('(?i)\b' + [regex]::Escape($PluginName) + '\b')) { return $true }
    # Load errors name the jar, which the build calls after the project ("FoliaTest" -> "folia-test-0.1.0.jar").
    if ($PluginName) {
        $kebab = ($PluginName -creplace '([a-z0-9])([A-Z])', '$1-$2').ToLowerInvariant()
        if ($text -match ('(?i)[\\/]' + [regex]::Escape($kebab) + '-[0-9][^\\/'']*\.jar')) { return $true }
    }
    if ($Package -and $text.Contains($Package + '.')) { return $true }
    return $false
}
