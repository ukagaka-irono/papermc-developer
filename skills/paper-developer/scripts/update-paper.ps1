<#
.SYNOPSIS
  Moves the project to another (by default the latest stable) Minecraft / Paper version.
.DESCRIPTION
  Updates, in the build files: the paper-api (or folia-api) dependency, the Java toolchain (raised to what
  the version needs, never lowered), run-paper's minecraftVersion, the MockBukkit artifact, and the
  java-version of .github/workflows/*.yml. With -ApiVersion it also raises api-version in the descriptor
  (servers older than that then refuse the plugin: only when the user wants to drop them).
  Before writing, the files are copied to <home>/backups/<time>/. Afterwards scripts/check.ps1 runs; when
  the build breaks, the API changed: fix the code (references/workflows/update-paper.md), or restore.
  Lines the script does not recognise (versions in a version catalog, variables) are reported for a manual edit.
  -DryRun shows the plan only.
  Exit codes: 0 / 1 failed, or the check failed after the update / 2 something needs a manual edit.
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/update-paper.ps1 -DryRun
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/update-paper.ps1 -Minecraft 26.3 -ApiVersion
#>
param(
    [string]$ProjectRoot,
    [string]$Minecraft,
    [switch]$ApiVersion,
    [switch]$NoCheck,
    [switch]$DryRun
)
. (Join-Path $PSScriptRoot 'lib/common.ps1')
Initialize-PaperDevConsole

$project = Resolve-PaperDevProject $ProjectRoot
if (-not $project) { Write-PaperDevStatus 'error' 'no Gradle or Maven project found (pass -ProjectRoot)'; exit 1 }
$current = Get-PaperDevProjectVersions $project
$platform = $current.Platform
try {
    if (-not $Minecraft) { $Minecraft = Get-PaperDevLatestMinecraft -Project $platform }
    $info = Get-PaperDevVersionInfo -Minecraft $Minecraft -Project $platform
    $mock = $null
    if ($current.MockBukkit) { $mock = Get-PaperDevMockBukkit -Minecraft $Minecraft }
} catch { Write-PaperDevStatus 'error' ('lookup failed: ' + $_.Exception.Message); exit 1 }
$javaMin = $info.JavaMinimum
$coordinate = Get-PaperDevApiCoordinate $Minecraft
$mavenCoordinate = $coordinate
if (Test-PaperDevModernVersion $Minecraft) { $mavenCoordinate = '[' + $Minecraft + '.build,)' }

Write-Host ('project: ' + $project.Root)
Write-Host ('from:    ' + $platform + ' ' + $current.Minecraft + ' (' + $current.PaperApi + '), java ' + $current.Java)
Write-Host ('to:      ' + $platform + ' ' + $Minecraft + ' (' + $coordinate + '), java ' + $javaMin + '+')

$changes = New-Object System.Collections.ArrayList
$manual = New-Object System.Collections.ArrayList
$newTexts = @{}

function Update-Text {
    param([string]$File, [string]$Text, [string]$Pattern, [scriptblock]$Replace, [string]$What)
    $rx = New-Object System.Text.RegularExpressions.Regex($Pattern)
    $result = $rx.Replace($Text, {
        param($m)
        $new = & $Replace $m
        if ($new -ne $m.Value) { [void]$changes.Add([PSCustomObject]@{ File = $File; What = $What; Old = $m.Value; New = $new }) }
        return $new
    })
    return $result
}

$files = @(Get-PaperDevBuildFiles $project)
$wfDir = Join-Path $project.Root '.github/workflows'
if (Test-Path -LiteralPath $wfDir) { $files += @(Get-ChildItem -LiteralPath $wfDir -File -Include '*.yml', '*.yaml' -Recurse | ForEach-Object { $_.FullName }) }
if ($ApiVersion -and $project.Descriptor) { $files += $project.Descriptor }

foreach ($f in $files) {
    $text = Read-PaperDevText $f
    $orig = $text
    $leaf = Split-Path -Leaf $f
    if ($leaf -match '\.gradle(\.kts)?$') {
        $text = Update-Text $f $text '(io\.papermc\.paper:paper-api:|dev\.folia:folia-api:)([0-9][^"''\s)]*)' { param($m) $m.Groups[1].Value + $coordinate } 'api dependency'
        $text = Update-Text $f $text 'JavaLanguageVersion\.of\(\s*(\d+)\s*\)' { param($m) if ($javaMin -and [int]$m.Groups[1].Value -lt $javaMin) { 'JavaLanguageVersion.of(' + $javaMin + ')' } else { $m.Value } } 'java toolchain'
        $text = Update-Text $f $text 'minecraftVersion\(\s*"([^"]+)"\s*\)' { param($m) 'minecraftVersion("' + $Minecraft + '")' } 'run-paper'
        if ($mock) { $text = Update-Text $f $text 'org\.mockbukkit\.mockbukkit:mockbukkit-v[0-9.]+:[^"''\s)]+' { param($m) 'org.mockbukkit.mockbukkit:' + $mock.Artifact + ':' + $mock.Version } 'MockBukkit' }
        elseif ($current.MockBukkit) { [void]$manual.Add('MockBukkit has no release for ' + $Minecraft + ' yet; keep ' + $current.MockBukkit + ' (tests may fail) or wait') }
        if ($orig -match 'paper-api' -and $text -notmatch 'paper-api:' -and $text -notmatch 'folia-api:') { [void]$manual.Add($leaf + ': paper-api is declared in a form the script does not edit') }
    } elseif ($leaf -eq 'pom.xml') {
        $text = Update-Text $f $text '(<artifactId>(?:paper|folia)-api</artifactId>\s*<version>)([^<]+)(</version>)' { param($m) $m.Groups[1].Value + $mavenCoordinate + $m.Groups[3].Value } 'api dependency'
        $text = Update-Text $f $text '<maven\.compiler\.release>(\d+)</maven\.compiler\.release>' { param($m) if ($javaMin -and [int]$m.Groups[1].Value -lt $javaMin) { '<maven.compiler.release>' + $javaMin + '</maven.compiler.release>' } else { $m.Value } } 'java release'
    } elseif ($leaf -eq 'libs.versions.toml' -or $leaf -eq 'gradle.properties') {
        if ($text -match '(?im)^\s*(paper|minecraft|mc)[A-Za-z_.-]*\s*[=:]') { [void]$manual.Add($leaf + ': has version entries; edit them by hand (target ' + $Minecraft + ', paper-api ' + $coordinate + ')') }
    } elseif ($leaf -match '\.ya?ml$' -and $f -like ($wfDir + '*')) {
        $text = Update-Text $f $text "java-version:\s*['""]?(\d+)['""]?" { param($m) if ($javaMin -and [int]$m.Groups[1].Value -lt $javaMin) { "java-version: '" + $javaMin + "'" } else { $m.Value } } 'workflow java'
    } elseif ($f -eq $project.Descriptor) {
        $text = Update-Text $f $text "(?m)^api-version:\s*['""]?([^'""\s]+)['""]?" { param($m) "api-version: '" + (Get-PaperDevApiVersionField $Minecraft) + "'" } 'api-version'
    }
    if ($text -ne $orig) { $newTexts[$f] = $text }
}

foreach ($c in $changes) {
    $rel = $c.File.Substring($project.Root.Length).TrimStart('\', '/')
    Write-PaperDevStatus $(if ($DryRun) { 'plan' } else { 'change' }) ($rel + ' (' + $c.What + '): ' + $c.Old + ' -> ' + $c.New)
}
foreach ($m in $manual) { Write-PaperDevStatus 'manual' $m }
if (-not $ApiVersion -and $project.Descriptor) {
    $api = (Read-PaperDevDescriptor $project.Descriptor).Values['api-version']
    Write-PaperDevStatus 'note' ('api-version stays ' + $api + ' (the oldest server version the plugin claims to support); -ApiVersion raises it')
}
if ($changes.Count -eq 0) {
    Write-PaperDevStatus 'ok' 'nothing to change'
    if ($manual.Count -gt 0) { exit 2 }
    exit 0
}
if ($DryRun) { if ($manual.Count -gt 0) { exit 2 }; exit 0 }

$backup = Join-Path (Get-PaperDevHomeDir 'backups') ((Get-Date).ToString('yyyyMMdd-HHmmss') + '-' + $project.Id)
foreach ($f in $newTexts.Keys) {
    $rel = $f.Substring($project.Root.Length).TrimStart('\', '/')
    $dest = Join-Path $backup $rel
    New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
    Copy-Item -LiteralPath $f -Destination $dest -Force
    Write-PaperDevText -Path $f -Text $newTexts[$f]
}
Write-Host ('backup of the changed files: ' + $backup)

if (-not $NoCheck) {
    & (Join-Path $PSScriptRoot 'check.ps1') -ProjectRoot $project.Root
    if ($LASTEXITCODE -ne 0) {
        Write-PaperDevStatus 'error' ('the check fails on ' + $Minecraft + ': fix the code for the API changes (references/workflows/update-paper.md), or copy the files back from ' + $backup)
        exit 1
    }
}
if ($manual.Count -gt 0) { exit 2 }
exit 0
