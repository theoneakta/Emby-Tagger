# Emby Tagger

Two lightweight PowerShell scripts to audit and tag your Emby movie library using a CSV file. No folder structure or special setup needed — just point it at your Emby server, find what's untagged, fill in the tags, and apply them.

Useful for:
- First-time tagging of a new or existing library
- Cleaning up movies that slipped through without a tag
- Bulk-applying tags after a library rebuild (as a follow-up to the [Emby Tag Recovery Toolkit](./README-recovery.md))
- Ongoing maintenance as new movies are added

---

## Requirements

- PowerShell 7+ (uses `-AsHashtable` on `ConvertFrom-Json`)
- Network access to your Emby server
- An Emby API key

---

## Setup

### 1. Get your Emby API key
**Emby Dashboard → Advanced → Security → API Keys → create new**

### 2. Get your Emby User ID
```powershell
Invoke-RestMethod -Uri "http://YOUR_SERVER:8096/Users" `
    -Headers @{ "X-Emby-Token" = "YOUR_API_KEY" } |
    ForEach-Object { "$($_.Id)  $($_.Name)" }
```

### 3. Create your `.env` file
Place it in the same folder as the scripts:

```env
# Emby server URL — no trailing slash, use IP:port for local servers
EMBY_SERVER=http://yourip:8096

# Emby API key
EMBY_API_KEY=your_api_key_here

# Your Emby user ID
EMBY_USER_ID=your_user_id_here
```

> **Tip:** Use the local IP and port rather than a domain name — external URLs can cause auth issues with the Emby API.

---

## Scripts

### `Get-EmbyUntaggedMovies.ps1`
Connects to Emby and exports every movie that has no tags to a CSV file.

```powershell
.\Get-EmbyUntaggedMovies.ps1
```

**Output:** `untagged_movies.csv` in the same folder as the script:

```csv
Name,Year,EmbyId,Path
Spectre,2015,3842217,D:\Movies\Spectre
Inception,2010,3841100,D:\Movies\Inception
The Raid,2011,3841500,D:\Movies\The Raid
```

Open the CSV, add a `Tag` column, and fill in the genre for each movie. That file is then ready to feed into `Import-EmbyTagsFromCsv.ps1`.

---

### `Import-EmbyTagsFromCsv.ps1`
Reads a CSV with a `Tag` column and applies each tag to the matching movie in Emby. Uses the `EmbyId` to identify movies precisely — no fuzzy matching needed.

```powershell
# Dry run — preview what will be tagged, nothing written
.\Import-EmbyTagsFromCsv.ps1 -CsvPath ".\untagged_movies.csv" -WhatIf

# Live run
.\Import-EmbyTagsFromCsv.ps1 -CsvPath ".\untagged_movies.csv"
```

**CSV format** — add a `Tag` column to the untagged export and fill it in:

```csv
Name,Year,EmbyId,Tag
Spectre,2015,3842217,Action
Inception,2010,3841100,Sci-Fi
The Raid,2011,3841500,Martial Arts
```

- `EmbyId` and `Tag` are the only required columns — `Name` and `Year` are for your reference
- To apply **multiple tags** to one movie, add multiple rows with the same `EmbyId`:
  ```csv
  Aliens,1986,3840001,Action
  Aliens,1986,3840001,Sci-Fi
  ```
- Rows with a blank `Tag` are skipped automatically
- Movies that already have the tag are skipped — safe to re-run the same CSV multiple times

---

## Workflow

```
1. Run Get-EmbyUntaggedMovies.ps1
      → produces untagged_movies.csv

2. Open untagged_movies.csv in Excel or any spreadsheet app
      → add a Tag column
      → fill in the genre for each movie

3. Run Import-EmbyTagsFromCsv.ps1 -CsvPath ".\untagged_movies.csv" -WhatIf
      → preview what will be tagged

4. Run Import-EmbyTagsFromCsv.ps1 -CsvPath ".\untagged_movies.csv"
      → tags are applied to Emby

5. Re-run Get-EmbyUntaggedMovies.ps1 to confirm nothing is left untagged
```

---

## Files Reference

| File | Purpose |
|------|---------|
| `.env` | Config — server URL, API key, user ID |
| `Get-EmbyUntaggedMovies.ps1` | Export all untagged movies to CSV |
| `Import-EmbyTagsFromCsv.ps1` | Apply tags to Emby from a CSV |
| `untagged_movies.csv` | Output — movies with no tags *(generated)* |