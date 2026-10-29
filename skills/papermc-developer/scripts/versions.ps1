<#
.SYNOPSIS
  Shows the versions the project uses next to the latest ones. Changes nothing.
.DESCRIPTION
  Looks up, at run time, the latest stable Minecraft version on Paper (Fill API), its latest build and the
  Java it needs, the newest paper-api build, MockBukkit, Gradle, and the Gradle plugins the templates use.
  Facts that change are never written in the skill's documents; ask this script.
  -Minecraft <version>  look at that version instead of the latest.
  -List                 also list the recent Minecraft versions and their support status.
  Exit codes: 0 / 1 lookup failed.
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/versions.ps1
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/versions.ps1 -Minecraft 1.21.11 -Json
#>
param(
    [string]$ProjectRoot,
    [string]$Minecraft,
    [switch]$List,
    [switch]$Json
)
. (Join-Path $PSScriptRoot 'lib/common.ps1')
Initialize-PaperDevConsole

try {
    $project = Resolve-PaperDevProject $ProjectRoot
    $current = $null
    if ($project) { $current = Get-PaperDevProjectVersions $project }
    $latestStable = Get-PaperDevLatestMinecraft
    $mc = $Minecraft
    if (-not $mc) { $mc = $latestStable }
    $info = Get-PaperDevVersionInfo -Minecraft $mc
    $build = Get-PaperDevLatestBuild -Minecraft $mc
    $api = Get-PaperDevLatestApiBuild -Minecraft $mc
    $era = Get-PaperDevEra -Minecraft $mc -JavaMinimum ([int]$info.JavaMinimum)
    $dep = Get-PaperDevApiDependency $mc
    $mock = $null
    try { $mock = Get-PaperDevMockBukkit -Minecraft $mc } catch { }
    $gradle = $null
    try { $gradle = (Get-PaperDevGradleCurrent).Version } catch { }
    $plugins = [ordered]@{}
    foreach ($id in @('xyz.jpenilla.run-paper', 'com.gradleup.shadow', 'io.papermc.paperweight.userdev', 'org.gradle.toolchains.foojay-resolver-convention', 'io.papermc.hangar-publish-plugin', 'com.modrinth.minotaur')) {
        try { $plugins[$id] = Get-PaperDevGradlePluginVersion $id } catch { $plugins[$id] = $null }
    }
    $recent = @()
    $all = @()
    if ($List) {
        $all = @(Get-PaperDevMinecraftVersions | Where-Object { -not (Test-PaperDevPreRelease $_) })
        foreach ($v in ($all | Select-Object -First 8)) {
            $vi = Get-PaperDevVersionInfo -Minecraft $v
            $recent += [PSCustomObject]@{ version = $v; support = $vi.Support; java = $vi.JavaMinimum }
        }
    }
    $folia = $null
    try { if ((Get-PaperDevMinecraftVersions 'folia') -contains $mc) { $folia = $mc } } catch { }

    $result = [PSCustomObject]@{
        latestStableMinecraft = $latestStable
        minecraft = $mc
        support = $info.Support
        javaMinimum = $info.JavaMinimum
        paperBuild = $build.Build
        paperChannel = $build.Channel
        apiDependency = $dep.Coordinate
        javaPreferred = $era.JavaPreferred
        javaMaximum = $(if ($era.JavaMax -ge 99) { $null } else { $era.JavaMax })
        commands = $(if ($era.Brigadier) { "brigadier" } else { "plugin.yml" })
        text = $(if ($era.MiniMessage) { "minimessage" } else { "legacy" })
        paperPluginYml = $era.PaperPlugin
        paperApiLatest = $api
        apiVersionField = (Get-PaperDevApiVersionField $mc)
        foliaAvailable = [bool]$folia
        mockbukkit = $(if ($mock) { 'org.mockbukkit.mockbukkit:' + $mock.Artifact + ':' + $mock.Version } else { $null })
        gradle = $gradle
        gradlePlugins = $plugins
        project = $(if ($current) { [PSCustomObject]@{ root = $project.Root; paperApi = $current.PaperApi; minecraft = $current.Minecraft; java = $current.Java; runPaper = $current.RunPaper; mockbukkit = $current.MockBukkit; platform = $current.Platform } } else { $null })
        recent = $recent
        allVersions = $all
    }
    if ($Json) { Write-Output ($result | ConvertTo-Json -Depth 6); exit 0 }

    Write-Host ('latest stable Minecraft on Paper: ' + $latestStable)
    Write-Host ('looking at:          ' + $mc + ' (' + $info.Support + ')')
    Write-Host ('  Java:              ' + (Format-PaperDevJavaRange $era) + ' (builds and runs on ' + $era.JavaPreferred + ' by default)')
    Write-Host ('  commands:          ' + $(if ($era.Brigadier) { 'Brigadier (lifecycle API)' } else { 'plugin.yml commands: + CommandExecutor' }))
    Write-Host ('  text:              ' + $(if ($era.MiniMessage) { 'Adventure + MiniMessage' } else { 'legacy color codes (ChatColor)' }))
    Write-Host ('  Paper build:       ' + $build.Build + ' (' + $build.Channel + ')')
    Write-Host ('  API:               compileOnly("' + $dep.Coordinate + '")' + $(if ($api) { '   found: ' + $api } else { '   NOT FOUND in the Paper repository' }))
    Write-Host ('  api-version:       ' + $(if ($era.ApiVersion) { Get-PaperDevApiVersionField $mc } else { '(none before 1.13)' }))
    Write-Host ('  paper-plugin.yml:  ' + $(if ($era.PaperPlugin) { 'yes' } else { 'no (plugin.yml only)' }))
    Write-Host ('  Folia:             ' + $(if ($folia) { 'available' } else { 'no build for this version' }))
    Write-Host ('  MockBukkit:        ' + $(if ($mock) { 'org.mockbukkit.mockbukkit:' + $mock.Artifact + ':' + $mock.Version } else { 'none for this version yet' }))
    Write-Host ('gradle:              ' + $gradle)
    foreach ($k in $plugins.Keys) { Write-Host ('  ' + $k.PadRight(50) + $plugins[$k]) }
    if ($current) {
        Write-Host ''
        Write-Host ('project: ' + $project.Root)
        Write-Host ('  paper-api:   ' + $current.PaperApi + $(if ($current.Platform -eq 'folia') { ' (folia-api)' } else { '' }))
        Write-Host ('  minecraft:   ' + $current.Minecraft)
        Write-Host ('  java:        ' + $current.Java)
        Write-Host ('  run-paper:   ' + $current.RunPaper)
        Write-Host ('  mockbukkit:  ' + $current.MockBukkit)
        if ($current.Minecraft -and $current.Minecraft -ne $latestStable) { Write-PaperDevStatus 'note' ('the project targets ' + $current.Minecraft + '; the latest stable is ' + $latestStable + ' (references/workflows/update-paper.md)') }
    }
    if ($recent.Count -gt 0) {
        Write-Host ''
        Write-Host 'recent versions:'
        foreach ($r in $recent) { Write-Host ('  ' + $r.version.PadRight(14) + ([string]$r.support).PadRight(14) + 'java ' + $r.java) }
        Write-Host ('all ' + $all.Count + ' released versions (any of them works with -Minecraft):')
        Write-Host ('  ' + ($all -join ' '))
    }
    exit 0
} catch {
    Write-PaperDevStatus 'error' ('lookup failed: ' + $_.Exception.Message)
    exit 1
}
