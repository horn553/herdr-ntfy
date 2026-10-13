# Windows counterpart of notify_test.sh. Runs notify.ps1 against a local fake ntfy server.
Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$testDir = Join-Path ([IO.Path]::GetTempPath()) ("herdr-ntfy-test-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testDir | Out-Null
$callsFile = Join-Path $testDir 'calls.jsonl'
$configDir = Join-Path $testDir 'config'
$port = Get-Random -Minimum 20000 -Maximum 40000
$paneId = 'pane-transition-test'

$emojiDone = [char]::ConvertFromUtf32(0x2705)
$emojiBlocked = [char]::ConvertFromUtf32(0x1F6AB)
$dot = [char]::ConvertFromUtf32(0x30FB)

# Fake ntfy: records each request as one JSON line, replies like ntfy does.
$server = Start-Job -ArgumentList $port, $callsFile -ScriptBlock {
  param($port, $callsFile)
  $listener = New-Object System.Net.HttpListener
  $listener.Prefixes.Add("http://127.0.0.1:$port/")
  $listener.Start()
  while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $reader = New-Object System.IO.StreamReader($ctx.Request.InputStream, [Text.Encoding]::UTF8)
    $body = $reader.ReadToEnd()
    $headers = @{}
    foreach ($name in $ctx.Request.Headers.AllKeys) { $headers[$name] = $ctx.Request.Headers[$name] }
    $record = @{ path = $ctx.Request.Url.AbsolutePath; headers = $headers; body = $body } | ConvertTo-Json -Compress -Depth 4
    [IO.File]::AppendAllText($callsFile, $record + "`n", (New-Object System.Text.UTF8Encoding($false)))
    $bytes = [Text.Encoding]::UTF8.GetBytes('{"id":"test"}')
    $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $ctx.Response.Close()
  }
}

function Stop-Cleanup {
  Stop-Job $server -ErrorAction SilentlyContinue
  Remove-Job $server -Force -ErrorAction SilentlyContinue
  Remove-Item -Recurse -Force $testDir -ErrorAction SilentlyContinue
}

function Fail([string]$Message) {
  [Console]::Error.WriteLine($Message)
  Stop-Cleanup
  exit 1
}

function Get-Calls {
  if (-not (Test-Path $callsFile)) { return @() }
  return @(Get-Content -Encoding UTF8 $callsFile | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json })
}

# Wait for the listener to accept connections.
$ready = $false
for ($i = 0; $i -lt 50 -and -not $ready; $i++) {
  try {
    $tcp = New-Object Net.Sockets.TcpClient
    $tcp.Connect('127.0.0.1', $port)
    $tcp.Close()
    $ready = $true
  } catch {
    Start-Sleep -Milliseconds 100
  }
}
if (-not $ready) { Fail 'fake ntfy server did not start' }
# The readiness probe above sends no HTTP request, so the log stays empty.

function Assert-CallCount([int]$Expected) {
  $actual = @(Get-Calls).Count
  if ($actual -ne $Expected) { Fail "expected $Expected notification(s), got $actual" }
}

function Get-LastCall { return @(Get-Calls)[-1] }

function Decode-Header([string]$Value) {
  if ($Value -match '^=\?UTF-8\?B\?(.+)\?=$') {
    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Matches[1]))
  }
  return $Value
}

function Invoke-Event([string]$AgentStatus, [string]$CollieUrl = '') {
  $env:HERDR_PLUGIN_EVENT_JSON = "{`"data`":{`"agent_status`":`"$AgentStatus`",`"pane_id`":`"$paneId`"}}"
  $env:HERDR_PLUGIN_CONTEXT_JSON = '{"workspace_label":"workspace","tab_label":"tab"}'
  $env:HERDR_PLUGIN_CONFIG_DIR = $configDir
  $env:HERDR_BIN_PATH = Join-Path $root 'tests\bin\herdr.cmd'
  $env:NTFY_URL = "http://127.0.0.1:$port/topic"
  $env:COLLIE_URL = $CollieUrl

  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'notify.ps1') | Out-Null
  if ($LASTEXITCODE -ne 0) { Fail "notify.ps1 exited with $LASTEXITCODE" }
}

Invoke-Event idle
Assert-CallCount 0

Invoke-Event working
Assert-CallCount 0
Invoke-Event idle
Assert-CallCount 1
$call = Get-LastCall
if ((Decode-Header $call.headers.Title) -ne "$emojiDone workspace${dot}tab (Herdr)") { Fail "unexpected title: $(Decode-Header $call.headers.Title)" }
if ($call.body -notmatch 'Agent output from the test pane\.') { Fail "unexpected body: $($call.body)" }
if ($call.path -ne '/topic') { Fail "unexpected path: $($call.path)" }

Invoke-Event idle
Assert-CallCount 1

Invoke-Event working
Invoke-Event done
Assert-CallCount 2
Invoke-Event idle
Assert-CallCount 2

Invoke-Event blocked
Assert-CallCount 3
if ((Decode-Header (Get-LastCall).headers.Title) -ne "$emojiBlocked workspace${dot}tab (Herdr)") { Fail 'unexpected blocked title' }

Invoke-Event working
Invoke-Event done
Assert-CallCount 4
if ((Get-LastCall).headers.PSObject.Properties.Name -contains 'Click') { Fail 'expected no Click header without COLLIE_URL' }

Invoke-Event working 'https://collie.example.ts.net'
Invoke-Event done 'https://collie.example.ts.net'
Assert-CallCount 5
if ((Get-LastCall).headers.Click -ne 'https://collie.example.ts.net/pane/pane-transition-test') { Fail "unexpected Click header: $((Get-LastCall).headers.Click)" }

Stop-Cleanup
Write-Output 'notify tests: ok'
