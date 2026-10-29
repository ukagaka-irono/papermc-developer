<#
.SYNOPSIS
  Prepares the home folder: records the user's choices and downloads what the other scripts use.
.DESCRIPTION
  -AcceptEula   records that the USER agreed to the Minecraft EULA (https://aka.ms/MinecraftEULA).
                The test server does not start without it. Pass it only after the user said they agree.
  -JavaPath     records a java (a java executable or a JDK folder) in local.json: as the java that runs Gradle when
                it is 17 or newer, and in any case as the JDK of its version for test servers.
  -Jdk <n>      makes sure a JDK of version n (8, 11, 17, 21, 25 ...) is there for test servers; when none is installed,
                downloads Eclipse Temurin n (about 100-200 MB) into the home folder. Ask the user before downloading.
  -Minecraft    downloads the Paper server jar of that version (default: the project's version, else the latest stable).
  -Gradle       downloads the current Gradle distribution (used to create the wrapper of new projects).
  Without switches it downloads the server jar for the project and shows the doctor result.
  Everything goes to the home folder (%LOCALAPPDATA%\papermc-developer, or PAPERMCDEV_HOME), never into the project.
  Exit codes: 0 / 1 failed or a required item is missing.
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/setup.ps1
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/setup.ps1 -AcceptEula
#>
param(
    [string]$ProjectRoot,
    [switch]$AcceptEula,
    [string]$JavaPath,
    [int[]]$Jdk = @(),
    [string]$Minecraft,
    [switch]$Gradle,
    [switch]$NoDownload
)
. (Join-Path $PSScriptRoot 'lib/common.ps1')
Initialize-PaperDevConsole

$failed = $false

if ($AcceptEula) {
    Set-PaperDevLocalConfig 'eulaAccepted' $true
    Set-PaperDevLocalConfig 'eulaAcceptedAt' ((Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK'))
    Write-PaperDevStatus 'ok' ('recorded the agreement to the Minecraft EULA (' + $PaperDevEulaUrl + ') in local.json')
}

if ($JavaPath) {
    $j = Get-PaperDevJava $JavaPath
    if ($j) {
        if ($j.Major -ge 17) { Set-PaperDevLocalConfig 'javaPath' $j.Path }
        $jdks = (Get-PaperDevLocalConfig).PSObject.Properties['jdks']
        $map = New-Object PSObject
        if ($jdks -and $jdks.Value) { $map = $jdks.Value }
        $jdkHome = Split-Path -Parent (Split-Path -Parent $j.Path)
        if ($map.PSObject.Properties[[string]$j.Major]) { $map.([string]$j.Major) = $jdkHome } else { $map | Add-Member -NotePropertyName ([string]$j.Major) -NotePropertyValue $jdkHome }
        Set-PaperDevLocalConfig 'jdks' $map
        Write-PaperDevStatus 'ok' ('java ' + $j.Major + ': ' + $j.Version + ' at ' + $j.Path + $(if ($j.Major -ge 17) { ' (also runs Gradle)' } else { ' (for test servers)' }))
    } else {
        Write-PaperDevStatus 'error' ('not a working java: ' + $JavaPath)
        $failed = $true
    }
}

foreach ($major in $Jdk) {
    $found = @(Find-PaperDevJdks | Where-Object { $_.Major -eq $major }) | Select-Object -First 1
    if ($found) { Write-PaperDevStatus 'ok' ('JDK ' + $major + ': ' + $found.Home); continue }
    if ($NoDownload) { Write-PaperDevStatus 'missing' ('JDK ' + $major + ' is not installed'); $failed = $true; continue }
    try {
        $installed = Install-PaperDevJdk -Major $major
        Write-PaperDevStatus 'ok' ('JDK ' + $major + ': installed Eclipse Temurin at ' + $installed)
    } catch {
        Write-PaperDevStatus 'error' ('could not install JDK ' + $major + ': ' + $_.Exception.Message)
        $failed = $true
    }
}

if (-not $NoDownload) {
    $project = Resolve-PaperDevProject $ProjectRoot
    $mc = $Minecraft
    $platform = 'paper'
    if (-not $mc -and $project) {
        $v = Get-PaperDevProjectVersions $project
        $mc = $v.Minecraft
        if ($v.Platform -eq 'folia') { $platform = 'folia' }
    }
    try {
        if (-not $mc) { $mc = Get-PaperDevLatestMinecraft }
        $jar = Get-PaperDevServerJar -Minecraft $mc -Project $platform
        Write-PaperDevStatus 'ok' ($platform + ' server ' + $mc + ' build ' + $jar.Build.Build + ': ' + $jar.Path)
    } catch {
        Write-PaperDevStatus 'error' ('could not get the server jar: ' + $_.Exception.Message)
        $failed = $true
    }
    if ($Gradle) {
        try {
            $g = Get-PaperDevGradleDistribution
            Write-PaperDevStatus 'ok' ('gradle: ' + $g)
        } catch {
            Write-PaperDevStatus 'error' ('could not get Gradle: ' + $_.Exception.Message)
            $failed = $true
        }
    }
}

Write-Host ''
& (Join-Path $PSScriptRoot 'doctor.ps1') -ProjectRoot $ProjectRoot
$doctorExit = $LASTEXITCODE
if ($failed -or $doctorExit -ne 0) { exit 1 }
exit 0
