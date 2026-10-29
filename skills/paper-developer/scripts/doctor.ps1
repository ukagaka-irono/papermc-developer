<#
.SYNOPSIS
  Diagnoses the environment for developing a Paper plugin. Changes nothing.
.DESCRIPTION
  Shows the plugin project (root, build tool, plugin.yml or paper-plugin.yml), Java and the version the
  target Minecraft version needs, the build wrapper, Git, PLUGIN.md, and whether the test server can run
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
    Add-Item 'target' 'recommended' ([bool]$versions.PaperApi) $t 'The Minecraft version the plugin is compiled against.' 'Add compileOnly("io.papermc.paper:paper-api:<version>.build.+") (references/layout.md), or see references/workflows/update-paper.md.'
}

$java = Get-PaperDevJava $JavaPath
if ($java) {
    $ok = $true
    $d = $java.Version + ' at ' + $java.Path
    if ($javaNeeded) {
        $d += ' (Minecraft ' + $target + ' needs Java ' + $javaNeeded + '+)'
        if ($java.Major -lt $javaNeeded) { $ok = $false }
    }
    Add-Item 'java' 'required' $ok $d 'Runs Gradle and the test server.' ('Install a JDK ' + $javaNeeded + ' or newer (Windows: winget install --id EclipseAdoptium.Temurin.' + $javaNeeded + '.JDK -e), or set javaPath in local.json / PAPERDEV_JAVA.')
} else {
    $need = '21'
    if ($javaNeeded) { $need = [string]$javaNeeded }
    Add-Item 'java' 'required' $false 'java not found (PAPERDEV_JAVA, local.json javaPath, JAVA_HOME, PATH)' 'Runs Gradle and the test server.' ('Install a JDK ' + $need + ' or newer (Windows: winget install --id EclipseAdoptium.Temurin.' + $need + '.JDK -e). Restart the agent afterwards so PATH is reloaded.')
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

if ($project) {
    $pm = Join-Path $project.Root 'PLUGIN.md'
    $pmOk = Test-Path -LiteralPath $pm
    $pmDetail = 'PLUGIN.md'
    if ($pmOk -and (Read-PaperDevText $pm) -match 'paper-developer:plugin-template') { $pmOk = $false; $pmDetail = 'PLUGIN.md is still the empty template' }
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
        project = $(if ($project) { $project.Root } else { $null }); kind = $(if ($project) { $project.Kind } else { $null })
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
