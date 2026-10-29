<#
.SYNOPSIS
  Runs a server process and feeds its console (stdin) from a queue file. Started by lib/server.ps1, not by hand.
.DESCRIPTION
  Velocity has no RCON, so the test proxy is started through this bridge: it starts java with stdin kept open,
  writes java's stdout/stderr to -ConsoleLog, writes java's pid to -PidFile, and sends every line appended to
  -Queue to java's console. It exits when java exits.
  Exit codes: java's exit code / 1 java did not start.
#>
param(
    [string]$Java,
    [string]$ArgsFile,
    [string]$WorkDir,
    [string]$Queue,
    [string]$ConsoleLog,
    [string]$PidFile
)
. (Join-Path $PSScriptRoot 'common.ps1')
$ErrorActionPreference = 'Stop'

$arguments = @((Get-Content -LiteralPath $ArgsFile -Raw -Encoding UTF8 | ConvertFrom-Json))
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $Java
$psi.Arguments = ConvertTo-PaperDevArgumentString $arguments
$psi.WorkingDirectory = $WorkDir
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
$psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

$utf8 = New-Object System.Text.UTF8Encoding($false)
$log = New-Object System.IO.StreamWriter((New-Object System.IO.FileStream($ConsoleLog, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)), $utf8)
$log.AutoFlush = $true
try { $p = [System.Diagnostics.Process]::Start($psi) } catch { $log.WriteLine('bridge: cannot start java: ' + $_.Exception.Message); $log.Dispose(); exit 1 }
[System.IO.File]::WriteAllText($PidFile, [string]$p.Id, $utf8)
$stdin = New-Object System.IO.StreamWriter($p.StandardInput.BaseStream, $utf8)
$stdin.AutoFlush = $true

$outTask = $p.StandardOutput.ReadLineAsync()
$errTask = $p.StandardError.ReadLineAsync()
$queueOffset = 0
while ($true) {
    $busy = $false
    if ($outTask -and $outTask.IsCompleted) {
        if ($null -ne $outTask.Result) { $log.WriteLine($outTask.Result); $outTask = $p.StandardOutput.ReadLineAsync(); $busy = $true } else { $outTask = $null }
    }
    if ($errTask -and $errTask.IsCompleted) {
        if ($null -ne $errTask.Result) { $log.WriteLine($errTask.Result); $errTask = $p.StandardError.ReadLineAsync(); $busy = $true } else { $errTask = $null }
    }
    # New complete lines in the queue go to the console.
    if (-not $p.HasExited -and (Test-Path -LiteralPath $Queue)) {
        try {
            $fs = New-Object System.IO.FileStream($Queue, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            try {
                if ($fs.Length -gt $queueOffset) {
                    [void]$fs.Seek($queueOffset, [System.IO.SeekOrigin]::Begin)
                    $buf = New-Object byte[] ($fs.Length - $queueOffset)
                    $n = $fs.Read($buf, 0, $buf.Length)
                    $chunk = $utf8.GetString($buf, 0, $n)
                    $end = $chunk.LastIndexOf("`n")
                    if ($end -ge 0) {
                        foreach ($line in ($chunk.Substring(0, $end) -split "`r?`n")) { if ($line -ne '') { $stdin.WriteLine($line) } }
                        $queueOffset += $utf8.GetByteCount($chunk.Substring(0, $end + 1))
                        $busy = $true
                    }
                }
            } finally { $fs.Dispose() }
        } catch { }
    }
    if ($p.HasExited -and -not $outTask -and -not $errTask) { break }
    if (-not $busy) { Start-Sleep -Milliseconds 200 }
}
$log.WriteLine('bridge: java exited with code ' + $p.ExitCode)
$log.Dispose()
exit $p.ExitCode
