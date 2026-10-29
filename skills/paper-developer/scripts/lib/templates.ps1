# Renders the files under templates/. Tokens are @@NAME@@ (in contents and in path segments).
# Lines between "@@BEGIN:X@@" and "@@END:X@@" are kept only when block X is enabled; the marker lines are dropped.
# A line whose tokens expand to nothing because the value is empty is kept as is (write the template so that is fine).

function Expand-PaperDevTemplate {
    param([string]$Text, [hashtable]$Tokens, [string[]]$Blocks = @())
    $out = New-Object System.Collections.ArrayList
    $skip = 0
    foreach ($line in ($Text -replace "`r`n", "`n") -split "`n") {
        if ($line -match '^\s*@@BEGIN:([A-Z_]+)@@\s*$') {
            if ($skip -gt 0 -or $Blocks -notcontains $Matches[1]) { $skip++ }
            continue
        }
        if ($line -match '^\s*@@END:([A-Z_]+)@@\s*$') {
            if ($skip -gt 0) { $skip-- }
            continue
        }
        if ($skip -gt 0) { continue }
        [void]$out.Add($line)
    }
    $result = $out -join "`n"
    foreach ($k in $Tokens.Keys) { $result = $result.Replace('@@' + $k + '@@', [string]$Tokens[$k]) }
    return $result
}

function Get-PaperDevTemplateDir {
    return (Join-Path $PaperDevSkillDir 'templates')
}

function Get-PaperDevStarterFiles {
    # Starter files of a plugin project: template path (relative to templates/) -> path in the project.
    param([switch]$Workflow)
    $files = [ordered]@{
        'PLUGIN.md' = 'PLUGIN.md'
        'AGENTS.md' = 'AGENTS.md'
        'CLAUDE.md' = 'CLAUDE.md'
        'gitignore' = '.gitignore'
        'gitattributes' = '.gitattributes'
        'editorconfig' = '.editorconfig'
    }
    if ($Workflow) {
        $files['github/check.yml'] = '.github/workflows/check.yml'
        $files['github/release.yml'] = '.github/workflows/release.yml'
    }
    return $files
}

function ConvertTo-PaperDevYamlString {
    param([string]$Value)
    return ("'" + ($Value -replace "'", "''") + "'")
}

function ConvertTo-PaperDevIdentifier {
    # A Java class name from a plugin name: "my cool-plugin" -> "MyCoolPlugin".
    param([string]$Name)
    $parts = @($Name -split '[^A-Za-z0-9]+' | Where-Object { $_ })
    $id = -join ($parts | ForEach-Object { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) })
    if (-not $id) { $id = 'Plugin' }
    if ($id -match '^\d') { $id = 'P' + $id }
    return $id
}

function ConvertTo-PaperDevKebab {
    # "MyCoolPlugin" -> "my-cool-plugin"
    param([string]$Name)
    $s = $Name -creplace '([a-z0-9])([A-Z])', '$1-$2'
    $s = ($s -replace '[^A-Za-z0-9]+', '-').Trim('-').ToLowerInvariant()
    if (-not $s) { $s = 'plugin' }
    return $s
}

function ConvertTo-PaperDevPackageSegment {
    param([string]$Text)
    $s = ($Text -replace '[^A-Za-z0-9_]', '').ToLowerInvariant()
    if (-not $s) { $s = 'plugin' }
    if ($s -match '^\d') { $s = '_' + $s }
    $reserved = @('abstract', 'assert', 'boolean', 'break', 'byte', 'case', 'catch', 'char', 'class', 'const', 'continue', 'default', 'do', 'double', 'else', 'enum', 'extends', 'final', 'finally', 'float', 'for', 'goto', 'if', 'implements', 'import', 'instanceof', 'int', 'interface', 'long', 'native', 'new', 'package', 'private', 'protected', 'public', 'return', 'short', 'static', 'strictfp', 'super', 'switch', 'synchronized', 'this', 'throw', 'throws', 'transient', 'try', 'void', 'volatile', 'while', 'true', 'false', 'null')
    if ($reserved -contains $s) { $s = $s + '_' }
    return $s
}

function Write-PaperDevTemplateFile {
    # Writes one rendered template unless the target exists. Returns 'created', 'exists' or 'would create'.
    param([string]$Source, [string]$Target, [hashtable]$Tokens, [string[]]$Blocks, [switch]$DryRun)
    if (Test-Path -LiteralPath $Target) { return 'exists' }
    if ($DryRun) { return 'would create' }
    $text = Expand-PaperDevTemplate -Text (Read-PaperDevText $Source) -Tokens $Tokens -Blocks $Blocks
    Write-PaperDevText -Path $Target -Text $text
    return 'created'
}
