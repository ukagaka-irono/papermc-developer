<#
.SYNOPSIS
  Adds the starter files to an existing plugin project. Existing files are never changed.
.DESCRIPTION
  PLUGIN.md (the empty form; draft it from the code, references/workflows/setup.md), AGENTS.md, CLAUDE.md,
  .gitignore, .gitattributes, .editorconfig. -Workflow also adds .github/workflows/check.yml and release.yml.
  -DryRun shows what would be created.
  Exit codes: 0 / 1 failed.
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/init-plugin.ps1 -DryRun
#>
param(
    [string]$ProjectRoot,
    [switch]$Workflow,
    [switch]$DryRun
)
. (Join-Path $PSScriptRoot 'lib/common.ps1')
. (Join-Path $PSScriptRoot 'lib/templates.ps1')
Initialize-PaperDevConsole

$project = Resolve-PaperDevProject $ProjectRoot
if (-not $project) { Write-PaperDevStatus 'error' 'no Gradle or Maven project found (pass -ProjectRoot, or create one with scripts/new-plugin.ps1)'; exit 1 }

$v = Get-PaperDevProjectVersions $project
$name = Get-PaperDevPluginName $project
$main = ''
$package = ''
if ($project.Descriptor) {
    $main = (Read-PaperDevDescriptor $project.Descriptor).Values['main']
    if ($main -match '^(.+)\.([^.]+)$') { $package = $Matches[1]; $main = $Matches[2] }
}
$java = $v.Java
if (-not $java) { $java = 21 }
$descriptorText = 'plugin.yml (Bukkit)'
if ($project.Kind -eq 'paper') { $descriptorText = 'paper-plugin.yml (Paper plugin)' }
$target = [string]$v.Minecraft
$blocks = @('BUKKIT')
switch ($v.Platform) {
    'spigot' { $blocks += 'SERVER_SPIGOT' }
    'craftbukkit' { $blocks += 'SERVER_CRAFTBUKKIT' }
    default { $blocks += 'SERVER_PAPER' }
}
if ($v.FoliaSupported -or $v.Platform -eq 'folia') { $blocks += 'FOLIA' } else { $blocks += 'NO_FOLIA' }
# PLUGIN.md's database part when the code uses JDBC.
$usesSql = @(Get-ChildItem -LiteralPath (Join-Path $project.Module 'src/main') -Recurse -File -Include '*.java', '*.kt' -ErrorAction SilentlyContinue | Where-Object { (Read-PaperDevText $_.FullName) -match 'java\.sql\.' }).Count -gt 0
if ($usesSql) { $blocks += 'DATABASE' }
# Message format in PLUGIN.md: MiniMessage where the API has it (Paper 1.18.2+), else "&" color codes.
if ($v.Platform -notin @('spigot', 'craftbukkit') -and $v.Minecraft -and (Test-PaperDevVersionAtLeast $v.Minecraft '1.18.2')) { $blocks += 'MINIMESSAGE' } else { $blocks += 'LEGACY_TEXT' }
if ($project.Kind -eq 'velocity') {
    $descriptorText = 'velocity-plugin.json (generated from @Plugin)'
    $target = [string]$v.Velocity
    $blocks = @('VELOCITY')
    $vp = Get-PaperDevVelocityPlugin $project
    if ($vp -and $vp.Main -match '^(.+)\.([^.]+)$') { $package = $Matches[1]; $main = $Matches[2] }
}
$tokens = @{
    PLUGIN_NAME = $name; MINECRAFT = $target; JAVA = [string]$java; DESCRIPTOR = $descriptorText
    PACKAGE = $package; MAIN_CLASS = $main; PERMISSION_PREFIX = ($name.ToLowerInvariant() -replace '[^a-z0-9_]', '')
}
$templateDir = Get-PaperDevTemplateDir
$starter = Get-PaperDevStarterFiles -Workflow:$Workflow
Write-Host ('project: ' + $project.Root)
foreach ($k in $starter.Keys) {
    $state = Write-PaperDevTemplateFile -Source (Join-Path $templateDir $k) -Target (Join-Path $project.Root $starter[$k]) -Tokens $tokens -Blocks $blocks -DryRun:$DryRun
    Write-PaperDevStatus $state $starter[$k]
}
if ($Workflow -and $project.BuildTool -eq 'maven') { Write-PaperDevStatus 'note' 'the workflows run ./gradlew; change them to ./mvnw -B package for Maven' }
exit 0
