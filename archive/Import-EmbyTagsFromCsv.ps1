# ============================================================
#  Import-EmbyTagsFromCsv.ps1
#
#  Reads a CSV with columns: Name, Year, EmbyId, Tag
#  and applies the Tag to each movie in Emby that is missing it.
#
#  CSV format (headers required):
#    Name,Year,EmbyId,Tag
#    Spectre,2015,3842217,Action
#    Inception,2010,3841100,Sci-Fi
#
#  Usage:
#    .\Import-EmbyTagsFromCsv.ps1 -CsvPath ".\tags.csv"
#    .\Import-EmbyTagsFromCsv.ps1 -CsvPath ".\tags.csv" -WhatIf
# ============================================================

param(
    [Parameter(Mandatory)]
    [string]$CsvPath,
    [switch]$WhatIf
)

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

# ── Load CSV ─────────────────────────────────────────────────
if (-not (Test-Path $CsvPath)) {
    Write-Host "ERROR: CSV not found at $CsvPath" -ForegroundColor Red
    exit 1
}

$rows = Import-Csv -Path $CsvPath

# Validate required columns
$required = @("EmbyId", "Tag")
foreach ($col in $required) {
    if ($rows.Count -gt 0 -and -not ($rows[0].PSObject.Properties.Name -contains $col)) {
        Write-Host "ERROR: CSV must have columns: Name, Year, EmbyId, Tag" -ForegroundColor Red
        exit 1
    }
}

# Skip rows with no Tag value
$rows = $rows | Where-Object { $_.Tag -and $_.Tag.Trim() -ne "" }
Write-Host "[+] Loaded $($rows.Count) rows from CSV." -ForegroundColor Cyan

if ($WhatIf) {
    Write-Host "`n*** DRY RUN MODE — no changes will be made to Emby ***`n" -ForegroundColor Magenta
}

$headers = @{ "X-Emby-Token" = $ApiKey }
$stats   = @{ applied = 0; already = 0; failed = 0 }

# ── Process each row ─────────────────────────────────────────
foreach ($row in $rows) {
    $itemId = $row.EmbyId.Trim()
    $tag    = $row.Tag.Trim()
    $label  = if ($row.Name) { "$($row.Name) ($($row.Year))" } else { "Id $itemId" }

    # Fetch current item
    try {
        $fullItem = Invoke-RestMethod -Uri "$EmbyServer/Users/$UserId/Items/$itemId" -Headers $headers
    } catch {
        Write-Host "  ! FETCH ERROR [$label]: $($_.Exception.Message)" -ForegroundColor Red
        $stats.failed++
        continue
    }

    # Check if tag already exists
    $existingTagNames = @()
    if ($fullItem.TagItems) {
        $existingTagNames = @($fullItem.TagItems | ForEach-Object { $_.Name })
    }

    if ($existingTagNames -contains $tag) {
        Write-Host "  ~ Already tagged [$tag]: $label" -ForegroundColor DarkGray
        $stats.already++
        continue
    }

    # Dry run
    if ($WhatIf) {
        Write-Host "  ? Would tag '$tag': $label" -ForegroundColor Cyan
        $stats.applied++
        continue
    }

    # Apply tag
    try {
        $hash = $fullItem | ConvertTo-Json -Depth 10 | ConvertFrom-Json -AsHashtable
        $hash["TagItems"] = @($hash["TagItems"] + @{ Name = $tag; Id = 0 })

        $body = $hash | ConvertTo-Json -Depth 10 -Compress
        Invoke-RestMethod -Uri "$EmbyServer/Items/$itemId" `
            -Headers $headers -Method Post -Body $body -ContentType "application/json" | Out-Null

        Write-Host "  + Tagged '$tag': $label" -ForegroundColor Green
        $stats.applied++
    } catch {
        $errMsg  = $_.Exception.Message
        $errBody = $null
        try { $errBody = $_.ErrorDetails.Message } catch {}
        Write-Host "  ! ERROR tagging '$label': $errMsg" -ForegroundColor Red
        if ($errBody) { Write-Host "    Detail: $errBody" -ForegroundColor Red }
        $stats.failed++
    }
}

# ── Summary ──────────────────────────────────────────────────
$mode = if ($WhatIf) { "DRY RUN" } else { "DONE" }
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " $mode"
Write-Host "  $(if ($WhatIf) {'Would apply'} else {'Tags applied'}) : $($stats.applied)"
Write-Host "  Already set              : $($stats.already)"
Write-Host "  Errors                   : $($stats.failed)"
Write-Host "============================================" -ForegroundColor Cyan