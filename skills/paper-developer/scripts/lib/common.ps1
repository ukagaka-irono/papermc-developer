# Shared helpers for the paper-developer scripts.
# Rules for every script: ASCII only (Windows PowerShell 5.1 reads BOM-less files as ANSI),
# no PowerShell 7-only syntax, exit codes 0 OK / 1 failed / 2 needs attention / 3 cannot check (tool missing).

$ErrorActionPreference = 'Stop'

$PaperDevName = 'paper-developer'
$PaperDevRepo = 'ukagaka-irono/paper-developer'
$PaperDevUserAgent = 'paper-developer (+https://github.com/ukagaka-irono/paper-developer)'
$PaperDevSkillDir = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$PaperDevFillApi = 'https://fill.papermc.io/v3/projects'
$PaperDevMavenPaper = 'https://repo.papermc.io/repository/maven-public'
$PaperDevMavenCentral = 'https://repo1.maven.org/maven2'
$PaperDevPluginPortal = 'https://plugins.gradle.org/m2'
$PaperDevEulaUrl = 'https://aka.ms/MinecraftEULA'

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
    $base = $env:PAPERDEV_HOME
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
    $out = Join-Path ([System.IO.Path]::GetTempPath()) ('paper-developer-' + [guid]::NewGuid().ToString('N') + '.log')
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

function Get-PaperDevApiCoordinate {
    # The paper-api version string for a Minecraft version, as the Paper docs write it.
    param([string]$Minecraft)
    if (Test-PaperDevModernVersion $Minecraft) { return ($Minecraft + '.build.+') }
    return ($Minecraft + '-R0.1-SNAPSHOT')
}

function Test-PaperDevModernVersion {
    # 26.1 and later use "<version>.build.<n>-<channel>" for paper-api; 1.x used "-R0.1-SNAPSHOT".
    param([string]$Minecraft)
    return ($Minecraft -match '^(\d+)\.' -and [int]$Matches[1] -ge 26)
}

function Get-PaperDevApiVersionField {
    # The api-version value for plugin.yml / paper-plugin.yml.
    param([string]$Minecraft)
    if (Test-PaperDevModernVersion $Minecraft) { return $Minecraft }
    if ($Minecraft -match '^1\.(\d+)') {
        if ([int]$Matches[1] -ge 21 -or $Minecraft -match '^1\.20\.[5-9]') { return $Minecraft }
        return ('1.' + $Matches[1])
    }
    return $Minecraft
}

function Get-PaperDevLatestApiBuild {
    # Newest concrete paper-api version for a Minecraft version (e.g. 26.3.build.229-stable).
    param([string]$Minecraft)
    $versions = Get-PaperDevMavenVersions -Repository $PaperDevMavenPaper -Group 'io.papermc.paper' -Artifact 'paper-api'
    if (Test-PaperDevModernVersion $Minecraft) {
        $prefix = $Minecraft + '.build.'
        $best = $null; $bestN = -1
        foreach ($v in $versions) {
            if ($v.StartsWith($prefix) -and $v -match '\.build\.(\d+)-') {
                $n = [int]$Matches[1]
                if ($n -gt $bestN) { $bestN = $n; $best = $v }
            }
        }
        return $best
    }
    $want = $Minecraft + '-R0.1-SNAPSHOT'
    if ($versions -contains $want) { return $want }
    return $null
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
    # Finds java: -JavaPath, PAPERDEV_JAVA, local.json javaPath, JAVA_HOME, PATH. Returns $null when none.
    param([string]$JavaPath)
    $exe = 'java'
    if (Test-PaperDevWindows) { $exe = 'java.exe' }
    $candidates = @()
    if ($JavaPath) { $candidates += $JavaPath }
    if ($env:PAPERDEV_JAVA) { $candidates += $env:PAPERDEV_JAVA }
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
    # Finds the plugin project: -ProjectRoot, PAPERDEV_PROJECT_ROOT, then the working folder and its parents.
    # Returns $null when no project is found (the caller decides whether that is an error).
    param([string]$ProjectRoot)
    $start = $ProjectRoot
    if (-not $start) { $start = $env:PAPERDEV_PROJECT_ROOT }
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
    $result = [PSCustomObject]@{ PaperApi = $null; Minecraft = $null; Java = $null; RunPaper = $null; MockBukkit = $null; Platform = 'paper' }
    foreach ($f in (Get-PaperDevBuildFiles $Project)) {
        $text = Read-PaperDevText $f
        if (-not $result.PaperApi -and $text -match '(?:io\.papermc\.paper:paper-api:|paper-api["'']?\s*[,:]\s*version\s*=\s*["'']|<artifactId>paper-api</artifactId>\s*<version>)([0-9][^"''<\s]*)') { $result.PaperApi = $Matches[1] }
        if (-not $result.PaperApi -and $text -match 'dev\.folia:folia-api:([0-9][^"''\s]*)') { $result.PaperApi = $Matches[1]; $result.Platform = 'folia' }
        if (-not $result.Java -and $text -match 'JavaLanguageVersion\.of\(\s*(\d+)\s*\)') { $result.Java = [int]$Matches[1] }
        if (-not $result.Java -and $text -match '<maven\.compiler\.release>(\d+)<') { $result.Java = [int]$Matches[1] }
        if (-not $result.RunPaper -and $text -match 'minecraftVersion\(\s*"([^"]+)"\s*\)') { $result.RunPaper = $Matches[1] }
        if (-not $result.MockBukkit -and $text -match 'org\.mockbukkit\.mockbukkit:(mockbukkit-v[0-9.]+):([^"''\s]+)') { $result.MockBukkit = $Matches[1] + ':' + $Matches[2] }
    }
    if ($result.PaperApi -and $result.PaperApi -match '^(\d+\.\d+(?:\.\d+)?)(?:\.build|-R0\.1)') { $result.Minecraft = $Matches[1] }
    elseif ($result.RunPaper) { $result.Minecraft = $result.RunPaper }
    return $result
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
    $path = Join-Path (Get-PaperDevServerDir $Project) 'paper-developer-session.json'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try { return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function Save-PaperDevSession {
    param($Project, $Session)
    $path = Join-Path (Get-PaperDevServerDir $Project) 'paper-developer-session.json'
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
        if ($l -match '^\[(\d\d:\d\d:\d\d)\] \[([^\]]*?)/([A-Z]+)\]: (.*)$') {
            # Copy the groups first: the next -match replaces $Matches.
            $time = $Matches[1]; $thread = $Matches[2]; $level = $Matches[3]; $msg = $Matches[4]
            $source = ''
            if ($msg -match '^\[([^\]]+)\] ') { $source = $Matches[1] }
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
    if ($Package -and $text.Contains($Package + '.')) { return $true }
    return $false
}
