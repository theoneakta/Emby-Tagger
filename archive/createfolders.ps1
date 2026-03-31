# 1. Define your target path
$targetRoot = 'C:\Users\mbmon\OneDrive - aktasolutions\emby tags\Output'

# 2. Import CSV and MANUALLY name the columns H1, H2, H3 to avoid the warning
# Change the number of "H" headers to match the number of columns in your file
$csvData = Import-Csv -Path 'exportpathemby.csv' -Header "H1","H2","H3"

foreach ($row in $csvData) {
    # This collects all values from the row and joins them with backslashes
    # Example: Row values "Movies", "Action", "2024" becomes "Movies\Action\2024"
    $subPath = ($row.PSObject.Properties.Value | Where-Object { $_ -and $_.Trim() }) -join "\"
    
    if ($subPath) {
        $fullPath = Join-Path -Path $targetRoot -ChildPath $subPath
        
        # Create the full folder tree
        if (-not (Test-Path -Path $fullPath)) {
            New-Item -Path $fullPath -ItemType Directory -Force | Out-Null
            Write-Host "Created: $subPath" -ForegroundColor Green
        }
    }
}
