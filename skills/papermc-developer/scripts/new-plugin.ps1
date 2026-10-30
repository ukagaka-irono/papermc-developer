<#
.SYNOPSIS
  Creates a new Paper plugin project (Gradle, Kotlin DSL, Java) from the skill's templates.
.DESCRIPTION
  Versions are looked up at run time: the latest stable Minecraft on Paper (or -Minecraft), the Java it
  needs, paper-api, run-paper, MockBukkit, JUnit, the foojay toolchain resolver and Gradle.
  The project gets: build files, a main class with a Brigadier command (/hello) and a join listener,
  config.yml, plugin.yml (or paper-plugin.yml with -PaperPlugin), a MockBukkit test (unless -NoTests),
  PLUGIN.md / AGENTS.md / CLAUDE.md, .gitignore, .gitattributes, .editorconfig, and the Gradle wrapper
  (Gradle is downloaded once into the home folder). Existing files are never overwritten.
  -Path       the project folder (default: the working folder if it has no project in it and is empty
              apart from .git/.idea, else a new folder named after the plugin)
  -Minecraft  the Paper version, 1.7.10 or later (default: the latest stable)
  -Folia      also for Folia: "folia-supported: true" (Folia has builds from 1.19.4)
  -Velocity   a Velocity (proxy) plugin instead: @Plugin annotation, Brigadier /hello on the proxy, a join
              message; -VelocityVersion picks the Velocity API (default: the latest stable). No tests.
  -Spigot / -CraftBukkit  a plugin for Spigot / CraftBukkit servers (it also runs on Paper): Bukkit API only,
              spigot-api (org.bukkit:bukkit for CraftBukkit up to 1.15.2), plugin.yml commands, legacy color codes,
              no tests. -Minecraft 1.8 or later (default: the newest version BuildTools can build).
  -Database   a database layer: Database.java (SQLite by default, MySQL by config.yml), queries on their own
              thread, /hello counts per sender in the table hello_counts, a JUnit test on SQLite. Not for -Velocity.
  -Workflow   also creates .github/workflows/check.yml and release.yml
  -WrapperOnly only adds the Gradle wrapper to an existing project
  -DryRun     shows what would be created
  Exit codes: 0 / 1 failed / 3 no java to run Gradle.
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/new-plugin.ps1 -Name SleepVote -Description "Skip the night by vote"
#>
param(
    [string]$Name,
    [string]$Path,
    [string]$Package,
    [string]$Description = 'A Paper plugin',
    [string]$Author,
    [string]$Minecraft,
    [switch]$PaperPlugin,
    [switch]$Folia,
    [switch]$Velocity,
    [string]$VelocityVersion,
    [switch]$Spigot,
    [switch]$Database,
    [switch]$CraftBukkit,
    [switch]$NoTests,
    [switch]$Workflow,
    [switch]$NoWrapper,
    [switch]$WrapperOnly,
    [string]$JavaPath,
    [switch]$DryRun
)
. (Join-Path $PSScriptRoot 'lib/common.ps1')
. (Join-Path $PSScriptRoot 'lib/templates.ps1')
Initialize-PaperDevConsole

function Invoke-Wrapper {
    param([string]$Dir, $Java)
    $gradle = Get-PaperDevGradleDistribution
    $version = (Split-Path -Leaf (Split-Path -Parent (Split-Path -Parent $gradle))) -replace '^gradle-', ''
    $envs = @{ 'JAVA_HOME' = (Split-Path -Parent (Split-Path -Parent $Java.Path)) }
    Write-Host ('creating the Gradle wrapper (' + $version + ')')
    $r = Invoke-PaperDevDetachedProcess -FilePath $gradle -Arguments @('--console=plain', '-q', 'wrapper', '--gradle-version', $version, '--distribution-type', 'bin') -WorkingDirectory $Dir -Environment $envs
    if ($r.ExitCode -ne 0) {
        Write-Host $r.StdOut
        Write-Host $r.StdErr
        throw 'gradle wrapper failed'
    }
}

$java = Get-PaperDevJava $JavaPath
if (-not $java -or $java.Major -lt 17) {
    Write-PaperDevStatus 'missing' 'Gradle needs Java 17 or newer to run (scripts/doctor.ps1 shows how to install it)'
    if (-not $DryRun) { exit 3 }
}

if ($WrapperOnly) {
    $project = Resolve-PaperDevProject $Path
    if (-not $project) { Write-PaperDevStatus 'error' 'no Gradle project found'; exit 1 }
    if ($DryRun) { Write-PaperDevStatus 'plan' ('would create the Gradle wrapper in ' + $project.Root); exit 0 }
    try { Invoke-Wrapper -Dir $project.Root -Java $java } catch { Write-PaperDevStatus 'error' $_.Exception.Message; exit 1 }
    Write-PaperDevStatus 'ok' ('gradle wrapper created in ' + $project.Root)
    exit 0
}

if (-not $Name) { Write-PaperDevStatus 'error' '-Name is required (the plugin name, e.g. SleepVote)'; exit 1 }
if ($Name -notmatch '^[A-Za-z0-9_.-]+$') { Write-PaperDevStatus 'error' ('plugin names may use only A-Z a-z 0-9 _ . - (got "' + $Name + '")'); exit 1 }

# Where to create it
$cwd = (Get-Location).Path
if (-not $Path) {
    $entries = @(Get-ChildItem -LiteralPath $cwd -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin @('.git', '.idea', '.gitignore', '.gitattributes', 'README.md', 'LICENSE', '.claude', '.agents') })
    if ($entries.Count -eq 0 -and -not (Test-PaperDevBuildRoot $cwd)) { $Path = $cwd }
    else { $Path = Join-Path $cwd (ConvertTo-PaperDevKebab $Name) }
}
if (-not [System.IO.Path]::IsPathRooted($Path)) { $Path = Join-Path $cwd $Path }
if ((Test-Path -LiteralPath $Path) -and (Test-PaperDevBuildRoot $Path)) {
    Write-PaperDevStatus 'error' ('a build already exists in ' + $Path + ' (use scripts/init-plugin.ps1 to add the starter files to it)')
    exit 1
}

# Names
$mainClass = ConvertTo-PaperDevIdentifier $Name
$projectName = ConvertTo-PaperDevKebab $Name
$permPrefix = ConvertTo-PaperDevPackageSegment $Name
if (-not $Author) {
    $git = Get-Command git -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($git) {
        $r = Invoke-PaperDevProcess -FilePath $git.Source -Arguments @('config', 'user.name')
        if ($r.ExitCode -eq 0) { $Author = $r.StdOut.Trim() }
    }
}
if (-not $Package) {
    $owner = $null
    if ($Author) { $owner = ConvertTo-PaperDevPackageSegment $Author }
    if ($owner -and $owner -ne 'plugin') { $Package = 'io.github.' + $owner + '.' + $permPrefix }
    else { $Package = 'com.example.' + $permPrefix }
}
if ($Package -notmatch '^[a-z_][a-z0-9_]*(\.[a-z_][a-z0-9_]*)+$') { Write-PaperDevStatus 'error' ('not a valid package name: ' + $Package + ' (lowercase, dot separated)'); exit 1 }

if ($Velocity -and $Database) { Write-PaperDevStatus 'error' '-Database is for Paper / Spigot / CraftBukkit plugins (Velocity ships no JDBC drivers: references/database.md)'; exit 1 }
if ($Velocity -and ($PaperPlugin -or $Folia)) { Write-PaperDevStatus 'error' '-Velocity cannot be combined with -PaperPlugin or -Folia (a proxy plugin is a different kind of plugin)'; exit 1 }
$velocityId = ConvertTo-PaperDevKebab $Name
if ($Velocity -and $velocityId -notmatch '^[a-z][a-z0-9_-]{0,63}$') { Write-PaperDevStatus 'error' ('cannot make a Velocity plugin id from "' + $Name + '" (it must start with a letter)'); exit 1 }
$foojay = $null

# Versions, looked up now
if ($Velocity) {
    try {
        if (-not $VelocityVersion) { $VelocityVersion = Get-PaperDevLatestVelocity }
        if ((Get-PaperDevMinecraftVersions 'velocity') -notcontains $VelocityVersion) { Write-PaperDevStatus 'error' ('Velocity has no version ' + $VelocityVersion); exit 1 }
        $vinfo = Get-PaperDevVersionInfo -Minecraft $VelocityVersion -Project 'velocity'
        $javaVersion = [int]$vinfo.JavaMinimum
        if ($javaVersion -lt 17) { $javaVersion = 17 }
        $era = [PSCustomObject]@{ JavaMin = $javaVersion; JavaMax = 99; JavaPreferred = $javaVersion }
        $apiDependency = [PSCustomObject]@{ Coordinate = ('com.velocitypowered:velocity-api:' + $VelocityVersion) }
        $runVelocity = Get-PaperDevGradlePluginVersion 'xyz.jpenilla.run-velocity'
        $foojay = Get-PaperDevGradlePluginVersion 'org.gradle.toolchains.foojay-resolver-convention'
    } catch {
        Write-PaperDevStatus 'error' ('version lookup failed (network?): ' + $_.Exception.Message)
        exit 1
    }
    $NoTests = $true
    $Minecraft = $VelocityVersion
}
# Spigot / CraftBukkit: Bukkit API only (plugin.yml commands, legacy color codes), spigot-api or bukkit, no tests.
$bukkitPlatform = $null
if ($Spigot) { $bukkitPlatform = 'spigot' }
if ($CraftBukkit) { $bukkitPlatform = 'craftbukkit' }
if ($Spigot -and $CraftBukkit) { Write-PaperDevStatus 'error' 'choose one of -Spigot and -CraftBukkit'; exit 1 }
if ($bukkitPlatform -and ($Velocity -or $Folia -or $PaperPlugin)) { Write-PaperDevStatus 'error' ('-' + $bukkitPlatform + ' cannot be combined with -Velocity, -Folia or -PaperPlugin'); exit 1 }
if ($bukkitPlatform) {
    try {
        $spigotVersions = Get-PaperDevSpigotVersions
        if (-not $Minecraft) { $Minecraft = $spigotVersions[0] }
        if ($spigotVersions -notcontains $Minecraft) { Write-PaperDevStatus 'error' ('BuildTools cannot build ' + $Minecraft + ' (Spigot and CraftBukkit: 1.8 and later; scripts/versions.ps1 -List)'); exit 1 }
        $sj = Get-PaperDevSpigotJava $Minecraft
        $era = Get-PaperDevEra -Minecraft $Minecraft -JavaMinimum $sj.JavaMin
        $era.JavaMin = $sj.JavaMin; $era.JavaMax = $sj.JavaMax; $era.JavaPreferred = $sj.JavaPreferred
        $era.Brigadier = $false; $era.MiniMessage = $false; $era.PaperPlugin = $false
        $javaVersion = $era.JavaPreferred
        $apiDependency = Get-PaperDevApiDependency -Minecraft $Minecraft -Platform $bukkitPlatform
        if (-not (Get-PaperDevLatestApiBuild -Minecraft $Minecraft -Platform $bukkitPlatform)) {
            if ($bukkitPlatform -eq 'craftbukkit' -and $apiDependency.Artifact -eq 'bukkit') {
                $apiDependency = Get-PaperDevApiDependency -Minecraft $Minecraft -Platform 'spigot'
                Write-PaperDevStatus 'note' ('org.bukkit:bukkit has no ' + $Minecraft + '; compiling against spigot-api (use only the Bukkit part of it)')
            }
            if (-not (Get-PaperDevLatestApiBuild -Minecraft $Minecraft -Platform 'spigot')) { Write-PaperDevStatus 'warn' ($apiDependency.Coordinate + ' was not found in the Spigot repository; the build may fail') }
        }
        $foojay = Get-PaperDevGradlePluginVersion 'org.gradle.toolchains.foojay-resolver-convention'
    } catch {
        Write-PaperDevStatus 'error' ('version lookup failed (network?): ' + $_.Exception.Message)
        exit 1
    }
    $NoTests = $true
}
if (-not $Velocity -and -not $bukkitPlatform) {
try {
    if (-not $Minecraft) { $Minecraft = Get-PaperDevLatestMinecraft }
    if (-not (Test-PaperDevVersionAtLeast $Minecraft '1.7.10')) { Write-PaperDevStatus 'error' ('Paper versions before 1.7.10 are not supported (got ' + $Minecraft + ')'); exit 1 }
    if ((Get-PaperDevMinecraftVersions) -notcontains $Minecraft) { Write-PaperDevStatus 'error' ('Paper has no version ' + $Minecraft + ' (scripts/versions.ps1 -List shows them)'); exit 1 }
    $info = Get-PaperDevVersionInfo -Minecraft $Minecraft
    $era = Get-PaperDevEra -Minecraft $Minecraft -JavaMinimum ([int]$info.JavaMinimum)
    $javaVersion = $era.JavaPreferred
    $apiDependency = Get-PaperDevApiDependency $Minecraft
    if (-not (Get-PaperDevLatestApiBuild $Minecraft)) { Write-PaperDevStatus 'warn' ($apiDependency.Coordinate + ' was not found in the Paper repository; the build may fail') }
    $runPaper = Get-PaperDevGradlePluginVersion 'xyz.jpenilla.run-paper'
    $foojay = Get-PaperDevGradlePluginVersion 'org.gradle.toolchains.foojay-resolver-convention'
    $mock = $null
    $junit = $null
    if ($PaperPlugin -and -not $era.PaperPlugin) {
        Write-PaperDevStatus 'error' ('-PaperPlugin needs Paper 1.20.6 or later (the template registers commands with the lifecycle API); ' + $Minecraft + ' uses plugin.yml')
        exit 1
    }
    if ($Folia -and (Get-PaperDevMinecraftVersions 'folia') -notcontains $Minecraft) {
        Write-PaperDevStatus 'error' ('Folia has no build for ' + $Minecraft + ' (Folia versions: ' + ((Get-PaperDevMinecraftVersions 'folia') -join ', ') + ')')
        exit 1
    }
    if (-not $NoTests) {
        # The templates' tests use MockBukkit's current packages (org.mockbukkit), released for 1.21 and later.
        if ($era.Brigadier) { $mock = Get-PaperDevMockBukkit -Minecraft $Minecraft }
        if (-not $mock) {
            Write-PaperDevStatus 'note' ('no MockBukkit for ' + $Minecraft + ' that the templates use; the project is created without tests (check on the test server, references/testing.md)')
            $NoTests = $true
        } else {
            $junit = Get-PaperDevMavenRelease -Repository $PaperDevMavenCentral -Group 'org.junit' -Artifact 'junit-bom'
        }
    }
} catch {
    Write-PaperDevStatus 'error' ('version lookup failed (network?): ' + $_.Exception.Message)
    exit 1
}
}

$descriptorName = 'plugin.yml'
$descriptorText = 'plugin.yml (Bukkit)'
if ($PaperPlugin) { $descriptorName = 'paper-plugin.yml'; $descriptorText = 'paper-plugin.yml (Paper plugin)' }
if ($Velocity) { $descriptorName = $null; $descriptorText = 'velocity-plugin.json (generated from @Plugin)' }
$authorsJava = ''
$sqliteJdbc = ''
if ($Database -and -not $NoTests) {
    try { $sqliteJdbc = Get-PaperDevMavenRelease -Repository $PaperDevMavenCentral -Group 'org.xerial' -Artifact 'sqlite-jdbc' } catch { Write-PaperDevStatus 'error' ('version lookup failed (network?): ' + $_.Exception.Message); exit 1 }
}
if ($Author) { $authorsJava = '"' + $Author.Replace('\', '\\').Replace('"', '\"') + '"' }
$tokens = @{
    PLUGIN_NAME = $Name; PROJECT_NAME = $projectName; MAIN_CLASS = $mainClass
    PACKAGE = $Package; PACKAGE_PATH = ($Package -replace '\.', '/'); GROUP = $Package
    PERMISSION_PREFIX = $permPrefix
    DESCRIPTION = $Description.Replace('\', '\\').Replace('"', '\"').Replace('$', '\$'); DESCRIPTION_YAML = (ConvertTo-PaperDevYamlString $Description)
    AUTHOR_YAML = $(if ($Author) { ConvertTo-PaperDevYamlString $Author } else { '' })
    MINECRAFT = $Minecraft; API_VERSION = [string](Get-PaperDevApiVersionField $Minecraft); API_DEPENDENCY = $apiDependency.Coordinate
    JAVA = [string]$javaVersion; RUN_PAPER = $runPaper; FOOJAY = $foojay
    MOCKBUKKIT_ARTIFACT = $(if ($mock) { $mock.Artifact } else { '' }); MOCKBUKKIT_VERSION = $(if ($mock) { $mock.Version } else { '' })
    JUNIT = [string]$junit; DESCRIPTOR = $descriptorText
    VELOCITY = $(if ($Velocity) { $VelocityVersion } else { '' }); RUN_VELOCITY = [string]$runVelocity; VELOCITY_ID = $velocityId
    SQLITE_JDBC = [string]$sqliteJdbc
    DESCRIPTION_JAVA = $Description.Replace('\', '\\').Replace('"', '\"'); AUTHORS_JAVA = $authorsJava
}
# Blocks of the templates: the platform, and for Paper the era (scripts/lib/common.ps1 Get-PaperDevEra).
$blocks = @()
if ($Velocity) { $blocks += 'VELOCITY' }
else {
    $blocks += 'BUKKIT'
    if ($bukkitPlatform) {
        $blocks += 'SPIGOT_REPO'
        if ($bukkitPlatform -eq 'craftbukkit') { $blocks += @('CRAFTBUKKIT', 'SERVER_CRAFTBUKKIT') } else { $blocks += 'SERVER_SPIGOT' }
    } else { $blocks += @('PAPER', 'SERVER_PAPER') }
    if (-not $NoTests) { $blocks += 'TESTS' }
    if ($era.Brigadier) { $blocks += 'BRIGADIER' } else { $blocks += 'LEGACY_COMMANDS' }
    if ($era.MiniMessage) { $blocks += 'MINIMESSAGE' } else { $blocks += 'LEGACY_TEXT' }
    if ($era.ApiVersion) { $blocks += 'API_VERSION' }
    if ($Folia) { $blocks += 'FOLIA' } else { $blocks += 'NO_FOLIA' }
    if ($Database) { $blocks += 'DATABASE' } else { $blocks += 'NO_DATABASE' }
}

$templateDir = Get-PaperDevTemplateDir
$projectTemplates = Join-Path $templateDir 'project'
if ($Velocity) { $projectTemplates = Join-Path $templateDir 'velocity' }
$plan = New-Object System.Collections.ArrayList
foreach ($f in (Get-ChildItem -LiteralPath $projectTemplates -Recurse -File)) {
    $rel = $f.FullName.Substring($projectTemplates.Length).TrimStart('\', '/') -replace '\\', '/'
    if ($NoTests -and $rel -like 'src/test/*') { continue }
    $target = $rel
    foreach ($k in $tokens.Keys) { $target = $target.Replace('@@' + $k + '@@', [string]$tokens[$k]) }
    [void]$plan.Add([PSCustomObject]@{ Source = $f.FullName; Target = $target })
}
if ($descriptorName) { [void]$plan.Add([PSCustomObject]@{ Source = (Join-Path $templateDir ('descriptor/' + $descriptorName)); Target = ('src/main/resources/' + $descriptorName) }) }
$starter = Get-PaperDevStarterFiles -Workflow:$Workflow
foreach ($k in $starter.Keys) { [void]$plan.Add([PSCustomObject]@{ Source = (Join-Path $templateDir $k); Target = $starter[$k] }) }

Write-Host ('project:   ' + $Path)
if ($Velocity) {
    Write-Host ('plugin:    ' + $Name + ' (id ' + $velocityId + ', ' + $Package + '.' + $mainClass + ', @Plugin)')
    Write-Host ('target:    Velocity ' + $VelocityVersion + ', Java ' + $javaVersion + ', ' + $apiDependency.Coordinate)
} else {
Write-Host ('plugin:    ' + $Name + ' (' + $Package + '.' + $mainClass + ', ' + $descriptorName + $(if ($Folia) { ', folia-supported' } else { '' }) + ')')
$platformName = 'Paper'; if ($bukkitPlatform -eq 'spigot') { $platformName = 'Spigot' } elseif ($bukkitPlatform -eq 'craftbukkit') { $platformName = 'CraftBukkit' }
Write-Host ('target:    ' + $platformName + ' ' + $Minecraft + ', Java ' + $javaVersion + ', ' + $apiDependency.Coordinate + ', commands: ' + $(if ($era.Brigadier) { 'Brigadier' } else { 'plugin.yml + CommandExecutor' }) + ', text: ' + $(if ($era.MiniMessage) { 'MiniMessage' } else { 'legacy color codes' }))
}
foreach ($p in $plan) {
    $state = Write-PaperDevTemplateFile -Source $p.Source -Target (Join-Path $Path $p.Target) -Tokens $tokens -Blocks $blocks -DryRun:$DryRun
    Write-PaperDevStatus $state $p.Target
}
if ($DryRun) {
    if (-not $NoWrapper) { Write-PaperDevStatus 'plan' 'would create the Gradle wrapper (gradlew, gradlew.bat, gradle/wrapper/)' }
    exit 0
}

if (-not $NoWrapper) {
    try { Invoke-Wrapper -Dir $Path -Java $java }
    catch {
        Write-PaperDevStatus 'error' ($_.Exception.Message + ' - run scripts/new-plugin.ps1 -WrapperOnly -Path "' + $Path + '" again later')
        exit 1
    }
    Write-PaperDevStatus 'created' 'gradlew, gradlew.bat, gradle/wrapper/'
}

Write-Host ''
Write-Host 'next: scripts/check.ps1 (build and test), then scripts/run-server.ps1 to try it on a test server.'
if ($java.Major -ne $javaVersion) { Write-PaperDevStatus 'note' ('the build compiles with Java ' + $javaVersion + ' (Gradle downloads it as a toolchain when missing); the test server runs on Java ' + (Format-PaperDevJavaRange $era) + ' (scripts/doctor.ps1 shows whether one is installed)') }
exit 0
