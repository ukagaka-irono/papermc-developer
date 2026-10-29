<#
.SYNOPSIS
  Builds the jar to distribute, inspects it, and writes it with its SHA-256 to build/release/. Uploads nothing.
.DESCRIPTION
  1. scripts/check.ps1 (descriptor, build, tests) unless -SkipCheck.
  2. Inspects the jar: it has plugin.yml / paper-plugin.yml with the version filled in (no "${version}"),
     the main class, and no copy of the server API inside (org/bukkit, io/papermc/paper, net/kyori/adventure:
     shading those breaks the plugin on servers). Lists anything shaded so the user can check its license.
  3. Copies it to build/release/<name>-<version>.jar and writes <jar>.sha256.
  -Tag v1.2.0   also checks that the version matches the tag (with or without "v").
  -ListOnly     only lists the jar's contents.
  Publishing (GitHub Releases, Hangar, Modrinth) is a separate step the user approves:
  references/workflows/release.md.
  Exit codes: 0 / 1 failed / 3 no java or build tool.
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build-release.ps1
#>
param(
    [string]$ProjectRoot,
    [string]$Tag,
    [switch]$SkipCheck,
    [switch]$ListOnly,
    [string]$JavaPath
)
. (Join-Path $PSScriptRoot 'lib/common.ps1')
Initialize-PaperDevConsole
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$project = Resolve-PaperDevProject $ProjectRoot
if (-not $project) { Write-PaperDevStatus 'error' 'no Gradle or Maven project found (pass -ProjectRoot)'; exit 1 }

if (-not $ListOnly -and -not $SkipCheck) {
    & (Join-Path $PSScriptRoot 'check.ps1') -ProjectRoot $project.Root -JavaPath $JavaPath
    $c = $LASTEXITCODE
    if ($c -ne 0) { Write-PaperDevStatus 'error' 'check failed; nothing was released'; exit $c }
}
$jar = Find-PaperDevPluginJar $project
if (-not $jar) { Write-PaperDevStatus 'error' 'no plugin jar in build/libs or target (run scripts/check.ps1)'; exit 1 }

$zip = [System.IO.Compression.ZipFile]::OpenRead($jar)
try {
    $names = @($zip.Entries | ForEach-Object { $_.FullName })
    if ($ListOnly) {
        Write-Host ('jar: ' + $jar + ' (' + $names.Count + ' entries)')
        foreach ($n in $names) { Write-Host ('  ' + $n) }
        exit 0
    }
    $problems = 0
    $descName = $null
    foreach ($n in @('paper-plugin.yml', 'plugin.yml')) { if ($names -contains $n) { $descName = $n; break } }
    $version = $null; $name = $null; $main = $null
    if ($project.Kind -eq 'velocity') {
        # Velocity: velocity-plugin.json, written by the annotation processor from @Plugin.
        if ($names -notcontains 'velocity-plugin.json') { Write-PaperDevStatus 'error' 'the jar has no velocity-plugin.json (annotationProcessor("com.velocitypowered:velocity-api:...") missing? references/velocity.md)'; $problems++ }
        else {
            $reader = New-Object System.IO.StreamReader($zip.GetEntry('velocity-plugin.json').Open(), [System.Text.Encoding]::UTF8)
            try { $json = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
            $version = [string]$json.version; $name = [string]$json.id; $main = [string]$json.main
            if (-not $version) { Write-PaperDevStatus 'error' 'velocity-plugin.json has no version (@Plugin version)'; $problems++ }
            if ($main -and ($names -notcontains (($main -replace '\.', '/') + '.class'))) { Write-PaperDevStatus 'error' ('main class ' + $main + ' is not in the jar'); $problems++ }
        }
    }
    elseif (-not $descName) { Write-PaperDevStatus 'error' 'the jar has no plugin.yml or paper-plugin.yml at its root'; $problems++ }
    else {
        $entry = $zip.GetEntry($descName)
        $reader = New-Object System.IO.StreamReader($entry.Open(), [System.Text.Encoding]::UTF8)
        try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
        $tmp = [System.IO.Path]::GetTempFileName()
        Write-PaperDevText -Path $tmp -Text $text
        $d = Read-PaperDevDescriptor $tmp
        Remove-Item -LiteralPath $tmp -Force
        $version = $d.Values['version']; $name = $d.Values['name']; $main = $d.Values['main']
        if (-not $version -or $version -match '\$\{') { Write-PaperDevStatus 'error' ('the version in ' + $descName + ' was not filled in: "' + $version + '" (processResources expand, references/layout.md)'); $problems++ }
        if ($main -and ($names -notcontains (($main -replace '\.', '/') + '.class'))) { Write-PaperDevStatus 'error' ('main class ' + $main + ' is not in the jar'); $problems++ }
    }
    $apiPrefixes = @('org/bukkit/', 'io/papermc/paper/', 'net/kyori/adventure/', 'com/mojang/brigadier/', 'net/minecraft/', 'com/velocitypowered/', 'com/google/inject/')
    foreach ($p in $apiPrefixes) {
        $hits = @($names | Where-Object { $_.StartsWith($p) -and $_.EndsWith('.class') })
        if ($hits.Count -gt 0) { Write-PaperDevStatus 'error' ($hits.Count.ToString() + ' class(es) under ' + $p + ' are inside the jar: the server provides them; use compileOnly, not implementation'); $problems++ }
    }
    $ownPrefix = $null
    if ($main -and $main -match '^(.+)\.[^.]+$') { $ownPrefix = ($Matches[1] -replace '\.', '/') + '/' }
    $shaded = @{}
    foreach ($n in $names) {
        if (-not $n.EndsWith('.class') -or ($ownPrefix -and $n.StartsWith($ownPrefix)) -or $n -match '^META-INF/') { continue }
        $parts = $n -split '/'
        $key = ($parts[0..([Math]::Min(2, $parts.Count - 2))] -join '/')
        $shaded[$key] = 1 + [int]$shaded[$key]
    }
    if ($shaded.Count -gt 0) {
        Write-PaperDevStatus 'note' 'other code inside the jar (shaded libraries; check that their licenses allow redistribution):'
        foreach ($k in ($shaded.Keys | Sort-Object)) { Write-Host ('          ' + $k + '/ (' + $shaded[$k] + ' classes)') }
    }
} finally { $zip.Dispose() }

if ($Tag -and $version) {
    if ($Tag.TrimStart('v', 'V') -ne $version) { Write-PaperDevStatus 'error' ('version ' + $version + ' does not match the tag ' + $Tag); $problems++ }
}
if ($version -match '(?i)SNAPSHOT') { Write-PaperDevStatus 'warn' ('the version is ' + $version + '; a release usually has a plain version') }
if ($problems -gt 0) { exit 1 }

$outDir = Join-Path $project.Root 'build/release'
if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$outJar = Join-Path $outDir ($name + '-' + $version + '.jar')
Copy-Item -LiteralPath $jar -Destination $outJar -Force
$sha = Get-PaperDevFileSha256 $outJar
Write-PaperDevText -Path ($outJar + '.sha256') -Text ($sha + '  ' + (Split-Path -Leaf $outJar) + "`n")
$size = [Math]::Round((Get-Item -LiteralPath $outJar).Length / 1KB, 1)
Write-PaperDevStatus 'ok' ($outJar + ' (' + $size + ' KB)')
Write-Host ('          sha256 ' + $sha)
exit 0
