<#
.SYNOPSIS
  Checks the plugin: the plugin.yml / paper-plugin.yml, then a full build with the tests.
.DESCRIPTION
  1. The descriptor: name, version, main, api-version; the main class exists in the sources; the
     api-version is not newer than the paper-api the build compiles against; commands used with
     getCommand("x") are declared (plugin.yml) or not used at all (paper-plugin.yml).
  2. The build ("gradlew build", Maven "package"): compiler errors as "file:line: error: message",
     deprecation warnings (the template enables -Xlint:deprecation), and failed tests with their messages.
  -NoTests     builds without running the tests
  -SkipBuild   only the descriptor checks
  -Ci          prints problems as GitHub Actions annotations
  Exit codes: 0 OK / 1 errors / 3 cannot check (no build tool or java).
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/check.ps1
#>
param(
    [string]$ProjectRoot,
    [switch]$NoTests,
    [switch]$SkipBuild,
    [switch]$Ci,
    [int]$MaxWarnings = 15,
    [string]$JavaPath
)
. (Join-Path $PSScriptRoot 'lib/common.ps1')
Initialize-PaperDevConsole

$project = Resolve-PaperDevProject $ProjectRoot
if (-not $project) { Write-PaperDevStatus 'error' 'no Gradle or Maven project found (pass -ProjectRoot)'; exit 1 }

$errors = 0
$warnings = 0
function Report {
    param([string]$Level, [string]$Message, [string]$File, [int]$Line)
    $loc = ''
    if ($File) {
        $rel = $File
        if ($rel.StartsWith($project.Root)) { $rel = $rel.Substring($project.Root.Length).TrimStart('\', '/') }
        $rel = $rel -replace '\\', '/'
        $loc = $rel
        if ($Line -gt 0) { $loc += ':' + $Line }
        $loc += ': '
    }
    if ($Level -eq 'error') { $script:errors++ } elseif ($Level -eq 'warning') { $script:warnings++ }
    if ($Ci) { Write-PaperDevCiAnnotation -Level $Level -Message $Message -File $(if ($File) { $rel } else { '' }) -Line $Line }
    else { Write-PaperDevStatus $Level ($loc + $Message) }
}

# ---------------------------------------------------------------- descriptor
Write-Host ('project: ' + $project.Root)
$versions = Get-PaperDevProjectVersions $project
$sourceRoots = @('src/main/java', 'src/main/kotlin') | ForEach-Object { Join-Path $project.Module $_ }
if ($project.Kind -eq 'velocity') {
    # Velocity: velocity-plugin.json is generated from @Plugin; check the annotation instead of a yml.
    $vp = Get-PaperDevVelocityPlugin $project
    if (-not $vp) { Report 'error' 'no class with the @Plugin annotation (com.velocitypowered.api.plugin.Plugin) in src/main/java' }
    else {
        if (-not $vp.Id) { Report 'error' '@Plugin has no id' $vp.File $vp.Line }
        elseif ($vp.Id -notmatch '^[a-z][a-z0-9_-]{0,63}$') { Report 'error' ('@Plugin id "' + $vp.Id + '" is invalid: lowercase letters, digits, - and _, starting with a letter, at most 64') $vp.File $vp.Line }
        if (-not $vp.Version) { Report 'warning' '@Plugin has no version (the proxy shows none)' $vp.File $vp.Line }
        if ($errors -eq 0) { Write-PaperDevStatus 'ok' ('@Plugin: id ' + $vp.Id + ', main ' + $vp.Main + $(if ($versions.Velocity) { ', builds against Velocity ' + $versions.Velocity } else { '' })) }
    }
    $buildText = (Get-PaperDevBuildFiles $project | ForEach-Object { Read-PaperDevText $_ }) -join "`n"
    if ($project.BuildTool -eq 'gradle' -and $buildText -notmatch 'annotationProcessor[^\r\n]*velocity-api') {
        Report 'warning' 'no annotationProcessor("com.velocitypowered:velocity-api:...") in the build: velocity-plugin.json is not generated unless it is written by hand (references/velocity.md)'
    }
} elseif (-not $project.Descriptor) {
    Report 'error' 'no src/main/resources/plugin.yml or paper-plugin.yml'
} else {
    $d = Read-PaperDevDescriptor $project.Descriptor
    $file = $project.Descriptor
    foreach ($k in @('name', 'version', 'main')) {
        if (-not $d.Values[$k]) { Report 'error' ('"' + $k + '" is missing') $file 0 }
    }
    $name = $d.Values['name']
    if ($name -and $name -notmatch '^[A-Za-z0-9_.-]+$') { Report 'error' ('the name "' + $name + '" may use only A-Z a-z 0-9 _ . -') $file $d.Lines['name'] }
    $api = $d.Values['api-version']
    # api-version exists from 1.13; servers before 1.20.5 accept only "1.<minor>" (anything else: "Unsupported API version").
    $targetHasApi = (-not $versions.Minecraft) -or (Test-PaperDevVersionAtLeast $versions.Minecraft '1.13')
    if (-not $api) {
        if ($project.Kind -eq 'paper') { Report 'error' 'api-version is required in paper-plugin.yml' $file 0 }
        elseif ($targetHasApi) { Report 'warning' 'no api-version: the server loads the plugin in legacy mode (slow, old material names)' $file 0 }
    } elseif ($versions.Minecraft) {
        if (-not $targetHasApi) {
            Report 'notice' ('api-version is ignored by ' + $versions.Minecraft + ' (it exists from 1.13); keep it only if the plugin also targets 1.13+') $file $d.Lines['api-version']
        } elseif ((ConvertTo-PaperDevVersion $api) -gt (ConvertTo-PaperDevVersion $versions.Minecraft)) {
            Report 'error' ('api-version ' + $api + ' is newer than the API the build uses (' + $versions.Minecraft + ')') $file $d.Lines['api-version']
        }
        if ($api -match '^1\.\d+\.\d+' -and -not (Test-PaperDevVersionAtLeast $api '1.20.5')) {
            Report 'error' ('api-version ' + $api + ': servers before 1.20.5 accept only "1.<minor>" (write ' + ($api -replace '^(1\.\d+)\..*$', '$1') + ')') $file $d.Lines['api-version']
        }
    }
    $main = $d.Values['main']
    if ($main -and $main -notmatch '\$\{') {
        $relMain = $main -replace '\.', '/'
        $found = $false
        foreach ($r in $sourceRoots) { foreach ($ext in @('.java', '.kt')) { if (Test-Path -LiteralPath (Join-Path $r ($relMain + $ext))) { $found = $true } } }
        if (-not $found) { Report 'error' ('main class ' + $main + ' is not in src/main/java or src/main/kotlin') $file $d.Lines['main'] }
    }
    foreach ($k in @('bootstrapper', 'loader')) {
        $cls = $d.Values[$k]
        if ($cls) {
            if ($project.Kind -ne 'paper') { Report 'warning' ('"' + $k + '" only works in paper-plugin.yml') $file $d.Lines[$k] }
            $relCls = $cls -replace '\.', '/'
            $found = $false
            foreach ($r in $sourceRoots) { foreach ($ext in @('.java', '.kt')) { if (Test-Path -LiteralPath (Join-Path $r ($relCls + $ext))) { $found = $true } } }
            if (-not $found) { Report 'error' ($k + ' class ' + $cls + ' is not in the sources') $file $d.Lines[$k] }
        }
    }
    # getCommand("x") needs "commands: x:" in plugin.yml, and does not work at all with paper-plugin.yml.
    foreach ($r in $sourceRoots) {
        if (-not (Test-Path -LiteralPath $r)) { continue }
        foreach ($src in (Get-ChildItem -LiteralPath $r -Recurse -File -Include '*.java', '*.kt')) {
            $lineNo = 0
            foreach ($line in (Read-PaperDevText $src.FullName) -split "`r?`n") {
                $lineNo++
                foreach ($m in [regex]::Matches($line, 'getCommand\(\s*"([^"]+)"\s*\)')) {
                    $cmd = $m.Groups[1].Value
                    if ($project.Kind -eq 'paper') { Report 'error' ('getCommand("' + $cmd + '") returns null in a Paper plugin; register the command with the lifecycle API (references/paper-api.md)') $src.FullName $lineNo }
                    elseif ($d.Commands -notcontains $cmd) { Report 'error' ('getCommand("' + $cmd + '") but "' + $cmd + '" is not under commands: in plugin.yml (it returns null)') $src.FullName $lineNo }
                }
            }
        }
    }
    # Folia: a plugin that declares folia-supported must not use the BukkitScheduler (it throws on Folia).
    $foliaDeclared = ($d.Values['folia-supported'] -eq 'true')
    if ($foliaDeclared -or $versions.Platform -eq 'folia') {
        if (-not $foliaDeclared) { Report 'error' 'the build uses folia-api but the descriptor has no "folia-supported: true" (Folia refuses to load the plugin)' $file 0 }
        $foliaRules = @(
            # Only the server's scheduler: entity.getScheduler() is Folia's EntityScheduler and is right.
            @{ Pattern = '(?:getServer\(\)|\bBukkit|\bserver)\s*\.\s*getScheduler\(\)|\bBukkitScheduler\b'; Level = 'error'; Text = 'the BukkitScheduler does not work on Folia (UnsupportedOperationException); use getGlobalRegionScheduler(), getRegionScheduler(), entity.getScheduler() or getAsyncScheduler()' }
            @{ Pattern = '\bBukkitRunnable\b'; Level = 'error'; Text = 'BukkitRunnable runs on the BukkitScheduler, which does not work on Folia; use the region-aware schedulers' }
            @{ Pattern = '\.teleport\(\s*[^)]'; Level = 'warning'; Text = 'teleport() blocks and may cross regions on Folia; use teleportAsync()' }
        )
        foreach ($r in $sourceRoots) {
            if (-not (Test-Path -LiteralPath $r)) { continue }
            foreach ($src in (Get-ChildItem -LiteralPath $r -Recurse -File -Include '*.java', '*.kt')) {
                $lineNo = 0
                foreach ($line in (Read-PaperDevText $src.FullName) -split "`r?`n") {
                    $lineNo++
                    if ($line -match '^\s*(//|\*|/\*)') { continue }
                    foreach ($rule in $foliaRules) { if ($line -match $rule.Pattern) { Report $rule.Level ('Folia: ' + $rule.Text) $src.FullName $lineNo } }
                }
            }
        }
    }
    if ($errors -eq 0) { Write-PaperDevStatus 'ok' ('descriptor ' + (Split-Path -Leaf $file) + ': ' + $name + ' ' + $d.Values['version'] + $(if ($api) { ', api-version ' + $api } else { '' }) + $(if ($versions.Minecraft) { ', builds against ' + $versions.Minecraft } else { '' })) }
}

if ($SkipBuild) {
    if ($errors -gt 0) { exit 1 }
    exit 0
}

# ---------------------------------------------------------------- build
$java = Get-PaperDevJava $JavaPath
if (-not $java) { Write-PaperDevStatus 'skipped' 'build: java not found (scripts/doctor.ps1)'; exit 3 }
$javaHome = Split-Path -Parent (Split-Path -Parent $java.Path)
$tasks = @('build')
$extra = @()
if ($NoTests) {
    if ($project.BuildTool -eq 'maven') { $extra += '-DskipTests' } else { $extra += @('-x', 'test') }
}
Write-Host ('build: ' + $project.BuildTool + ' ' + ($tasks + $extra -join ' ') + ' (java ' + $java.Version + ')')
$started = Get-Date
$r = Invoke-PaperDevBuild -Project $project -Tasks $tasks -Extra $extra -JavaHome $javaHome
if (-not $r) { Write-PaperDevStatus 'skipped' 'build: no gradlew / gradle (or mvnw / mvn) found (scripts/doctor.ps1)'; exit 3 }
$output = $r.StdOut + "`n" + $r.StdErr
$seconds = [Math]::Round(((Get-Date) - $started).TotalSeconds)

$messages = @(Get-PaperDevCompilerMessages $output)
$compileErrors = @($messages | Where-Object { $_.Level -eq 'error' })
$compileWarnings = @($messages | Where-Object { $_.Level -eq 'warning' })
foreach ($m in $compileErrors) {
    Report 'error' $m.Message $m.File $m.Line
    if (-not $Ci) { foreach ($c in $m.Context) { Write-Host ('          ' + $c) } }
}
$shown = 0
foreach ($m in $compileWarnings) {
    if ($shown -ge $MaxWarnings) { break }
    Report 'warning' $m.Message $m.File $m.Line
    $shown++
}
if ($compileWarnings.Count -gt $shown) { Write-Host ('          ... ' + ($compileWarnings.Count - $shown) + ' more warning(s)') }

$tests = Get-PaperDevTestResults $project
if (-not $NoTests -and $tests.Found) {
    foreach ($f in $tests.Failures) {
        Report 'error' ('test failed: ' + $f.Name + ' - ' + $f.Message)
        if (-not $Ci) { foreach ($l in ($f.Detail -split "`n" | Select-Object -Skip 1 -First 6)) { Write-Host ('          ' + $l) } }
    }
}

if ($r.ExitCode -ne 0) {
    if ($compileErrors.Count -eq 0 -and $tests.Failures.Count -eq 0) {
        # Not a compiler or test failure: show the build tool's own explanation.
        $lines = @($output -split "`r?`n")
        $start = -1
        for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^(\* What went wrong:|FAILURE:|\[ERROR\] Failed)') { $start = $i; break } }
        if ($start -lt 0) { $start = [Math]::Max(0, $lines.Count - 40) }
        $tail = @($lines[$start..([Math]::Min($lines.Count - 1, $start + 30))] | Where-Object { $_ -notmatch '^\* (Try|Get more help)' })
        Report 'error' ('build failed (exit ' + $r.ExitCode + ')')
        foreach ($l in $tail) { Write-Host ('          ' + $l) }
    }
    Write-Host ('build: FAILED in ' + $seconds + 's')
    exit 1
}

$jar = Find-PaperDevPluginJar $project
$summary = 'build: OK in ' + $seconds + 's'
if (-not $NoTests -and $tests.Found) { $summary += ', tests ' + ($tests.Total - $tests.Failures.Count - $tests.Skipped) + ' passed' + $(if ($tests.Skipped) { ', ' + $tests.Skipped + ' skipped' } else { '' }) }
elseif (-not $NoTests) { $summary += ', no tests' }
if ($compileWarnings.Count) { $summary += ', ' + $compileWarnings.Count + ' compiler warning(s)' }
if ($jar) { $summary += ' -> ' + $jar }
Write-Host $summary
if ($errors -gt 0) { exit 1 }
exit 0
