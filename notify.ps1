# Windows (PowerShell 5.1+) port of notify.sh. Keep behavior in sync with it.
Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'

try {
  [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
} catch {
  # No console attached; output encoding cannot be changed.
}
$OutputEncoding = New-Object System.Text.UTF8Encoding($false)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Built from code points so the file does not depend on its own encoding.
$EmojiDone = [char]::ConvertFromUtf32(0x2705)
$EmojiBlocked = [char]::ConvertFromUtf32(0x1F6AB)
$EmojiTest = [char]::ConvertFromUtf32(0x1F9EA)
$Dot = [char]::ConvertFromUtf32(0x30FB)

$script:Cfg = @{}

# Writes straight to stdout so function return values stay clean.
function Say([string]$Text) {
  [Console]::Out.WriteLine($Text)
}

function Get-EnvVar([string]$Name) {
  [Environment]::GetEnvironmentVariable($Name)
}

function Import-DotEnv([string]$Path) {
  $lines = [IO.File]::ReadAllLines($Path, (New-Object System.Text.UTF8Encoding($false)))
  foreach ($raw in $lines) {
    $line = $raw.TrimStart([char]0xFEFF).Trim()
    if ($line -eq '' -or $line.StartsWith('#')) { continue }
    if ($line -match '^export\s+') { $line = $line -replace '^export\s+', '' }
    $eq = $line.IndexOf('=')
    if ($eq -lt 1) { continue }

    $key = $line.Substring(0, $eq).Trim()
    $value = $line.Substring($eq + 1).Trim()
    if ($value.Length -ge 2 -and ($value[0] -eq '"' -or $value[0] -eq "'") -and $value[$value.Length - 1] -eq $value[0]) {
      $value = $value.Substring(1, $value.Length - 2)
    } else {
      $value = ($value -replace '\s+#.*$', '').Trim()
    }
    $script:Cfg[$key] = $value
  }
}

function Import-Config {
  $configDir = Get-EnvVar 'HERDR_PLUGIN_CONFIG_DIR'
  $root = Get-EnvVar 'HERDR_PLUGIN_ROOT'
  if (-not $root) { $root = '.' }
  $localEnv = Join-Path $root '.env'

  if ($configDir -and (Test-Path -LiteralPath (Join-Path $configDir '.env') -PathType Leaf)) {
    Import-DotEnv (Join-Path $configDir '.env')
  } elseif (Test-Path -LiteralPath $localEnv -PathType Leaf) {
    Import-DotEnv $localEnv
  }
}

# Values from .env win over the process environment, like sourcing it in notify.sh.
function Get-Setting([string]$Name, [string]$Default = '') {
  $value = $null
  if ($script:Cfg.ContainsKey($Name)) {
    $value = $script:Cfg[$Name]
  } else {
    $value = Get-EnvVar $Name
  }
  if ([string]::IsNullOrEmpty($value)) { return $Default }
  return $value
}

function Get-JsonValue([string]$Name, [string]$Json, [string]$Path) {
  if ([string]::IsNullOrEmpty($Json)) { return '' }

  try {
    $node = $Json | ConvertFrom-Json
  } catch {
    [Console]::Error.WriteLine("failed to parse $Name")
    throw
  }

  foreach ($part in $Path.Split('.')) {
    if ($null -eq $node -or $node -isnot [psobject] -or -not ($node.PSObject.Properties.Name -contains $part)) {
      return ''
    }
    $node = $node.$part
  }

  if ($null -eq $node -or ($node -is [bool] -and -not $node)) { return '' }
  return [string]$node
}

function Get-FirstValue([string[]]$Values) {
  foreach ($value in $Values) {
    if (-not [string]::IsNullOrEmpty($value) -and $value -ne 'null') { return $value }
  }
  return ''
}

function Get-CleanLabel([string]$Label, [string]$Fallback) {
  $clean = ($Label -replace '[\r\n\t]', ' ' -replace ' +', ' ').Trim()
  if ($clean) { return $clean }
  return $Fallback
}

function Get-StatusStateFile([string]$PaneId) {
  if (-not $PaneId) { return '' }

  $base = Get-EnvVar 'HERDR_PLUGIN_CONFIG_DIR'
  if (-not $base) { $base = Get-EnvVar 'HERDR_PLUGIN_ROOT' }
  if (-not $base) { $base = '.' }

  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    $hash = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($PaneId))
  } finally {
    $sha.Dispose()
  }
  $key = ([BitConverter]::ToString($hash, 0, 8)).Replace('-', '').ToLowerInvariant()
  return Join-Path (Join-Path $base '.state') "$key.status"
}

function Read-PreviousStatus([string]$StateFile) {
  if ($StateFile -and (Test-Path -LiteralPath $StateFile -PathType Leaf)) {
    $lines = [IO.File]::ReadAllLines($StateFile)
    if ($lines.Count -gt 0) { return $lines[0] }
  }
  return ''
}

function Save-Status([string]$StateFile, [string]$Status) {
  if (-not $StateFile) { return }

  $stateDir = Split-Path -Parent $StateFile
  $stateTmp = "$StateFile.$PID"

  try {
    New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
    [IO.File]::WriteAllText($stateTmp, "$Status`n", (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $stateTmp -Destination $StateFile -Force
  } catch {
    [Console]::Error.WriteLine("failed to save status state: $StateFile")
    Remove-Item -LiteralPath $stateTmp -Force -ErrorAction SilentlyContinue
  }
}

function Test-HttpUrl([string]$Url) {
  return $Url -match '^https?://'
}

function Test-PositiveInteger([string]$Value) {
  return $Value -match '^[0-9]+$' -and [int64]$Value -gt 0
}

function Get-RedactedUrl([string]$Url) {
  if ($Url -match '^https?://.*/') {
    $slash = $Url.LastIndexOf('/')
    $topic = $Url.Substring($slash + 1)
    if ($topic.Length -gt 6) { $topic = $topic.Substring(0, 6) }
    return "$($Url.Substring(0, $slash))/$topic..."
  }
  return $Url
}

function Get-CollieClickUrl([string]$CollieUrl, [string]$PaneId) {
  if (-not $CollieUrl -or -not $PaneId) { return '' }

  if (-not (Test-HttpUrl $CollieUrl)) {
    [Console]::Error.WriteLine('invalid COLLIE_URL; expected http:// or https://')
    return ''
  }

  return '{0}/pane/{1}' -f $CollieUrl.TrimEnd('/'), [Uri]::EscapeDataString($PaneId)
}

# HTTP header values must be ASCII; ntfy accepts RFC 2047 encoded words for UTF-8.
function ConvertTo-HeaderValue([string]$Value) {
  if ($Value -notmatch '[^\x20-\x7E]') { return $Value }
  $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value))
  return "=?UTF-8?B?${b64}?="
}

function Send-Ntfy([string]$Url, [string]$Title, [string]$Body, [string]$ClickUrl = '') {
  $headers = @{ 'Title' = (ConvertTo-HeaderValue $Title) }
  if ($ClickUrl) { $headers['Click'] = $ClickUrl }
  $token = Get-Setting 'NTFY_TOKEN'
  if ($token) { $headers['Authorization'] = "Bearer $token" }

  $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($Body)
  $response = Invoke-WebRequest -UseBasicParsing -Method Post -Uri $Url -Headers $headers `
    -ContentType 'text/plain; charset=utf-8' -Body $bytes
  return [Text.Encoding]::UTF8.GetString($response.RawContentStream.ToArray()).Trim()
}

function Write-CommonChecks([string]$NtfyUrl, [string]$NtfyTitle) {
  $ok = $true

  if ($NtfyUrl) {
    if (Test-HttpUrl $NtfyUrl) {
      Say "NTFY_URL: ok ($(Get-RedactedUrl $NtfyUrl))"
    } else {
      Say 'NTFY_URL: invalid; expected http:// or https://'
      $ok = $false
    }
  } else {
    Say 'NTFY_URL: missing'
    $ok = $false
  }

  Say "NTFY_TITLE: $NtfyTitle"
  if (Get-Setting 'NTFY_TOKEN') { Say 'NTFY_TOKEN: set' } else { Say 'NTFY_TOKEN: not set' }
  return $ok
}

function Write-ColliePart {
  $collieUrl = Get-Setting 'COLLIE_URL'
  if (-not $collieUrl) {
    Say 'COLLIE_URL: not set (notifications will have no click action)'
    return $true
  }
  if (Test-HttpUrl $collieUrl) {
    Say "COLLIE_URL: ok ($collieUrl)"
    return $true
  }
  Say 'COLLIE_URL: invalid; expected http:// or https://'
  return $false
}

function Invoke-DryRun {
  Import-Config

  $ntfyUrl = Get-Setting 'NTFY_URL'
  $ntfyTitle = Get-CleanLabel (Get-Setting 'NTFY_TITLE' 'Herdr') 'Herdr'
  $lines = Get-Setting 'NTFY_LINES' '12'

  Say 'Herdr ntfy dry-run'
  Say ''
  Say "powershell: ok ($($PSVersionTable.PSVersion))"

  $ok = Write-CommonChecks $ntfyUrl $ntfyTitle

  if (Test-PositiveInteger $lines) {
    Say "NTFY_LINES: $lines"
  } else {
    Say 'NTFY_LINES: invalid; expected a positive integer'
    $ok = $false
  }

  if (-not (Write-ColliePart)) { $ok = $false }
  $collieUrl = Get-Setting 'COLLIE_URL'

  Say ''
  Say 'Sample title:'
  Say "$EmojiDone verification${Dot}dry-run ($ntfyTitle)"
  Say ''
  Say 'Sample body:'
  Say 'Herdr ntfy dry-run: no notification was sent.'

  if ($collieUrl -and (Test-HttpUrl $collieUrl)) {
    Say ''
    Say 'Sample click URL:'
    Say (Get-CollieClickUrl $collieUrl 'wE:p1')
  }

  Say ''
  if ($ok) {
    Say 'Result: ok'
    return 0
  }
  Say 'Result: failed'
  return 1
}

function Invoke-TestNotification {
  Import-Config

  $ntfyUrl = Get-Setting 'NTFY_URL'
  $ntfyTitle = Get-CleanLabel (Get-Setting 'NTFY_TITLE' 'Herdr') 'Herdr'

  Say 'Herdr ntfy test'
  Say ''

  $ok = Write-CommonChecks $ntfyUrl $ntfyTitle
  if (-not (Write-ColliePart)) { $ok = $false }

  if (-not $ok) {
    Say ''
    Say 'Result: failed'
    return 1
  }

  $sentAt = [DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
  $title = "$EmojiTest verification${Dot}test ($ntfyTitle)"
  $body = "Herdr ntfy test: this notification was sent by the test action.`nSent at: $sentAt"

  Say ''
  Say 'Sending title:'
  Say $title
  Say ''
  Say 'Sending body:'
  Say $body
  Say ''
  Say 'ntfy response:'

  try {
    $response = Send-Ntfy $ntfyUrl $title $body
  } catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    Say ''
    Say 'Result: failed'
    return 1
  }

  Say $response
  Say ''
  Say 'Result: sent'
  return 0
}

function Invoke-Event {
  Import-Config

  $eventJson = Get-EnvVar 'HERDR_PLUGIN_EVENT_JSON'
  $contextJson = Get-EnvVar 'HERDR_PLUGIN_CONTEXT_JSON'
  $evt = 'HERDR_PLUGIN_EVENT_JSON'
  $ctx = 'HERDR_PLUGIN_CONTEXT_JSON'

  $status = (Get-FirstValue @(
      (Get-JsonValue $evt $eventJson 'data.agent_status'),
      (Get-JsonValue $ctx $contextJson 'focused_pane_status'),
      (Get-JsonValue $ctx $contextJson 'agent_status')
    )).ToLowerInvariant()

  $paneId = Get-FirstValue @(
    (Get-JsonValue $evt $eventJson 'data.pane_id'),
    (Get-JsonValue $ctx $contextJson 'pane_id'),
    (Get-EnvVar 'HERDR_PANE_ID')
  )
  $stateFile = Get-StatusStateFile $paneId
  $previousStatus = Read-PreviousStatus $stateFile
  Save-Status $stateFile $status

  switch ($status) {
    'done' { $emoji = $EmojiDone }
    'blocked' { $emoji = $EmojiBlocked }
    'idle' {
      if ($previousStatus -ne 'working') { return 0 }
      $emoji = $EmojiDone
    }
    default { return 0 }
  }

  $ntfyUrl = Get-Setting 'NTFY_URL'
  if (-not $ntfyUrl) {
    [Console]::Error.WriteLine('missing NTFY_URL')
    return 0
  }
  $clickUrl = Get-CollieClickUrl (Get-Setting 'COLLIE_URL') $paneId

  $ntfyTitle = Get-CleanLabel (Get-Setting 'NTFY_TITLE' 'Herdr') 'Herdr'
  $workspaceName = Get-FirstValue @(
    (Get-JsonValue $ctx $contextJson 'workspace_label'),
    (Get-JsonValue $ctx $contextJson 'workspace.name'),
    (Get-JsonValue $ctx $contextJson 'workspace.label'),
    (Get-JsonValue $evt $eventJson 'data.workspace_label'),
    (Get-JsonValue $evt $eventJson 'data.workspace_id'),
    (Get-EnvVar 'HERDR_WORKSPACE_ID')
  )
  $tabName = Get-FirstValue @(
    (Get-JsonValue $ctx $contextJson 'tab_label'),
    (Get-JsonValue $ctx $contextJson 'tab.name'),
    (Get-JsonValue $ctx $contextJson 'tab.label'),
    (Get-JsonValue $evt $eventJson 'data.tab_label'),
    (Get-JsonValue $evt $eventJson 'data.tab_id'),
    (Get-EnvVar 'HERDR_TAB_ID')
  )

  $workspaceName = Get-CleanLabel $workspaceName 'workspace'
  $tabName = Get-CleanLabel $tabName 'tab'
  $title = "$emoji $workspaceName$Dot$tabName ($ntfyTitle)"

  $herdrBin = Get-EnvVar 'HERDR_BIN_PATH'
  if (-not $herdrBin) { $herdrBin = 'herdr' }
  $lines = Get-Setting 'NTFY_LINES' '12'
  $body = ''

  if ($paneId) {
    try {
      $output = & $herdrBin pane read $paneId --source recent-unwrapped --lines $lines 2>$null
      if ($output) { $body = (($output | ForEach-Object { "$_" }) -join "`n").TrimEnd("`r", "`n") }
    } catch {
      $body = ''
    }
  }

  if (-not $body) {
    $body = Get-FirstValue @(
      (Get-JsonValue $evt $eventJson 'data.message'),
      (Get-JsonValue $ctx $contextJson 'message'),
      $status
    )
  }

  try {
    $null = Send-Ntfy $ntfyUrl $title $body $clickUrl
  } catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    return 1
  }
  return 0
}

$mode = if ($args.Count -gt 0) { $args[0] } else { '' }
if ($mode -eq '--dry-run') { exit (Invoke-DryRun) }
if ($mode -eq '--test') { exit (Invoke-TestNotification) }
exit (Invoke-Event)
