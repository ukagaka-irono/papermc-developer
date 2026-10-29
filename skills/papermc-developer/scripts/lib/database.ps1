# A test MySQL (or MariaDB) server for plugins that use a database: started from the MySQL the user installed,
# with its own data folder in <home>/mysql/ and its own port (33306+), listening on 127.0.0.1 only.
# The user's own MySQL service and its data are not touched. Root has no password: it is a test server.

$PaperDevTestDatabaseName = 'papermc_test'

function Find-PaperDevMysql {
    # mysqld / mysql / mysqladmin of an installed MySQL (or MariaDB): PATH, then the usual install folders.
    $candidates = @()
    $cmd = Get-Command mysqld -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { $candidates += (Split-Path -Parent $cmd.Source) }
    if (Test-PaperDevWindows) {
        foreach ($pf in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
            if (-not $pf) { continue }
            foreach ($d in @(Get-ChildItem -Path (Join-Path $pf 'MySQL') -Directory -ErrorAction SilentlyContinue) + @(Get-ChildItem -Path $pf -Directory -Filter 'MariaDB*' -ErrorAction SilentlyContinue)) {
                $candidates += (Join-Path $d.FullName 'bin')
            }
        }
    } else {
        $candidates += @('/usr/sbin', '/usr/bin', '/usr/local/bin', '/opt/homebrew/bin', '/usr/local/mysql/bin')
    }
    $exe = ''
    if (Test-PaperDevWindows) { $exe = '.exe' }
    foreach ($bin in $candidates) {
        $mysqld = Join-Path $bin ('mysqld' + $exe)
        $client = Join-Path $bin ('mysql' + $exe)
        $admin = Join-Path $bin ('mysqladmin' + $exe)
        if (-not ((Test-Path -LiteralPath $mysqld) -and (Test-Path -LiteralPath $client))) { continue }
        $v = (Invoke-PaperDevProcess -FilePath $mysqld -Arguments @('--version')).StdOut.Trim()
        $kind = 'mysql'
        if ($v -match '(?i)mariadb') { $kind = 'mariadb' }
        return [PSCustomObject]@{ Mysqld = $mysqld; Client = $client; Admin = $admin; Version = $v; Kind = $kind; Bin = $bin }
    }
    return $null
}

function Get-PaperDevTestDbDir {
    return (Get-PaperDevHomeDir 'mysql')
}

function Get-PaperDevTestDbSession {
    $path = Join-Path (Get-PaperDevTestDbDir) 'papermc-developer-mysql.json'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try { return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function Test-PaperDevPortOpen {
    param([int]$Port)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $ar = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
        if (-not $ar.AsyncWaitHandle.WaitOne(1000)) { return $false }
        $client.EndConnect($ar)
        return $true
    } catch { return $false } finally { $client.Close() }
}

function Test-PaperDevTestDbRunning {
    param($Session)
    if (-not $Session) { return $false }
    return ((Test-PaperDevProcessAlive ([int]$Session.pid)) -and (Test-PaperDevPortOpen ([int]$Session.port)))
}

function Invoke-PaperDevTestDbSql {
    # Runs SQL with the mysql client against the test server. Returns the process result (StdOut is a table).
    param($Session, $Mysql, [string]$Sql, [string]$Database = '')
    $cmdArgs = @('--no-defaults', '-h', '127.0.0.1', '-P', [string]$Session.port, '-u', 'root', '--table')
    if ($Database) { $cmdArgs += @('-D', $Database) }
    $cmdArgs += @('-e', $Sql)
    return (Invoke-PaperDevProcess -FilePath $Mysql.Client -Arguments $cmdArgs)
}

function Start-PaperDevTestDb {
    # Starts the test server unless it runs; initializes its data folder the first time. Returns the session.
    param([int]$TimeoutSeconds = 90)
    $session = Get-PaperDevTestDbSession
    if (Test-PaperDevTestDbRunning $session) { return $session }
    $mysql = Find-PaperDevMysql
    if (-not $mysql) { throw 'no MySQL or MariaDB is installed (mysqld): install one, or use SQLite' }
    $dir = Get-PaperDevTestDbDir
    $data = Join-Path $dir 'data'
    if (-not (Test-Path -LiteralPath $data)) {
        Write-Host ('initializing the test database folder (' + $mysql.Version + ')')
        if ($mysql.Kind -eq 'mariadb') {
            $install = Join-Path $mysql.Bin 'mysql_install_db.exe'
            if (-not (Test-Path -LiteralPath $install)) { $install = Join-Path $mysql.Bin 'mariadb-install-db.exe' }
            $r = Invoke-PaperDevProcess -FilePath $install -Arguments @(('--datadir=' + $data))
        } else {
            $r = Invoke-PaperDevProcess -FilePath $mysql.Mysqld -Arguments @('--no-defaults', '--initialize-insecure', ('--datadir=' + $data), '--console')
        }
        if ($r.ExitCode -ne 0) {
            if (Test-Path -LiteralPath $data) { Remove-Item -LiteralPath $data -Recurse -Force }
            throw ('initializing the test database failed: ' + (($r.StdErr + $r.StdOut) -split "`r?`n" | Select-Object -Last 8) -join "`n")
        }
    }
    $port = 0
    if ($session) { $port = [int]$session.port }
    if ($port -le 0 -or -not (Test-PaperDevPortFree $port)) { $port = Find-PaperDevFreePort 33306 33315 }
    if ($port -le 0) { throw 'no free port in 33306-33315' }
    $cmdArgs = @('--no-defaults', ('--datadir=' + $data), ('--port=' + $port), '--bind-address=127.0.0.1', '--console')
    if ($mysql.Kind -eq 'mysql') { $cmdArgs += '--mysqlx=OFF' }
    $proc = Start-PaperDevServerProcess -Directory $dir -Java $mysql.Mysqld -Arguments $cmdArgs -ConsolePath (Join-Path $dir 'console.log')
    $session = [PSCustomObject]@{ pid = $proc.Id; port = $port; database = $PaperDevTestDatabaseName; user = 'root'; password = ''; kind = $mysql.Kind; version = $mysql.Version }
    Write-PaperDevText -Path (Join-Path $dir 'papermc-developer-mysql.json') -Text ($session | ConvertTo-Json)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline -and -not (Test-PaperDevPortOpen $port)) {
        if (-not (Test-PaperDevProcessAlive $proc.Id)) { break }
        Start-Sleep -Milliseconds 500
    }
    if (-not (Test-PaperDevPortOpen $port)) {
        $tail = ''
        $log = Join-Path $dir 'console.log'
        if (Test-Path -LiteralPath $log) { $tail = (Get-Content -LiteralPath $log -Tail 10) -join "`n" }
        throw ('the test database did not start:' + "`n" + $tail)
    }
    $r = Invoke-PaperDevTestDbSql -Session $session -Mysql $mysql -Sql ('CREATE DATABASE IF NOT EXISTS ' + $PaperDevTestDatabaseName)
    if ($r.ExitCode -ne 0) { throw ('cannot create the database ' + $PaperDevTestDatabaseName + ': ' + $r.StdErr.Trim()) }
    return $session
}

function Stop-PaperDevTestDb {
    param($Session)
    if (-not (Test-PaperDevTestDbRunning $Session)) { return $false }
    $mysql = Find-PaperDevMysql
    if ($mysql -and (Test-Path -LiteralPath $mysql.Admin)) {
        Invoke-PaperDevProcess -FilePath $mysql.Admin -Arguments @('--no-defaults', '-h', '127.0.0.1', '-P', [string]$Session.port, '-u', 'root', 'shutdown') | Out-Null
    }
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $deadline -and (Test-PaperDevProcessAlive ([int]$Session.pid))) { Start-Sleep -Milliseconds 500 }
    if (Test-PaperDevProcessAlive ([int]$Session.pid)) { Stop-PaperDevProcessTree ([int]$Session.pid) }
    return $true
}

function Set-PaperDevPluginDatabaseConfig {
    # Points a template-made plugin at a database by writing the "database:" block of plugins/<name>/config.yml
    # (other keys stay; a new file holds only this block, the plugin's defaults fill in the rest).
    param([string]$PluginsDir, [string]$PluginName, [string]$Type, $Session)
    $path = Join-Path (Join-Path $PluginsDir $PluginName) 'config.yml'
    if ($Type -eq 'mysql') {
        $block = "database:`n  type: mysql`n  sqlite-file: data.db`n  mysql:`n    host: 127.0.0.1`n    port: " + $Session.port + "`n    database: " + $Session.database + "`n    user: " + $Session.user + "`n    password: ''`n    properties: 'allowPublicKeyRetrieval=true&useSSL=false'`n"
    } else {
        $block = "database:`n  type: sqlite`n  sqlite-file: data.db`n"
    }
    $text = ''
    if (Test-Path -LiteralPath $path) { $text = Read-PaperDevText $path }
    $m = [regex]::Match($text, '(?ms)^database:[^\n]*\n(?:(?:[ \t]+[^\n]*|[ \t]*)\n)*')
    if ($m.Success) { $text = $text.Substring(0, $m.Index) + $block + $text.Substring($m.Index + $m.Length) }
    else { if ($text -and -not $text.EndsWith("`n")) { $text += "`n" }; $text += $block }
    Write-PaperDevText -Path $path -Text $text
}
