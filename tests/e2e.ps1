<#
.SYNOPSIS
  End-to-end test: creates plugins from the templates in a temporary folder and builds, tests and packages them.
.DESCRIPTION
  Needs the network (Paper, Maven, Gradle) and a JDK that can run Gradle. PAPERMCDEV_HOME points to a temporary
  folder unless -KeepHome is given, so the user's home folder is not touched. The test server is not started
  (that needs the user's agreement to the Minecraft EULA).
  Exit codes: 0 / 1 a step failed.
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File tests/e2e.ps1
#>
param([switch]$KeepHome, [switch]$KeepFiles)
$ErrorActionPreference = 'Stop'
$scripts = Join-Path $PSScriptRoot '../skills/papermc-developer/scripts'
$work = Join-Path ([System.IO.Path]::GetTempPath()) ('papermc-developer-e2e-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work -Force | Out-Null
if (-not $KeepHome) { $env:PAPERMCDEV_HOME = Join-Path $work 'home' }
$shell = 'powershell'
if ($PSVersionTable.PSEdition -eq 'Core') { $shell = 'pwsh' }
$failed = @()
function Step {
    param([string]$Name, [string]$Script, [string[]]$Arguments, [int[]]$Ok = @(0))
    Write-Host ('==== ' + $Name)
    & $shell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scripts $Script) @Arguments
    $code = $LASTEXITCODE
    if ($Ok -notcontains $code) { Write-Host ('==== FAILED (exit ' + $code + '): ' + $Name); $script:failed += $Name }
}
try {
    Push-Location $work
    Step 'new plugin.yml project' 'new-plugin.ps1' @('-Name', 'E2eBukkit', '-Description', 'end-to-end test', '-Workflow', '-Path', (Join-Path $work 'bukkit'))
    Step 'new paper-plugin.yml project' 'new-plugin.ps1' @('-Name', 'E2ePaper', '-PaperPlugin', '-Path', (Join-Path $work 'paper'))
    # An old era: plugin.yml commands, legacy color codes, Java 8, paperspigot-api, no api-version.
    Step 'new 1.8.8 project' 'new-plugin.ps1' @('-Name', 'E2eOld', '-Minecraft', '1.8.8', '-Path', (Join-Path $work 'old'))
    Step '-PaperPlugin refused before 1.20.6' 'new-plugin.ps1' @('-Name', 'E2eNo', '-Minecraft', '1.16.5', '-PaperPlugin', '-Path', (Join-Path $work 'no'), '-DryRun') @(1)
    Step 'new Folia project' 'new-plugin.ps1' @('-Name', 'E2eFolia', '-Folia', '-NoTests', '-Path', (Join-Path $work 'folia'))
    Step 'new Velocity project' 'new-plugin.ps1' @('-Name', 'E2eProxy', '-Velocity', '-Path', (Join-Path $work 'proxy'))
    Step 'new Spigot project' 'new-plugin.ps1' @('-Name', 'E2eSpigot', '-Spigot', '-Path', (Join-Path $work 'spigot'))
    Step 'new CraftBukkit 1.12.2 project' 'new-plugin.ps1' @('-Name', 'E2eCb', '-CraftBukkit', '-Minecraft', '1.12.2', '-Path', (Join-Path $work 'cb'))
    Step 'new database project' 'new-plugin.ps1' @('-Name', 'E2eDb', '-Database', '-Path', (Join-Path $work 'db'))
    Step 'new CraftBukkit 1.12.2 database project' 'new-plugin.ps1' @('-Name', 'E2eDbOld', '-Database', '-CraftBukkit', '-Minecraft', '1.12.2', '-Path', (Join-Path $work 'dbold'))
    Step '-Database refused for Velocity' 'new-plugin.ps1' @('-Name', 'E2eDbProxy', '-Database', '-Velocity', '-Path', (Join-Path $work 'dbproxy'), '-DryRun') @(1)
    foreach ($p in @('bukkit', 'paper', 'old', 'folia', 'proxy', 'spigot', 'cb', 'db', 'dbold')) {
        $root = Join-Path $work $p
        Step ('doctor ' + $p) 'doctor.ps1' @('-ProjectRoot', $root)
        Step ('check ' + $p) 'check.ps1' @('-ProjectRoot', $root)
        Step ('build-release ' + $p) 'build-release.ps1' @('-ProjectRoot', $root, '-SkipCheck', '-Tag', 'v0.1.0')
        Step ('update-paper dry run ' + $p) 'update-paper.ps1' @('-ProjectRoot', $root, '-DryRun') @(0, 2)
    }
    Step 'run-server without EULA refuses' 'run-server.ps1' @('-ProjectRoot', (Join-Path $work 'bukkit'), '-NoBuild') @(3)
} finally {
    Pop-Location
    if (-not $KeepFiles) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
if ($failed.Count -gt 0) { Write-Host ('e2e: FAILED: ' + ($failed -join ', ')); exit 1 }
Write-Host 'e2e: OK'
exit 0
