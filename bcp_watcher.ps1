<#
  bcp_watcher.ps1
  Keeps the "BCP Dashboard Auto-Publish" scheduled task enabled only while
  Power BI Desktop is actually running, so it doesn't wake up every 15
  minutes (even just to no-op) when there's nothing for it to publish.

  Runs on its own frequent, lightweight schedule via bcp_watcher_silent.vbs
  (see Register-BcpWatcherTask.ps1). Only writes to its log when it actually
  changes something -- not on every routine check -- so the log stays useful
  instead of filling up with "still off" lines every couple of minutes.
#>

$publishTaskName = "BCP Dashboard Auto-Publish"
$logFile = Join-Path $PSScriptRoot 'bcp_watcher.log'

function Write-Log([string]$msg) {
  Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $msg"
}

$task = Get-ScheduledTask -TaskName $publishTaskName -ErrorAction SilentlyContinue
if (-not $task) { exit 0 }

$pbiRunning = [bool](Get-Process PBIDesktop -ErrorAction SilentlyContinue)

if ($pbiRunning -and $task.State -eq 'Disabled') {
  Enable-ScheduledTask -TaskName $publishTaskName | Out-Null
  Start-ScheduledTask -TaskName $publishTaskName
  Write-Log "Power BI Desktop came online -- enabled and triggered $publishTaskName."
} elseif (-not $pbiRunning -and $task.State -ne 'Disabled') {
  Disable-ScheduledTask -TaskName $publishTaskName | Out-Null
  Write-Log "Power BI Desktop is no longer running -- disabled $publishTaskName."
}
