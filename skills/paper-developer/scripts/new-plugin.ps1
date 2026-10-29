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

# Versions, looked up now
try {
    if (-not $Minecraft) { $Minecraft = Get-PaperDevLatestMinecraft }
    $info = Get-PaperDevVersionInfo -Minecraft $Minecraft
    $javaVersion = $info.JavaMinimum
    if (-not $javaVersion) { $javaVersion = 21 }
    $runPaper = Get-PaperDevGradlePluginVersion 'xyz.jpenilla.run-paper'
    $foojay = Get-PaperDevGradlePluginVersion 'org.gradle.toolchains.foojay-resolver-convention'
    $mock = $null
    $junit = $null
    if (-not $NoTests) {
        $mock = Get-PaperDevMockBukkit -Minecraft $Minecraft
        if (-not $mock) {
            Write-PaperDevStatus 'warn' ('MockBukkit has no release for ' + $Minecraft + ' yet; the project is created without tests (add them later, references/testing.md)')
            $NoTests = $true
        } else {
            $junit = Get-PaperDevMavenRelease -Repository $PaperDevMavenCentral -Group 'org.junit' -Artifact 'junit-bom'
        }
    }
} catch {
    Write-PaperDevStatus 'error' ('version lookup failed (network?): ' + $_.Exception.Message)
    exit 1
}

$descriptorName = 'plugin.yml'
$descriptorText = 'plugin.yml (Bukkit)'
if ($PaperPlugin) { $descriptorName = 'paper-plugin.yml'; $descriptorText = 'paper-plugin.yml (Paper plugin)' }
$tokens = @{
    PLUGIN_NAME = $Name; PROJECT_NAME = $projectName; MAIN_CLASS = $mainClass
    PACKAGE = $Package; PACKAGE_PATH = ($Package -replace '\.', '/'); GROUP = $Package
    PERMISSION_PREFIX = $permPrefix
    DESCRIPTION = $Description.Replace('\', '\\').Replace('"', '\"').Replace('$', '\$'); DESCRIPTION_YAML = (ConvertTo-PaperDevYamlString $Description)
    AUTHOR_YAML = $(if ($Author) { ConvertTo-PaperDevYamlString $Author } else { '' })
    MINECRAFT = $Minecraft; API_VERSION = (Get-PaperDevApiVersionField $Minecraft); PAPER_API = (Get-PaperDevApiCoordinate $Minecraft)
    JAVA = [string]$javaVersion; RUN_PAPER = $runPaper; FOOJAY = $foojay
    MOCKBUKKIT_ARTIFACT = $(if ($mock) { $mock.Artifact } else { '' }); MOCKBUKKIT_VERSION = $(if ($mock) { $mock.Version } else { '' })
    JUNIT = [string]$junit; DESCRIPTOR = $descriptorText
}
$blocks = @()
if (-not $NoTests) { $blocks += 'TESTS' }

$templateDir = Get-PaperDevTemplateDir
$projectTemplates = Join-Path $templateDir 'project'
$plan = New-Object System.Collections.ArrayList
foreach ($f in (Get-ChildItem -LiteralPath $projectTemplates -Recurse -File)) {
    $rel = $f.FullName.Substring($projectTemplates.Length).TrimStart('\', '/') -replace '\\', '/'
    if ($NoTests -and $rel -like 'src/test/*') { continue }
    $target = $rel
    foreach ($k in $tokens.Keys) { $target = $target.Replace('@@' + $k + '@@', [string]$tokens[$k]) }
    [void]$plan.Add([PSCustomObject]@{ Source = $f.FullName; Target = $target })
}
[void]$plan.Add([PSCustomObject]@{ Source = (Join-Path $templateDir ('descriptor/' + $descriptorName)); Target = ('src/main/resources/' + $descriptorName) })
$starter = Get-PaperDevStarterFiles -Workflow:$Workflow
foreach ($k in $starter.Keys) { [void]$plan.Add([PSCustomObject]@{ Source = (Join-Path $templateDir $k); Target = $starter[$k] }) }

Write-Host ('project:   ' + $Path)
Write-Host ('plugin:    ' + $Name + ' (' + $Package + '.' + $mainClass + ', ' + $descriptorName + ')')
Write-Host ('target:    Paper ' + $Minecraft + ', Java ' + $javaVersion + ', paper-api ' + $tokens.PAPER_API)
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
if ($java.Major -lt $javaVersion) { Write-PaperDevStatus 'note' ('the build compiles with Java ' + $javaVersion + ' (Gradle downloads it as a toolchain); the test server also needs Java ' + $javaVersion + '+') }
exit 0
