# Strawberry MCP — installer for Windows (PowerShell).
#
#   irm https://raw.githubusercontent.com/redslayer34/strawberry-hub/claude/repo-exploration-ez26bn/mcp/install.ps1 | iex
#
# Installs into %USERPROFILE%\StrawberryMCP (again = update; the token and
# Cobalt.luau are kept), installs the dependencies, finds Cobalt.luau in
# Downloads, opens port 7777 for the private network, registers the MCP in
# Claude Code (user scope) and prints the line for Arceus X.

$ErrorActionPreference = "Stop"
$Branch = "claude/repo-exploration-ez26bn"
$Zip = "https://github.com/redslayer34/strawberry-hub/archive/refs/heads/$Branch.zip"
$Dir = Join-Path $env:USERPROFILE "StrawberryMCP"
$Port = 7777

function Step($text) { Write-Host "`n==> $text" -ForegroundColor Magenta }
function Ok($text) { Write-Host "    $text" -ForegroundColor Green }
function Warn($text) { Write-Host "    $text" -ForegroundColor Yellow }

# 1. Node.js
Step "Node.js"
$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) {
    Warn "Node.js not found: installing Node.js LTS with winget..."
    winget install -e --id OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
    $node = Get-Command node -ErrorAction SilentlyContinue
    if (-not $node) { throw "Node.js is still not found. Install it from https://nodejs.org (LTS), then run this again." }
}
$version = (& node --version)
if ([int]($version.TrimStart("v").Split(".")[0]) -lt 20) { throw "Node.js $version is too old: install Node.js 20 or newer (https://nodejs.org)." }
Ok "Node.js $version"

# 2. Files (the mcp folder of the branch)
Step "Downloading Strawberry MCP into $Dir"
$tmp = Join-Path $env:TEMP ("strawberry-mcp-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp | Out-Null
Invoke-WebRequest -Uri $Zip -OutFile (Join-Path $tmp "repo.zip") -UseBasicParsing
Expand-Archive -Path (Join-Path $tmp "repo.zip") -DestinationPath $tmp
$source = Get-ChildItem -Path $tmp -Directory | Where-Object { Test-Path (Join-Path $_.FullName "mcp") } | Select-Object -First 1
if (-not $source) { throw "The download has no mcp folder." }
New-Item -ItemType Directory -Force -Path $Dir | Out-Null
# .bridge-token, Cobalt.luau and node_modules are never in the zip: kept.
Copy-Item -Path (Join-Path $source.FullName "mcp\*") -Destination $Dir -Recurse -Force
Remove-Item -Recurse -Force $tmp
Ok "files in $Dir"

# 3. Dependencies
Step "Installing the dependencies (npm install)"
Push-Location $Dir
try { & npm install --omit=dev --no-audit --no-fund | Out-Host } finally { Pop-Location }
Ok "dependencies installed"

# 4. Cobalt.luau
Step "Cobalt.luau"
$cobalt = Join-Path $Dir "Cobalt.luau"
if (Test-Path $cobalt) {
    Ok "already there"
} else {
    $found = Get-ChildItem -Path (Join-Path $env:USERPROFILE "Downloads"), (Join-Path $env:USERPROFILE "Desktop") -Filter "*obalt*.lua*" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($found) {
        Copy-Item $found.FullName $cobalt
        Ok "copied from $($found.FullName)"
    } else {
        Warn "not found: put your Cobalt.luau in $Dir (remote_spy_start needs it)"
    }
}

# 5. Firewall (MuMu reaches the PC over the network)
Step "Firewall: port $Port (private network)"
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($admin) {
    if (-not (Get-NetFirewallRule -DisplayName "Strawberry MCP" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName "Strawberry MCP" -Direction Inbound -Protocol TCP -LocalPort $Port -Action Allow -Profile Private | Out-Null
    }
    Ok "rule 'Strawberry MCP' in place"
} else {
    Warn "not run as administrator: Windows will ask to allow Node the first time (choose Private networks),"
    Warn "or run this in an administrator PowerShell to add the rule now."
}

# 6. Claude Code
Step "Claude Code"
$server = Join-Path $Dir "src\server.js"
$claude = Get-Command claude -ErrorAction SilentlyContinue
if ($claude) {
    try { & claude mcp remove strawberry --scope user *> $null } catch { }
    & claude mcp add --scope user strawberry -- node "$server" | Out-Host
    Ok "MCP 'strawberry' registered for your user (claude mcp list to check)"
} else {
    Warn "the claude command was not found. Install Claude Code, then run:"
    Write-Host "    claude mcp add --scope user strawberry -- node `"$server`""
}

# 7. The line for Arceus X
Step "Line to run in Arceus X (pick the address of your PC on the network)"
Push-Location $Dir
try { & node src\loader.js | Out-Host } finally { Pop-Location }
Write-Host "Then in Claude Code: ask for roblox_status, it should say connected." -ForegroundColor Cyan
