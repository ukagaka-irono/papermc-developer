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
$tokens = @{
    PLUGIN_NAME = $name; MINECRAFT = [string]$v.Minecraft; JAVA = [string]$java; DESCRIPTOR = $descriptorText
    PACKAGE = $package; MAIN_CLASS = $main; PERMISSION_PREFIX = ($name.ToLowerInvariant() -replace '[^a-z0-9_]', '')
}
$templateDir = Get-PaperDevTemplateDir
$starter = Get-PaperDevStarterFiles -Workflow:$Workflow
Write-Host ('project: ' + $project.Root)
foreach ($k in $starter.Keys) {
    $state = Write-PaperDevTemplateFile -Source (Join-Path $templateDir $k) -Target (Join-Path $project.Root $starter[$k]) -Tokens $tokens -Blocks @() -DryRun:$DryRun
    Write-PaperDevStatus $state $starter[$k]
}
if ($Workflow -and $project.BuildTool -eq 'maven') { Write-PaperDevStatus 'note' 'the workflows run ./gradlew; change them to ./mvnw -B package for Maven' }
exit 0
