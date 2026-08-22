<#
  bcp_bridge.ps1
  Local data bridge for Heatmap_Dashboard.html.

  Power BI Desktop's local Analysis Services engine cannot be reached directly
  from a browser (no HTTP/CORS support, ADOMD.NET is a .NET-only API). This
  script is the missing middle tier: it re-discovers the running PBI Desktop
  instance on every request (so it survives the .pbix being closed/reopened,
  which changes both the port and the catalog GUID), queries Fact_BCP live,
  and serves the result as JSON over plain HTTP so the dashboard's fetch()
  call can read it.

  Usage:
    1. Open Heatmap.pbix in Power BI Desktop and leave it running.
    2. Run this script:  powershell -ExecutionPolicy Bypass -File bcp_bridge.ps1
    3. Leave this window open. Open/refresh Heatmap_Dashboard.html in a browser.
    4. Press Ctrl+C here to stop the bridge.
#>

param(
  [int]$Port = 8790
)

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

function Get-FactBcpJson {
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
    # Windows PowerShell 5.1 has no -AsArray; ConvertTo-Json collapses a
    # single-item collection to a bare object, so wrap that case manually.
    $json = $rows | ConvertTo-Json -Depth 3
    if ($rows.Count -eq 1) { $json = "[$json]" }
    return $json
  } finally {
    $conn.Close()
  }
}

$adomdPath = Get-AdomdAssemblyPath
Add-Type -Path $adomdPath
Write-Host "Loaded ADOMD.NET from: $adomdPath"

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Host "BCP data bridge listening on http://localhost:$Port/data"
Write-Host "Leave this window open. Press Ctrl+C to stop."

try {
  while ($listener.IsListening) {
    $context = $listener.GetContext()
    $response = $context.Response

    # The dashboard is opened as a local file:// page, so browsers send
    # "Origin: null" (or omit Origin) for its fetch() calls. Only echo the
    # CORS header back in that case, instead of a wildcard "*" — a wildcard
    # would let ANY website open in another tab of the same browser also
    # read this live employee data while the bridge happens to be running.
    $origin = $context.Request.Headers["Origin"]
    if ([string]::IsNullOrEmpty($origin) -or $origin -eq "null") {
      $response.Headers.Add("Access-Control-Allow-Origin", "null")
      $response.Headers.Add("Access-Control-Allow-Methods", "GET, OPTIONS")
      $response.Headers.Add("Access-Control-Allow-Headers", "*")
    }

    try {
      if ($context.Request.HttpMethod -eq 'OPTIONS') {
        $response.StatusCode = 204
        $response.Close()
        continue
      }
      $json = Get-FactBcpJson
      $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
      $response.ContentType = "application/json"
      $response.StatusCode = 200
      $response.OutputStream.Write($bytes, 0, $bytes.Length)
      Write-Host "$(Get-Date -Format 'HH:mm:ss') 200 OK  /data ($($bytes.Length) bytes)"
    } catch {
      $errJson = (@{ error = $_.Exception.Message } | ConvertTo-Json)
      $bytes = [System.Text.Encoding]::UTF8.GetBytes($errJson)
      $response.ContentType = "application/json"
      $response.StatusCode = 503
      $response.OutputStream.Write($bytes, 0, $bytes.Length)
      Write-Host "$(Get-Date -Format 'HH:mm:ss') 503     /data -- $($_.Exception.Message)" -ForegroundColor Yellow
    } finally {
      $response.Close()
    }
  }
} finally {
  $listener.Stop()
  $listener.Close()
}
