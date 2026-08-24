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

  # This dataset must stay synthetic -- see RISK_REGISTER.md (R-01/R-03) in
  # the shadowrealm-agents repo. Nothing else in the automated path checks
  # this, so it belongs here, immediately after the data leaves Power BI and
  # before anything gets written or pushed. Add a name to this list only
  # once it's confirmed fictional; do not add a real company name to make a
  # blocked publish go through.
  $approvedAccounts = @('Contoso', 'Fabrikam', 'Northwind Traders', 'Tailwind Traders')
  $unapproved = $rows | Where-Object { $_.account -and ($approvedAccounts -notcontains $_.account) } |
    Select-Object -ExpandProperty account -Unique
  if ($unapproved) {
    Write-Log "BLOCKED: unapproved account name(s) in source data: $($unapproved -join ', ') -- publish skipped. Update Fact_BCP[Account] in Power BI to a name in `$approvedAccounts, or add the new name here only if it is confirmed fictional."
    exit 0
  }

  $newJson = ConvertTo-JsonArray -Rows $rows

  # Two independent things can each need publishing: the data (bcp_data.json)
  # and the dashboard code itself (index.html, mirrored from
  # Heatmap_Dashboard.html whenever that file is edited). Check each on its
  # own -- gating index.html's refresh behind "did the data change" previously
  # meant a code fix committed to Heatmap_Dashboard.html never actually
  # reached the published index.html until the data *also* happened to change.
  $dataPath = Join-Path $repoRoot 'bcp_data.json'
  $oldJson = if (Test-Path $dataPath) { Get-Content -Path $dataPath -Raw } else { $null }
  $dataChanged = $oldJson -ne $newJson

  # RISK_REGISTER.md R-05: a record (EMP016) once disappeared between two
  # snapshots with no recorded reason, and separately the *same* ID later
  # got reused for a different person -- neither shows up as a plain row-
  # count change. Diff by ID against the previous snapshot and write every
  # addition/removal/reuse to DATA_CHANGELOG.md so this is never silent
  # again. Best-effort: a parse failure on the old snapshot logs a note but
  # never blocks the publish itself.
  if ($dataChanged) {
    $oldById = @{}
    if ($oldJson) {
      try {
        (ConvertFrom-Json $oldJson) | ForEach-Object { $oldById[$_.id] = $_ }
      } catch {
        Write-Log "NOTE: could not parse previous bcp_data.json for change tracking ($($_.Exception.Message)) -- skipping this run's DATA_CHANGELOG entry."
      }
    }
    if ($oldById.Count -gt 0 -or -not $oldJson) {
      $newIds = $rows | ForEach-Object { $_.id }
      $added = $rows | Where-Object { -not $oldById.ContainsKey($_.id) } | ForEach-Object { "$($_.id) ($($_.name))" }
      $removed = $oldById.Keys | Where-Object { $newIds -notcontains $_ } | ForEach-Object { "$_ ($($oldById[$_].name))" }
      $reused = $rows | Where-Object { $oldById.ContainsKey($_.id) -and $oldById[$_.id].name -ne $_.name } |
        ForEach-Object { "$($_.id): was '$($oldById[$_.id].name)', now '$($_.name)'" }

      if ($added -or $removed -or $reused) {
        $changelogPath = Join-Path $repoRoot 'DATA_CHANGELOG.md'
        if (-not (Test-Path $changelogPath)) {
          Set-Content -Path $changelogPath -Value "# Data Changelog`n`nAutomatically appended by bcp_publish.ps1 whenever the row set changes -- every addition, removal, or ID reuse gets a dated entry here so a change is never silent (see RISK_REGISTER.md R-05).`n"
        }
        $entry = "`n## $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
        if ($added)   { $entry += "`n- **Added ($($added.Count)):** " + ($added -join ', ') }
        if ($removed) { $entry += "`n- **Removed ($($removed.Count)):** " + ($removed -join ', ') }
        if ($reused)  { $entry += "`n- **ID reused (same ID, different person -- verify this is intentional):** " + ($reused -join '; ') }
        Add-Content -Path $changelogPath -Value $entry
      }
    }
  }

  $sourceHtml = Join-Path $repoRoot 'Heatmap_Dashboard.html'
  $indexHtml = Join-Path $repoRoot 'index.html'
  $oldHtml = if (Test-Path $indexHtml) { Get-Content -Path $indexHtml -Raw } else { $null }
  $newHtml = Get-Content -Path $sourceHtml -Raw
  $htmlChanged = $oldHtml -ne $newHtml

  if (-not $dataChanged -and -not $htmlChanged) {
    Write-Log "No data or code change since last run ($rowCount rows) -- nothing to publish."
    exit 0
  }

  if ($dataChanged) {
    [System.IO.File]::WriteAllText($dataPath, $newJson, [System.Text.UTF8Encoding]::new($false))
  }
  if ($htmlChanged) {
    Copy-Item -Path $sourceHtml -Destination $indexHtml -Force
  }

  $changeParts = @()
  if ($dataChanged) { $changeParts += "data: $rowCount rows" }
  if ($htmlChanged) { $changeParts += "dashboard code" }
  $commitMsg = "Auto-refresh published snapshot (" + ($changeParts -join ", ") + ")"

  Push-Location $repoRoot
  # Native commands (git) write routine warnings to stderr (e.g. CRLF-conversion
  # notices) that Windows PowerShell 5.1 turns into terminating errors when
  # $ErrorActionPreference is 'Stop' -- even with output redirected. Drop to
  # 'Continue' for this section and check $LASTEXITCODE explicitly instead.
  $prevEAP = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    git add bcp_data.json index.html DATA_CHANGELOG.md *> $null
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
