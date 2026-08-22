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

  This only ever serves YOUR OWN machine's localhost — see bcp_publish.ps1
  for the scheduled-snapshot approach that lets other viewers on a hosted
  copy of the dashboard see (periodically refreshed) data too.

  Usage:
    1. Open Heatmap.pbix in Power BI Desktop and leave it running.
    2. Run this script:  powershell -ExecutionPolicy Bypass -File bcp_bridge.ps1
    3. Leave this window open. Open/refresh Heatmap_Dashboard.html in a browser.
    4. Press Ctrl+C here to stop the bridge.
#>

param(
  [int]$Port = 8790
)

. (Join-Path $PSScriptRoot 'bcp_common.ps1')

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
      $json = Get-FactBcpRows | ConvertTo-JsonArray
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
