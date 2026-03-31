# ============================================================
#  Get-EmbyUntaggedMovies.ps1
#
#  Connects to Emby and exports all movies with no tags to a CSV.
#
#  Usage:
#    .\Get-EmbyUntaggedMovies.ps1
# ============================================================

# ── Load .env ────────────────────────────────────────────────
$envFile = Join-Path $PSScriptRoot ".env"
if (-not (Test-Path $envFile)) {
    Write-Host "ERROR: .env file not found at $envFile" -ForegroundColor Red
    exit 1
}

$envVars = @{}
foreach ($line in Get-Content $envFile) {
    if ($line -match '^\s*#') { continue }
    if ($line -match '^\s*$') { continue }
    if ($line -match '^([^=]+)=(.*)$') {
        $envVars[$matches[1].Trim()] = $matches[2].Trim().Trim('"').Trim("'")
    }
}

$EmbyServer = $envVars["EMBY_SERVER"]
$ApiKey     = $envVars["EMBY_API_KEY"]
$UserId     = $envVars["EMBY_USER_ID"]

if (-not $EmbyServer -or -not $ApiKey -or -not $UserId) {
    Write-Host "ERROR: .env must define EMBY_SERVER, EMBY_API_KEY, and EMBY_USER_ID" -ForegroundColor Red
    exit 1
}

$headers = @{ "X-Emby-Token" = $ApiKey }

# ── Fetch all movies ─────────────────────────────────────────
Write-Host "[+] Fetching all movies from Emby..." -ForegroundColor Cyan
try {
    $resp = Invoke-RestMethod `
        -Uri "$EmbyServer/Users/$UserId/Items?IncludeItemTypes=Movie&Recursive=true&Fields=Tags,TagItems,Path,ProductionYear" `
        -Headers $headers
} catch {
    Write-Host "ERROR: Could not reach Emby." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

Write-Host "    Found $($resp.TotalRecordCount) movies total." -ForegroundColor Green

# ── Filter untagged ──────────────────────────────────────────
$untagged = $resp.Items | Where-Object {
    -not $_.TagItems -or $_.TagItems.Count -eq 0
} | ForEach-Object {
    [PSCustomObject]@{
        Name   = $_.Name
        Year   = $_.ProductionYear
        EmbyId = $_.Id
        Path   = $_.Path
    }
} | Sort-Object Name

Write-Host "    $($untagged.Count) movies have no tags." -ForegroundColor Yellow

# ── Export CSV ───────────────────────────────────────────────
$csvPath = Join-Path $PSScriptRoot "untagged_movies.csv"
$untagged | Export-Csv -Path $csvPath -NoTypeInformation
Write-Host "`n  Saved to: $csvPath" -ForegroundColor Green