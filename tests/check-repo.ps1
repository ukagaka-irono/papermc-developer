<#
.SYNOPSIS
  Checks this repository: script syntax and ASCII, paths named in the documents, allowed-tools,
  template tokens, manifests, and that every mention of the repository names the same owner.
  Exit codes: 0 / 1 problems found.
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File tests/check-repo.ps1
#>
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$skill = Join-Path $repo 'skills/papermc-developer'
$problems = New-Object System.Collections.ArrayList
function Problem { param([string]$Text) [void]$problems.Add($Text); Write-Host ('[PROBLEM] ' + $Text) }
function Rel { param([string]$Path) return ($Path.Substring($repo.Length).TrimStart('\', '/') -replace '\\', '/') }
function ReadText { param([string]$Path) return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) }

# 1. scripts: syntax, ASCII, help
$scripts = @(Get-ChildItem -LiteralPath $repo -Recurse -File -Filter '*.ps1' | Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' })
foreach ($s in $scripts) {
    $tokens = $null; $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($s.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    foreach ($e in $errors) { Problem ((Rel $s.FullName) + ':' + $e.Extent.StartLineNumber + ': syntax: ' + $e.Message) }
    $bytes = [System.IO.File]::ReadAllBytes($s.FullName)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        if ($bytes[$i] -gt 127) {
            $line = 1 + @($bytes[0..$i] | Where-Object { $_ -eq 10 }).Count
            Problem ((Rel $s.FullName) + ':' + $line + ': non-ASCII byte (Windows PowerShell 5.1 misreads BOM-less UTF-8)')
            break
        }
    }
    if ($s.DirectoryName -notmatch '[\\/]lib$' -and (ReadText $s.FullName) -notmatch '\.SYNOPSIS') { Problem ((Rel $s.FullName) + ': no .SYNOPSIS help') }
}
Write-Host ('scripts: ' + $scripts.Count)

# 2. paths named in SKILL.md and references (relative to the skill folder)
$docs = @(Get-Item -LiteralPath (Join-Path $skill 'SKILL.md')) + @(Get-ChildItem -LiteralPath (Join-Path $skill 'references') -Recurse -File -Filter '*.md')
foreach ($d in $docs) {
    $text = ReadText $d.FullName
    foreach ($m in [regex]::Matches($text, '`((?:scripts|references|templates)/[A-Za-z0-9_./@-]+?\.(?:ps1|md|yml|kts|java|properties))[`\s]')) {
        $p = $m.Groups[1].Value
        if (-not (Test-Path -LiteralPath (Join-Path $skill $p))) { Problem ((Rel $d.FullName) + ': names a missing file: ' + $p) }
    }
}
$skillText = ReadText (Join-Path $skill 'SKILL.md')
$skillLines = @($skillText -split "`n").Count
if ($skillLines -gt 500) { Problem ('SKILL.md has ' + $skillLines + ' lines (keep it under 500)') }
if ($skillText -notmatch '(?m)^name: papermc-developer\s*$') { Problem 'SKILL.md: name is not papermc-developer' }
foreach ($m in [regex]::Matches($skillText, '\$\{CLAUDE_SKILL_DIR\}/(scripts/[A-Za-z0-9_-]+\.ps1)')) {
    if (-not (Test-Path -LiteralPath (Join-Path $skill $m.Groups[1].Value))) { Problem ('SKILL.md allowed-tools: missing ' + $m.Groups[1].Value) }
}
# every script is in the command table
$commands = ReadText (Join-Path $skill 'references/commands.md')
foreach ($s in (Get-ChildItem -LiteralPath (Join-Path $skill 'scripts') -File -Filter '*.ps1')) {
    if ($commands -notmatch [regex]::Escape('scripts/' + $s.Name)) { Problem ('references/commands.md does not list scripts/' + $s.Name) }
}
# every workflow is reachable from SKILL.md
foreach ($w in (Get-ChildItem -LiteralPath (Join-Path $skill 'references/workflows') -File -Filter '*.md')) {
    if ($skillText -notmatch [regex]::Escape('references/workflows/' + $w.Name)) { Problem ('SKILL.md does not point to references/workflows/' + $w.Name) }
}

# 3. template tokens
$known = @('PLUGIN_NAME', 'PROJECT_NAME', 'MAIN_CLASS', 'PACKAGE', 'PACKAGE_PATH', 'GROUP', 'PERMISSION_PREFIX', 'DESCRIPTION', 'DESCRIPTION_YAML', 'AUTHOR_YAML',
    'MINECRAFT', 'API_VERSION', 'API_DEPENDENCY', 'JAVA', 'RUN_PAPER', 'FOOJAY', 'MOCKBUKKIT_ARTIFACT', 'MOCKBUKKIT_VERSION', 'JUNIT', 'DESCRIPTOR',
    'VELOCITY', 'RUN_VELOCITY', 'VELOCITY_ID', 'DESCRIPTION_JAVA', 'AUTHORS_JAVA')
$newPlugin = ReadText (Join-Path $skill 'scripts/new-plugin.ps1')
foreach ($k in $known) { if ($newPlugin -notmatch ('\b' + $k + '\s*=')) { Problem ('scripts/new-plugin.ps1 does not set the token ' + $k) } }
foreach ($t in (Get-ChildItem -LiteralPath (Join-Path $skill 'templates') -Recurse -File)) {
    $names = @([regex]::Matches((ReadText $t.FullName) + ' ' + $t.FullName, '@@([A-Z_]+)(?::[A-Z_]+)?@@') | ForEach-Object { $_.Groups[1].Value })
    foreach ($n in ($names | Sort-Object -Unique)) {
        if ($n -in @('BEGIN', 'END')) { continue }
        if ($known -notcontains $n) { Problem ((Rel $t.FullName) + ': unknown token @@' + $n + '@@') }
    }
}
if (-not (Test-Path -LiteralPath (Join-Path $skill 'templates/PLUGIN.md')) -or (ReadText (Join-Path $skill 'templates/PLUGIN.md')) -notmatch 'papermc-developer:plugin-template') { Problem 'templates/PLUGIN.md lacks the template marker' }

# 4. manifests
foreach ($j in @('.claude-plugin/plugin.json', '.claude-plugin/marketplace.json')) {
    $p = Join-Path $repo $j
    try { $obj = (ReadText $p) | ConvertFrom-Json } catch { Problem ($j + ': not valid JSON'); continue }
    if ($obj.PSObject.Properties['version']) { Problem ($j + ': has "version" (updates stop reaching users; see MAINTAINING.md)') }
}

# 5. one repository owner everywhere
$common = ReadText (Join-Path $skill 'scripts/lib/common.ps1')
if ($common -notmatch "\`$PaperDevRepo = '([^']+)'") { Problem 'scripts/lib/common.ps1: $PaperDevRepo not found' }
else {
    $expected = $Matches[1]
    $files = @(Get-ChildItem -LiteralPath $repo -Recurse -File -Include '*.md', '*.json', '*.ps1', '*.yml' | Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' })
    foreach ($f in $files) {
        foreach ($m in [regex]::Matches((ReadText $f.FullName), '(?:github\.com/|marketplace add |codeload\.github\.com/)([A-Za-z0-9_.-]+/papermc-developer)')) {
            if ($m.Groups[1].Value -ne $expected) { Problem ((Rel $f.FullName) + ': names ' + $m.Groups[1].Value + ', expected ' + $expected) }
        }
    }
}

if ($problems.Count -gt 0) { Write-Host ($problems.Count.ToString() + ' problem(s)'); exit 1 }
Write-Host 'check-repo: OK'
exit 0
