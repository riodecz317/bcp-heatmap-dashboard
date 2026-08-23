<#
  bcp_watcher.ps1
  Keeps two things running only while Power BI Desktop actually is:
   1. The "BCP Dashboard Auto-Publish" scheduled task (for the GitHub
      Pages-hosted dashboard).
   2. bcp_bridge.ps1 itself (for the local file:// dashboard's live-data
      fetch) -- started detached and hidden when PBI comes online, stopped
      when PBI closes, since a bridge left pointing at a closed PBI session
      is useless and previously kept dying silently with nothing to notice.

  Runs on its own frequent, lightweight schedule via bcp_watcher_silent.vbs
  (see Register-BcpWatcherTask.ps1). Only writes to its log when it actually
  changes something -- not on every routine check -- so the log stays useful
  instead of filling up with "still off" lines every couple of minutes.
#>

$publishTaskName = "BCP Dashboard Auto-Publish"
$bridgePort = 8790
$repoRoot = $PSScriptRoot
$logFile = Join-Path $repoRoot 'bcp_watcher.log'

function Write-Log([string]$msg) {
  Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $msg"
}

function Test-BridgeListening {
  # Checking the port directly (not "is there a process whose command line
  # mentions bcp_bridge.ps1") is the reliable signal: a stale/zombie PID
  # reference can outlive the actual process, but a listening socket can't.
  $conn = Get-NetTCPConnection -LocalPort $bridgePort -State Listen -ErrorAction SilentlyContinue
  return [bool]$conn
}

$pbiRunning = [bool](Get-Process PBIDesktop -ErrorAction SilentlyContinue)

# --- Publish task (GitHub Pages side) ---
$task = Get-ScheduledTask -TaskName $publishTaskName -ErrorAction SilentlyContinue
if ($task) {
  if ($pbiRunning -and $task.State -eq 'Disabled') {
    Enable-ScheduledTask -TaskName $publishTaskName | Out-Null
    Start-ScheduledTask -TaskName $publishTaskName
    Write-Log "Power BI Desktop came online -- enabled and triggered $publishTaskName."
  } elseif (-not $pbiRunning -and $task.State -ne 'Disabled') {
    Disable-ScheduledTask -TaskName $publishTaskName | Out-Null
    Write-Log "Power BI Desktop is no longer running -- disabled $publishTaskName."
  }
}

# --- Local bridge (file:// dashboard side) ---
$bridgeListening = Test-BridgeListening
if ($pbiRunning -and -not $bridgeListening) {
  $vbsPath = Join-Path $repoRoot 'bcp_bridge_silent.vbs'
  Start-Process -FilePath 'wscript.exe' -ArgumentList "//B `"$vbsPath`"" -WindowStyle Hidden
  Write-Log "Power BI Desktop came online -- started bcp_bridge.ps1 (was not listening on port $bridgePort)."
} elseif (-not $pbiRunning -and $bridgeListening) {
  Get-NetTCPConnection -LocalPort $bridgePort -State Listen -ErrorAction SilentlyContinue |
    ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }
  Write-Log "Power BI Desktop is no longer running -- stopped bcp_bridge.ps1 (port $bridgePort)."
}
