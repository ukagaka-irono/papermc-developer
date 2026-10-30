<#
.SYNOPSIS
  A test MySQL server for plugins that use a database: start, stop, status, and SQL to look at the data.
.DESCRIPTION
  The test server is started from the MySQL (or MariaDB) installed on this PC, with its own data folder in
  <home>/mysql/ and its own port (33306+), listening on 127.0.0.1 only. The user's own MySQL service and its
  data are not touched. User root, no password, database papermc_test.
  scripts/run-server.ps1 -Database mysql starts it and points a template-made plugin at it.
  -Start           starts it (initializes the data folder the first time)
  -Stop            stops it
  -Query "<SQL>"   runs SQL on papermc_test and prints the result (e.g. "SELECT * FROM hello_counts")
  -Reset           deletes the test data folder (only the test server's; ask the user first)
  Without a switch: shows whether it runs and how to connect.
  Exit codes: 0 / 1 failed or SQL error / 3 no MySQL installed, or not running (for -Query).
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-db.ps1 -Start
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-db.ps1 -Query "SELECT * FROM hello_counts"
#>
param(
    [switch]$Start,
    [switch]$Stop,
    [string]$Query,
    [switch]$Reset
)
. (Join-Path $PSScriptRoot 'lib/common.ps1')
. (Join-Path $PSScriptRoot 'lib/server.ps1')
. (Join-Path $PSScriptRoot 'lib/database.ps1')
Initialize-PaperDevConsole

$session = Get-PaperDevTestDbSession
$running = Test-PaperDevTestDbRunning $session

if ($Stop -or $Reset) {
    if (Stop-PaperDevTestDb $session) { Write-PaperDevStatus 'ok' 'the test database stopped' } elseif ($Stop) { Write-PaperDevStatus 'ok' 'the test database was not running' }
    if ($Reset) {
        $data = Join-Path (Get-PaperDevTestDbDir) 'data'
        if (Test-Path -LiteralPath $data) { Remove-Item -LiteralPath $data -Recurse -Force; Write-PaperDevStatus 'ok' ('deleted ' + $data) }
    }
    exit 0
}

$mysql = Find-PaperDevMysql
if (-not $mysql) {
    Write-PaperDevStatus 'missing' 'no MySQL or MariaDB is installed (mysqld). Ask the user: install one (Windows: winget install --id Oracle.MySQL -e), or test with SQLite'
    exit 3
}

if ($Start) {
    try { $session = Start-PaperDevTestDb } catch { Write-PaperDevStatus 'error' $_.Exception.Message; exit 1 }
    $running = $true
}

if ($Query) {
    if (-not $running) { Write-PaperDevStatus 'stopped' 'the test database is not running (scripts/test-db.ps1 -Start)'; exit 3 }
    $r = Invoke-PaperDevTestDbSql -Session $session -Mysql $mysql -Sql $Query -Database $session.database
    if ($r.StdOut.Trim()) { Write-Host $r.StdOut.TrimEnd() } else { Write-Host '(no rows)' }
    if ($r.ExitCode -ne 0) { Write-PaperDevStatus 'error' $r.StdErr.Trim(); exit 1 }
    exit 0
}

if ($running) {
    Write-PaperDevStatus 'ok' ('running: ' + $session.version + ' (pid ' + $session.pid + ')')
    Write-Host ('          host 127.0.0.1  port ' + $session.port + '  database ' + $session.database + '  user root  password (none)')
    Write-Host ('          jdbc:mysql://127.0.0.1:' + $session.port + '/' + $session.database + '   folder: ' + (Get-PaperDevTestDbDir))
} else {
    Write-PaperDevStatus 'stopped' ('the test database is not running (' + $mysql.Version + ' is installed; scripts/test-db.ps1 -Start)')
}
exit 0
