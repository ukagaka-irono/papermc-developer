<#
.SYNOPSIS
  Diagnoses the environment for developing a Paper plugin. Changes nothing.
.DESCRIPTION
  Shows the plugin project (root, build tool, plugin.yml or paper-plugin.yml), Java and the version the
  target Minecraft version needs, the build wrapper, Git and the current branch (main / develop / <topic>-fix), PLUGIN.md, and whether the test server can run
  (EULA agreement). Each missing item comes with its purpose and how to fix it.
  Exit codes: 0 required items are present / 1 a required item is missing.
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/doctor.ps1
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/doctor.ps1 -Json
#>
param(
    [string]$ProjectRoot,
    [string]$JavaPath,
    [switch]$Offline,
    [switch]$Json
)
. (Join-Path $PSScriptRoot 'lib/common.ps1')
Initialize-PaperDevConsole

$items = New-Object System.Collections.ArrayList
function Add-Item {
    param([string]$Name, [string]$Level, [bool]$Ok, [string]$Detail, [string]$Purpose, [string]$Fix)
    [void]$items.Add([PSCustomObject]@{ name = $Name; level = $Level; ok = $Ok; detail = $Detail; purpose = $Purpose; fix = $Fix })
}

$project = Resolve-PaperDevProject $ProjectRoot
$versions = $null
if ($project) {
    $versions = Get-PaperDevProjectVersions $project
    $detail = $project.Root + ' (' + $project.BuildTool + ')'
    Add-Item 'project' 'required' $true $detail 'The plugin project the scripts work on.' ''
    if ($project.Descriptor) {
        $rel = $project.Descriptor.Substring($project.Root.Length).TrimStart('\', '/')
        $kindText = 'Bukkit-style plugin.yml'
        if ($project.Kind -eq 'paper') { $kindText = 'Paper plugin (paper-plugin.yml)' }
        Add-Item 'descriptor' 'required' $true ($rel + ' - ' + $kindText) 'Declares the plugin to the server.' ''
    } else {
        Add-Item 'descriptor' 'required' $false 'no plugin.yml or paper-plugin.yml under src/main/resources' 'Declares the plugin to the server.' 'Add src/main/resources/plugin.yml (references/layout.md), or create a new project with scripts/new-plugin.ps1.'
    }
} else {
    Add-Item 'project' 'required' $false ('no Gradle or Maven project found from ' + (Get-Location).Path) 'The plugin project the scripts work on.' 'Open the folder that has settings.gradle.kts (or pom.xml), pass -ProjectRoot, or create one with scripts/new-plugin.ps1.'
}

# Target and the Java it needs
$target = $null
$javaNeeded = $null
$latest = $null
if (-not $Offline) {
    try { $latest = Get-PaperDevLatestMinecraft } catch { }
}
if ($versions -and $versions.Minecraft) { $target = $versions.Minecraft } elseif ($latest) { $target = $latest }
if ($target -and -not $Offline) {
    try { $javaNeeded = (Get-PaperDevVersionInfo -Minecraft $target).JavaMinimum } catch { }
}
if ($versions) {
    $t = 'paper-api ' + $versions.PaperApi
    if (-not $versions.PaperApi) { $t = 'paper-api not found in the build files' }
    if ($latest -and $versions.Minecraft -and $versions.Minecraft -ne $latest) { $t += ' (latest stable Minecraft: ' + $latest + ')' }
    Add-Item 'target' 'recommended' ([bool]$versions.PaperApi) $t 'The Minecraft version the plugin is compiled against.' 'Add the API dependency for the version (scripts/versions.ps1 -Minecraft <version> prints it; references/layout.md), or see references/workflows/update-paper.md.'
}

# The java that runs Gradle (17+; the JDK the code is compiled with comes from the Gradle toolchain), and
# the one the test server of the target version runs on (old versions do not run on new Java).
$java = Get-PaperDevJava $JavaPath
if ($java) {
    Add-Item 'java' 'required' ($java.Major -ge 17) ($java.Version + ' at ' + $java.Path + ' (runs Gradle; 17+ needed)') 'Runs Gradle.' 'Install a JDK 17 or newer (Windows: winget install --id EclipseAdoptium.Temurin.25.JDK -e), or point to one with scripts/setup.ps1 -JavaPath.'
} else {
    Add-Item 'java' 'required' $false 'java not found (PAPERMCDEV_JAVA, local.json javaPath, JAVA_HOME, PATH)' 'Runs Gradle.' 'Install a JDK 17 or newer (Windows: winget install --id EclipseAdoptium.Temurin.25.JDK -e). Restart the agent afterwards so PATH is reloaded.'
}
if ($target) {
    $era = Get-PaperDevEra -Minecraft $target -JavaMinimum ([int]$javaNeeded)
    $range = [string]$era.JavaMin
    if ($era.JavaMax -ge 99) { $range += '+' } elseif ($era.JavaMax -ne $era.JavaMin) { $range += '-' + $era.JavaMax }
    $serverJava = Get-PaperDevServerJava -Minecraft $target -JavaMinimum ([int]$javaNeeded)
    $d = 'Minecraft ' + $target + ' runs on Java ' + $range
    if ($serverJava) { $d += ': ' + $serverJava.Version + ' at ' + $serverJava.Path } else { $d += ': none installed' }
    Add-Item 'server-java' 'recommended' ([bool]$serverJava) $d 'Runs the test server (scripts/run-server.ps1).' ('Ask the user, then scripts/setup.ps1 -Jdk ' + $era.JavaPreferred + ' (downloads Eclipse Temurin ' + $era.JavaPreferred + '), or register an installed JDK with scripts/setup.ps1 -JavaPath <folder>.')
}

if ($project) {
    if ($project.BuildTool -eq 'maven') {
        $m = Get-PaperDevMavenCommand $project
        Add-Item 'maven' 'required' ([bool]$m) ([string]$m) 'Builds the plugin.' 'Add the Maven wrapper (mvn wrapper:wrapper) or install Maven.'
    } else {
        $g = Get-PaperDevGradleCommand $project
        $isWrapper = $g -and ($g -match 'gradlew(\.bat)?$')
        $d = [string]$g
        if ($g -and -not $isWrapper) { $d += ' (no gradlew in the project; the build uses this Gradle)' }
        Add-Item 'gradle' 'required' ([bool]$g) $d 'Builds the plugin.' 'Generate the wrapper: scripts/new-plugin.ps1 -WrapperOnly (downloads Gradle once into the home folder).'
    }
}

$git = Get-Command git -ErrorAction SilentlyContinue | Select-Object -First 1
Add-Item 'git' 'recommended' ([bool]$git) ([string]$(if ($git) { $git.Source } else { '' })) 'History of changes, GitHub Actions, releases.' 'winget install --id Git.Git -e'

# Branches: main (released) / develop (next release) / <topic>-fix (one change each). references/workflows/branches.md
$branch = $null
if ($git -and $project) {
    $inside = Invoke-PaperDevProcess -FilePath $git.Source -Arguments @('-C', $project.Root, 'rev-parse', '--is-inside-work-tree')
    if ($inside.ExitCode -eq 0 -and $inside.StdOut.Trim() -eq 'true') {
        $branch = (Invoke-PaperDevProcess -FilePath $git.Source -Arguments @('-C', $project.Root, 'branch', '--show-current')).StdOut.Trim()
        $hasDevelop = (Invoke-PaperDevProcess -FilePath $git.Source -Arguments @('-C', $project.Root, 'rev-parse', '--verify', '--quiet', 'refs/heads/develop')).ExitCode -eq 0
        $ok = $true
        $d = 'on ' + $branch
        $fix = ''
        if (-not $branch) { $ok = $false; $d = 'detached HEAD (no branch)'; $fix = 'git switch develop, then git switch -c <topic>-fix' }
        elseif (-not $hasDevelop) { $ok = $false; $d += '; no develop branch'; $fix = 'Ask the user, then create develop from main: git branch develop main (references/workflows/branches.md)' }
        elseif ($branch -eq 'main' -or $branch -eq 'master' -or $branch -eq 'develop') { $ok = $false; $d += ' (do not commit here)'; $fix = 'Before changing code: git switch develop, then git switch -c <topic>-fix (e.g. hello-command-fix)' }
        elseif ($branch -notmatch '-fix$') { $ok = $false; $d += ' (work branches are named <topic>-fix)'; $fix = 'Ask the user whether to keep working here or move to a <topic>-fix branch from develop' }
        Add-Item 'branch' 'recommended' $ok $d 'Work happens on <topic>-fix branches made from develop; develop goes into main for releases.' $fix
    }
}

if ($project) {
    $pm = Join-Path $project.Root 'PLUGIN.md'
    $pmOk = Test-Path -LiteralPath $pm
    $pmDetail = 'PLUGIN.md'
    if ($pmOk -and (Read-PaperDevText $pm) -match 'papermc-developer:plugin-template') { $pmOk = $false; $pmDetail = 'PLUGIN.md is still the empty template' }
    elseif (-not $pmOk) { $pmDetail = 'no PLUGIN.md' }
    Add-Item 'plugin-profile' 'recommended' $pmOk $pmDetail 'What this plugin is: commands, permissions, config, rules. The agent reads it first.' 'references/workflows/setup.md (draft it from the code), scripts/init-plugin.ps1 creates the empty form.'
}

$cfg = Get-PaperDevLocalConfig
$eula = $cfg.PSObject.Properties['eulaAccepted'] -and $cfg.eulaAccepted -eq $true
Add-Item 'eula' 'recommended' $eula ([string]$(if ($eula) { 'agreed (local.json)' } else { 'not agreed yet' })) ('The test server (scripts/run-server.ps1) runs the Minecraft server, which needs the Minecraft EULA: ' + $PaperDevEulaUrl) 'Ask the user to read the EULA. Only after they agree: scripts/setup.ps1 -AcceptEula'

$gh = Get-Command gh -ErrorAction SilentlyContinue | Select-Object -First 1
Add-Item 'gh' 'optional' ([bool]$gh) ([string]$(if ($gh) { $gh.Source } else { '' })) 'GitHub releases from the command line.' 'winget install --id GitHub.cli -e'

$home2 = Get-PaperDevHome
$missingRequired = @($items | Where-Object { $_.level -eq 'required' -and -not $_.ok }).Count

if ($Json) {
    $out = [PSCustomObject]@{
        project = $(if ($project) { $project.Root } else { $null }); kind = $(if ($project) { $project.Kind } else { $null }); branch = $branch
        minecraft = $target; latestMinecraft = $latest; javaRequired = $javaNeeded; home = $home2; items = $items.ToArray()
    }
    Write-Output ($out | ConvertTo-Json -Depth 5)
} else {
    Write-Host ('home: ' + $home2)
    if ($target) { Write-Host ('minecraft: ' + $target + $(if ($latest -and $latest -ne $target) { ' (latest stable ' + $latest + ')' } else { '' })) }
    foreach ($i in $items) {
        $st = 'ok'
        if (-not $i.ok) { if ($i.level -eq 'required') { $st = 'missing' } else { $st = 'warn' } }
        Write-PaperDevStatus $st ($i.name + ' (' + $i.level + '): ' + $i.detail)
        if (-not $i.ok) {
            Write-Host ('          purpose: ' + $i.purpose)
            if ($i.fix) { Write-Host ('          fix: ' + $i.fix) }
        }
    }
}
if ($missingRequired -gt 0) { exit 1 }
exit 0
