<#
.SYNOPSIS
  Updates a copied install of this skill (Codex, Antigravity, .claude/skills/...) to the latest commit on GitHub.
.DESCRIPTION
  Claude Code plugin installs are updated with "claude plugin update paper-developer" instead; this script
  refuses to touch the plugin cache. The commit that was installed is written to .installed-from in the
  skill folder. Nothing outside the skill folder changes (the home folder and the projects stay as they are).
  -DryRun         shows the installed and the latest commit
  -Ref <ref>      a branch, tag or commit instead of the default branch
  -Source <path>  a local copy of the repository (a folder or a zip) instead of GitHub
  -Target <path>  the skill folder to update (default: the one this script is in)
  Exit codes: 0 / 1 failed.
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/update-skill.ps1 -DryRun
#>
param(
    [switch]$DryRun,
    [string]$Ref = 'main',
    [string]$Source,
    [string]$Target
)
. (Join-Path $PSScriptRoot 'lib/common.ps1')
Initialize-PaperDevConsole

if (-not $Target) { $Target = $PaperDevSkillDir }
$Target = (Resolve-Path -LiteralPath $Target).Path
if (($Target -replace '\\', '/') -match '/plugins/cache/') {
    Write-PaperDevStatus 'error' 'this is a Claude Code plugin install: run "claude plugin marketplace update paper-developer" and "claude plugin update paper-developer"'
    exit 1
}
if (-not (Test-Path -LiteralPath (Join-Path $Target 'SKILL.md'))) { Write-PaperDevStatus 'error' ('not a skill folder: ' + $Target); exit 1 }

$installedFile = Join-Path $Target '.installed-from'
$installed = '(unknown)'
if (Test-Path -LiteralPath $installedFile) { $installed = (Read-PaperDevText $installedFile).Trim() }

$work = Join-Path ([System.IO.Path]::GetTempPath()) ('paper-developer-update-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work -Force | Out-Null
try {
    $label = $null
    $repoDir = $null
    if ($Source) {
        if (Test-Path -LiteralPath $Source -PathType Container) { $repoDir = (Resolve-Path -LiteralPath $Source).Path }
        else { Expand-Archive -LiteralPath $Source -DestinationPath $work -Force }
        $label = 'local:' + $Source
    } else {
        try { $sha = [string](Get-PaperDevJson ('https://api.github.com/repos/' + $PaperDevRepo + '/commits/' + $Ref)).sha }
        catch { Write-PaperDevStatus 'error' ('cannot reach GitHub: ' + $_.Exception.Message); exit 1 }
        $label = $PaperDevRepo + '@' + $sha
        Write-Host ('installed: ' + $installed)
        Write-Host ('latest:    ' + $label)
        if ($DryRun) {
            if ($installed -eq $label) { Write-PaperDevStatus 'ok' 'up to date' } else { Write-PaperDevStatus 'note' 'a newer version is available' }
            exit 0
        }
        if ($installed -eq $label) { Write-PaperDevStatus 'ok' 'already up to date'; exit 0 }
        $zip = Join-Path $work 'repo.zip'
        Save-PaperDevDownload -Uri ('https://codeload.github.com/' + $PaperDevRepo + '/zip/' + $sha) -OutFile $zip
        Expand-Archive -LiteralPath $zip -DestinationPath $work -Force
    }
    if (-not $repoDir) {
        $repoDir = (Get-ChildItem -LiteralPath $work -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'skills/paper-developer/SKILL.md') } | Select-Object -First 1).FullName
    }
    $newSkill = Join-Path $repoDir 'skills/paper-developer'
    if (-not (Test-Path -LiteralPath (Join-Path $newSkill 'SKILL.md'))) { Write-PaperDevStatus 'error' 'the source has no skills/paper-developer/SKILL.md'; exit 1 }
    if ($DryRun) { Write-PaperDevStatus 'plan' ('would replace ' + $Target + ' with ' + $label); exit 0 }

    foreach ($item in (Get-ChildItem -LiteralPath $Target -Force)) { Remove-Item -LiteralPath $item.FullName -Recurse -Force }
    foreach ($item in (Get-ChildItem -LiteralPath $newSkill -Force)) { Copy-Item -LiteralPath $item.FullName -Destination $Target -Recurse -Force }
    Write-PaperDevText -Path $installedFile -Text ($label + "`n")
    Write-PaperDevStatus 'ok' ('updated ' + $Target + ' to ' + $label + '. Restart the agent so it reads SKILL.md again.')
    exit 0
} finally {
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
