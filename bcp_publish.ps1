<#
  bcp_publish.ps1
  Scheduled snapshot publisher for the GitHub Pages-hosted copy of the
  dashboard. Unlike bcp_bridge.ps1 (which only ever answers your own
  machine's browser), this script pulls fresh data from Power BI, writes it
  to bcp_data.json, and pushes it to GitHub — so anyone viewing the Pages URL
  sees data "as of the last scheduled run," not a one-time frozen snapshot.

  Intended to be run on a schedule (see: Register-BcpPublishTask.ps1) while
  Heatmap.pbix is open in Power BI Desktop. Safe to run manually too.
  Silently does nothing (exit 0) if Power BI isn't open, or if the data
  hasn't changed since the last run — it never force-pushes or fails loudly,
  since it runs unattended.
#>

$ErrorActionPreference = 'Stop'
$repoRoot = $PSScriptRoot
$logFile = Join-Path $repoRoot 'bcp_publish.log'

function Write-Log([string]$msg) {
  $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $msg"
  Write-Host $line
  Add-Content -Path $logFile -Value $line
}

try {
  . (Join-Path $repoRoot 'bcp_common.ps1')

  $adomdPath = Get-AdomdAssemblyPath
  Add-Type -Path $adomdPath

  $rows = Get-FactBcpRows
  $rowCount = $rows.Count
  $newJson = ConvertTo-JsonArray -Rows $rows

  # Compare content directly rather than trusting git's staged-diff timing --
  # relying on `git diff --cached` here previously caused a stale/partial
  # snapshot to get published when a prior run's git operations partially
  # succeeded before throwing. This is unambiguous: no write, no commit, no
  # push happen at all unless the actual data differs from what's on disk now.
  $dataPath = Join-Path $repoRoot 'bcp_data.json'
  $oldJson = if (Test-Path $dataPath) { Get-Content -Path $dataPath -Raw } else { $null }

  if ($oldJson -eq $newJson) {
    Write-Log "No data change since last run ($rowCount rows) -- nothing to publish."
    exit 0
  }

  [System.IO.File]::WriteAllText($dataPath, $newJson, [System.Text.UTF8Encoding]::new($false))

  # Keep an index.html mirror of the dashboard so GitHub Pages' root URL
  # (.../bcp-heatmap-dashboard/) serves it directly, without renaming the
  # canonical working file that bcp_bridge.ps1's docs and local habits refer to.
  $sourceHtml = Join-Path $repoRoot 'Heatmap_Dashboard.html'
  $indexHtml = Join-Path $repoRoot 'index.html'
  Copy-Item -Path $sourceHtml -Destination $indexHtml -Force

  $commitMsg = "Auto-refresh published snapshot ($rowCount rows)"

  Push-Location $repoRoot
  # Native commands (git) write routine warnings to stderr (e.g. CRLF-conversion
  # notices) that Windows PowerShell 5.1 turns into terminating errors when
  # $ErrorActionPreference is 'Stop' -- even with output redirected. Drop to
  # 'Continue' for this section and check $LASTEXITCODE explicitly instead.
  $prevEAP = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    git add bcp_data.json index.html *> $null
    if ($LASTEXITCODE -ne 0) { throw "git add failed (exit $LASTEXITCODE)" }
    git commit -m $commitMsg --quiet *> $null
    if ($LASTEXITCODE -ne 0) { throw "git commit failed (exit $LASTEXITCODE)" }
    git push --quiet *> $null
    if ($LASTEXITCODE -ne 0) { throw "git push failed (exit $LASTEXITCODE)" }
    Write-Log "Published $rowCount rows to GitHub Pages."
  } finally {
    $ErrorActionPreference = $prevEAP
    Pop-Location
  }
} catch {
  Write-Log "SKIPPED: $($_.Exception.Message)"
  exit 0
}
