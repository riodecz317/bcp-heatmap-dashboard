<#
  bcp_common.ps1
  Shared Power BI discovery/query logic, dot-sourced by both bcp_bridge.ps1
  (live local server) and bcp_publish.ps1 (scheduled snapshot publisher).
  This file only defines functions — it does nothing on its own.
#>

function Get-AdomdAssemblyPath {
  # WindowsApps' root directory listing is ACL-restricted, so we can't enumerate
  # it directly. Derive the exact versioned install path from the running
  # PBIDesktop.exe process instead (also guarantees we match the running version).
  $proc = Get-Process PBIDesktop -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $proc) { throw "Power BI Desktop is not running. Open Heatmap.pbix first." }
  $binDir = Split-Path -Parent $proc.Path
  $dll = Join-Path $binDir 'Microsoft.PowerBI.AdomdClient.dll'
  if (-not (Test-Path $dll)) { throw "Could not find Microsoft.PowerBI.AdomdClient.dll next to the running PBIDesktop.exe ($binDir)." }
  return $dll
}

function Get-PbiConnection {
  $msmdsrv = Get-Process msmdsrv -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $msmdsrv) { throw "Power BI Desktop's local engine (msmdsrv.exe) is not running. Open Heatmap.pbix first." }

  $netstatLine = (netstat -ano | Select-String "127.0.0.1:\d+\s+.*LISTENING\s+$($msmdsrv.Id)$") | Select-Object -First 1
  if (-not $netstatLine) { throw "Could not find the listening port for msmdsrv.exe (PID $($msmdsrv.Id))." }
  $port = ($netstatLine -split '\s+' | Where-Object { $_ -match '^127\.0\.0\.1:\d+$' }) -replace '.*:', '' | Select-Object -First 1

  $conn = New-Object Microsoft.AnalysisServices.AdomdClient.AdomdConnection "Data Source=127.0.0.1:$port"
  $conn.Open()
  $cmd = $conn.CreateCommand()
  $cmd.CommandText = "SELECT [CATALOG_NAME] FROM `$SYSTEM.DBSCHEMA_CATALOGS"
  $reader = $cmd.ExecuteReader()
  $catalog = $null
  if ($reader.Read()) { $catalog = $reader.GetValue(0) }
  $reader.Close()
  $conn.Close()
  if (-not $catalog) { throw "Could not discover the current catalog on 127.0.0.1:$port." }

  $full = New-Object Microsoft.AnalysisServices.AdomdClient.AdomdConnection "Data Source=127.0.0.1:$port;Catalog=$catalog"
  $full.Open()
  return $full
}

# Returns Fact_BCP as an array of PSCustomObjects (not JSON) so callers can
# either serve it, write it to disk, or diff it before deciding to publish.
function Get-FactBcpRows {
  $conn = Get-PbiConnection
  try {
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = @"
EVALUATE
SELECTCOLUMNS(
    Fact_BCP,
    "id", Fact_BCP[Employee ID],
    "name", Fact_BCP[Full Name],
    "account", Fact_BCP[Account],
    "lob", Fact_BCP[Line of Business],
    "office", Fact_BCP[Office Site],
    "city", Fact_BCP[Municipality/City],
    "province", Fact_BCP[Province],
    "region", Fact_BCP[Region(regional designation).1],
    "island", Fact_BCP[Island group],
    "status", Fact_BCP[BCP Status],
    "impact", Fact_BCP[Impact Type],
    "issue", Fact_BCP[Type of BCP Issue],
    "help", Fact_BCP[Needed Help],
    "remarks", Fact_BCP[Remarks]
)
"@
    $reader = $cmd.ExecuteReader()
    $rows = New-Object System.Collections.ArrayList
    while ($reader.Read()) {
      $obj = [ordered]@{}
      for ($i = 0; $i -lt $reader.FieldCount; $i++) {
        $name = $reader.GetName($i).Trim('[', ']')
        $obj[$name] = $reader.GetValue($i)
      }
      [void]$rows.Add([pscustomobject]$obj)
    }
    $reader.Close()
    return , $rows.ToArray()
  } finally {
    $conn.Close()
  }
}

# Windows PowerShell 5.1 has no ConvertTo-Json -AsArray; a single-item
# collection collapses to a bare object, so wrap that case manually.
function ConvertTo-JsonArray {
  param([Parameter(ValueFromPipeline)] $Rows)
  $json = $Rows | ConvertTo-Json -Depth 3
  if (@($Rows).Count -eq 1) { $json = "[$json]" }
  return $json
}
