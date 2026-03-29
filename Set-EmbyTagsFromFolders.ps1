# ============================================================
#  Set-EmbyTagsFromFolders.ps1
#
#  Reads a .env file for config, then walks your empty folder
#  tree and applies genre tags to matching Emby movies via API.
#
#  Folder structure expected:
#    $FoldersRoot\
#      [Comedy]\
#        Bad.Moms.2016.BRRip.XViD-ETRG\
#        Barbie (2023) [720p] [WEBRip] [YTS.MX]\
#      [Horror]\
#        Nope (2022) [720p] [WEBRip]\
#
#  Usage:
#    .\Set-EmbyTagsFromFolders.ps1            # live run
#    .\Set-EmbyTagsFromFolders.ps1 -WhatIf   # dry run, no changes made
# ============================================================

param(
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

$EmbyServer  = $envVars["EMBY_SERVER"]
$ApiKey      = $envVars["EMBY_API_KEY"]
$UserId      = $envVars["EMBY_USER_ID"]
$FoldersRoot = $envVars["FOLDERS_ROOT"]

if (-not $EmbyServer -or -not $ApiKey -or -not $UserId -or -not $FoldersRoot) {
    Write-Host "ERROR: .env must define EMBY_SERVER, EMBY_API_KEY, EMBY_USER_ID, and FOLDERS_ROOT" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $FoldersRoot)) {
    Write-Host "ERROR: FOLDERS_ROOT not found: $FoldersRoot" -ForegroundColor Red
    exit 1
}

if ($WhatIf) {
    Write-Host "`n*** DRY RUN MODE — no changes will be made to Emby ***`n" -ForegroundColor Magenta
}

$headers = @{ "X-Emby-Token" = $ApiKey }

# ── Title cleaning ───────────────────────────────────────────
function Clean-Title($raw) {
    $s = $raw

    # 1. Strip file extension — with OR without a dot before it
    #    Handles: "Firewall.mp4"  AND  "Firewall mp4"  AND  "The Raid 2.mp4"
    $s = $s -replace '\s*\.(mkv|mp4|avi|m4v|mov|wmv|flv|ts)$', ''
    $s = $s -replace '\s+(mkv|mp4|avi|m4v|mov|wmv|flv|ts)$',   ''

    # 2. Strip leading tracker/site prefix: "[ OxTorrent.com ] -" or "[ www.Torrenting.com ] -"
    #    Only fires when the prefix is wrapped in [ ] to avoid eating real title words
    $s = $s -replace '^\[\s*(?:www\.)?[A-Za-z0-9\-]+\.[a-z]{2,4}\s*\]\s*-?\s*', ''

    # 3. Strip leading [Genre] prefix: "[Comedy] Bad Moms"
    $s = $s -replace '^\[.*?\]\s*', ''

    # 4. Replace ALL dots with spaces — simple and safe
    $s = $s -replace '\.', ' '

    # 5. Remove everything from the year onward
    $s = $s -replace '[\[\(]?(19|20)\d{2}[\]\)]?.*$', ''

    # 6. Remove edition/quality words that appear before a year is found
    $s = $s -replace '(?i)\b(UNRATED|EXTENDED|THEATRICAL|DIRECTORS?\.?CUT|REMASTERED|REPACK|HC|LIMITED|INTERNAL|UNCENSORED|FRENCH|TRUEFRENCH|DVDRIP|BDRIP|BRRIP|WEBRIP|BLURAY|HDTV|HDRIP|XVID|H264|H265|HEVC|AAC|AC3|DTS|MULTI)\b.*$', ''

    # 7. Strip square/curly bracket blocks: [1080p] [YTS.MX] {5.1}
    $s = $s -replace '\[.*?\]', ''
    $s = $s -replace '\{.*?\}', ''

    # 8. Strip round-bracket blocks containing ONLY tech/descriptor words
    #    "(Action 1991)" "(Van Damme)" "(BluRay)" "(Dual)" "(stand up comedy)"
    $s = $s -replace '\([^)]*\b(Action|Adventure|BluRay|BRRip|WEBRip|HDRip|DVDRip|YTS|x264|x265|AAC|AC3|DTS|HDTV|Dual|Van Damme|Jean.Claude|Anime|stand up comedy|HDlight)\b[^)]*\)', ''

    # 9. Strip release-group suffix after a dash: "-ETRG" "-GalaxyRG" "- iExTV" "- Hon3y"
    $s = $s -replace '\s*-\s*[A-Za-z0-9][A-Za-z0-9\.\[\]]{1,25}$', ''

    # 10. Fix stray dot-space or space-dot sequences left after removal
    #     "Mission.Impossible. .Fallout" → "Mission Impossible Fallout"
    $s = $s -replace '\.\s+\.', ' '
    $s = $s -replace '\s+\.',   ' '
    $s = $s -replace '\.\s+',   ' '

    # 11. Tidy up
    $s = $s -replace '[_]+',      ' '   # underscores to spaces
    $s = $s -replace '\[\s*$',    ''    # trailing open bracket  "Virgin ["
    $s = $s -replace '\(\s*$',    ''    # trailing open paren    "double impact (action"  → done by step 8 partially, catch remainder
    $s = $s -replace '\s*-\s*$',  ''    # trailing dash
    $s = $s -replace '\s*\.\s*$', ''    # trailing dot
    $s = $s -replace '\s{2,}',    ' '   # collapse spaces
    $s = $s.Trim()

    return $s.ToLower()
}

# Light normalisation on Emby titles for lookup key
function Normalise-Emby($name) {
    $s = $name -replace '\s*\(\d{4}\)\s*$', ''
    return $s.ToLower().Trim()
}

# Bare alphanumeric only — for punctuation-blind comparison
# "Spider-Man" → "spiderman"   "Iron Man" → "ironman"   "U.N.C.L.E." → "uncle"
function Bare($s) {
    return ($s -replace '[^a-z0-9]', '')
}

# Word-overlap: fraction of meaningful words in $a that also appear in $b
function Word-Overlap($a, $b) {
    $wa = ($a -split '\s+') | Where-Object { $_.Length -gt 1 }
    $wb = ($b -split '\s+') | Where-Object { $_.Length -gt 1 }
    if ($wa.Count -eq 0) { return 0.0 }
    $shared = ($wa | Where-Object { $wb -contains $_ }).Count
    return [double]$shared / [double]$wa.Count
}

# ── Fetch all Emby movies once ───────────────────────────────
Write-Host "[+] Fetching all movies from Emby..." -ForegroundColor Cyan
try {
    $resp = Invoke-RestMethod `
        -Uri "$EmbyServer/Users/$UserId/Items?IncludeItemTypes=Movie&Recursive=true&Fields=Tags,TagItems" `
        -Headers $headers
} catch {
    Write-Host "ERROR: Could not reach Emby. Check EMBY_SERVER and EMBY_API_KEY." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
$allMovies = $resp.Items
Write-Host "    Found $($allMovies.Count) movies in Emby.`n" -ForegroundColor Green

# Build lookup: normalised Emby title → movie object
$lookup = @{}
foreach ($m in $allMovies) {
    $key = Normalise-Emby $m.Name
    if (-not $lookup.ContainsKey($key)) { $lookup[$key] = $m }
}

$stats     = @{ matched = 0; skipped = 0; already = 0 }
$unmatched = @()

# ── 5-strategy matcher ───────────────────────────────────────
function Find-Movie($cleaned) {

    # S1: Exact match
    if ($lookup.ContainsKey($cleaned)) { return $lookup[$cleaned] }

    # S2: Article-stripped match — ignore leading the/a/an on both sides
    $noArt = $cleaned -replace '^(the|a|an) ', ''
    $hit = $lookup.Keys | Where-Object {
        ($_ -replace '^(the|a|an) ', '') -eq $noArt
    } | Select-Object -First 1
    if ($hit) { return $lookup[$hit] }

    # S3: No-punctuation match — strip all non-alphanumeric before comparing
    #     "ironman" = "Iron Man"   "spiderman" = "Spider-Man"   "uncle" = "U.N.C.L.E."
    #     "billtedface" = "Bill & Ted Face the Music"
    $cleanedBare = Bare $cleaned
    if ($cleanedBare.Length -ge 4) {
        $hit = $lookup.Keys | Where-Object { (Bare $_) -eq $cleanedBare } | Select-Object -First 1
        if ($hit) { return $lookup[$hit] }
    }

    # S4: Bare prefix match — one bare title is a prefix of the other
    #     "terminator2" starts "terminator2judgmentday"
    #     "missionimpossiblefallout" matches "missionimpossiblefallout" with colons stripped
    if ($cleanedBare.Length -ge 6) {
        $hit = $lookup.Keys | Where-Object {
            $eb = Bare $_
            $eb.StartsWith($cleanedBare) -or $cleanedBare.StartsWith($eb)
        } | Select-Object -First 1
        if ($hit) { return $lookup[$hit] }
    }

    # S5: Word-overlap fuzzy match — 80%+ of our words appear in the Emby title
    #     Only fires with 3+ meaningful words to avoid short false-positives
    $words = ($cleaned -split '\s+') | Where-Object { $_.Length -gt 1 }
    if ($words.Count -ge 3) {
        $best      = $null
        $bestScore = 0.0
        foreach ($key in $lookup.Keys) {
            $score = Word-Overlap $cleaned $key
            if ($score -gt $bestScore) { $bestScore = $score; $best = $key }
        }
        if ($bestScore -ge 0.80) { return $lookup[$best] }
    }

    return $null
}

# ── Walk tag folders ─────────────────────────────────────────
foreach ($tagFolder in Get-ChildItem -Path $FoldersRoot -Directory) {

    # "[Comedy]" → "Comedy",  "Comedy" → "Comedy"
    $tag = $tagFolder.Name -replace '^\[|\]$', ''
    Write-Host "[TAG] $tag" -ForegroundColor Yellow

    foreach ($mFolder in Get-ChildItem -Path $tagFolder.FullName -Directory) {

        $cleaned = Clean-Title $mFolder.Name
        $movie   = Find-Movie $cleaned

        # No match
        if (-not $movie) {
            Write-Host "  x No match: $($mFolder.Name)  →  '$cleaned'" -ForegroundColor DarkGray
            $unmatched += [PSCustomObject]@{
                Tag          = $tag
                OrigFolder   = $mFolder.Name
                CleanedTitle = $cleaned
            }
            $stats.skipped++
            continue
        }

        # Already has this tag
        $existingTags = if ($movie.TagItems) { @($movie.TagItems) } else { @() }
        $existingTagNames = $existingTags | ForEach-Object { $_.Name }
        if ($existingTagNames -contains $tag) {
            Write-Host "  ~ Already tagged [$tag]: $($movie.Name)" -ForegroundColor DarkGray
            $stats.already++
            continue
        }

        # WhatIf preview
        if ($WhatIf) {
            Write-Host "  ? Would tag '$tag': $($movie.Name)  ←  '$($mFolder.Name)'" -ForegroundColor Cyan
            $stats.matched++
            continue
        }

        # Apply tag
        try {
            $itemId = $movie.Id

            # Fetch full item via user endpoint and convert to mutable hashtable
            $fullItem = Invoke-RestMethod -Uri "$EmbyServer/Users/$UserId/Items/$itemId" -Headers $headers
            $hash = $fullItem | ConvertTo-Json -Depth 10 | ConvertFrom-Json -AsHashtable

            # Append new tag to TagItems (Emby's actual tag field); Id=0 lets Emby assign its own Id
            $newTagItem  = @{ Name = $tag; Id = 0 }
            $hash["TagItems"] = @($hash["TagItems"] + $newTagItem)

            $body = $hash | ConvertTo-Json -Depth 10 -Compress

            # POST back to /Items/{id}
            Invoke-RestMethod -Uri "$EmbyServer/Items/$itemId" `
                -Headers $headers -Method Post -Body $body -ContentType "application/json" | Out-Null

            Write-Host "  + Tagged '$tag': $($movie.Name)" -ForegroundColor Green
            # Update in-memory so duplicate-tag check stays accurate this run
            $movie.TagItems = @($existingTags + @{ Name = $tag; Id = 0 })
            $stats.matched++
        } catch {
            $errMsg = $_.Exception.Message
            $errBody = $null
            try { $errBody = $_.ErrorDetails.Message } catch {}
            Write-Host "  ! ERROR tagging '$($movie.Name)': $errMsg" -ForegroundColor Red
            if ($errBody) { Write-Host "    Detail: $errBody" -ForegroundColor Red }
            Write-Host "    Item Id used: $itemId  Server: $EmbyServer" -ForegroundColor DarkRed
            $unmatched += [PSCustomObject]@{
                Tag          = $tag
                OrigFolder   = $mFolder.Name
                CleanedTitle = $cleaned
            }
            $stats.skipped++
        }
    }

    Write-Host ""
}

# ── Summary ──────────────────────────────────────────────────
$mode = if ($WhatIf) { "DRY RUN" } else { "DONE" }
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " $mode"
Write-Host "  $(if ($WhatIf) {'Would tag'} else {'Tags applied'}) : $($stats.matched)"
Write-Host "  Already set              : $($stats.already)"
Write-Host "  No match                 : $($stats.skipped)"
Write-Host "============================================" -ForegroundColor Cyan

if ($unmatched.Count -gt 0) {
    Write-Host "`nUnmatched — review CleanedTitle vs your Emby titles:" -ForegroundColor Red
    $unmatched | ForEach-Object {
        Write-Host "  [$($_.Tag)] $($_.OrigFolder)" -ForegroundColor Red
        Write-Host "       cleaned → '$($_.CleanedTitle)'" -ForegroundColor DarkRed
    }
    $csvPath = Join-Path $PSScriptRoot "unmatched.csv"
    $unmatched | Export-Csv -Path $csvPath -NoTypeInformation
    Write-Host "`n  Saved to: $csvPath" -ForegroundColor Yellow
    Write-Host "  Tip: CleanedTitle shows exactly what was compared against Emby." -ForegroundColor Yellow
}