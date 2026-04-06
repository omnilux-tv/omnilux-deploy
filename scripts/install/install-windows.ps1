#Requires -Version 5.1
<#
.SYNOPSIS
    OmniLux Windows Install Script

.DESCRIPTION
    Installs Node.js 22, pnpm, FFmpeg, builds the project, and optionally
    creates a Windows Service for auto-start.

.PARAMETER Port
    Server port (default: 4000)

.PARAMETER DataDir
    Data directory (default: $env:LOCALAPPDATA\OmniLux)

.PARAMETER SkipService
    Don't create the Windows Service

.PARAMETER SkipBuild
    Don't run pnpm install/build

.PARAMETER SkipOptional
    Don't show optional dependency info

.PARAMETER Help
    Show help message
#>

param(
    [int]$Port = 4000,
    [string]$DataDir = "",
    [switch]$SkipService,
    [switch]$SkipBuild,
    [switch]$SkipOptional,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = (Resolve-Path (Join-Path $ScriptDir "..\..")).Path
$DefaultPort = 4000

if (-not $Port) { $Port = if ($env:PORT) { [int]$env:PORT } else { $DefaultPort } }
if (-not $DataDir) { $DataDir = if ($env:OMNILUX_DATA_DIR) { $env:OMNILUX_DATA_DIR } else { Join-Path $env:LOCALAPPDATA "OmniLux" } }

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Write-Info  { param([string]$Message) Write-Host "[info]  $Message" -ForegroundColor Blue }
function Write-Ok    { param([string]$Message) Write-Host "[ok]    $Message" -ForegroundColor Green }
function Write-Warn  { param([string]$Message) Write-Host "[warn]  $Message" -ForegroundColor Yellow }
function Write-Err   { param([string]$Message) Write-Host "[error] $Message" -ForegroundColor Red; exit 1 }
function Write-Step  { param([string]$Message) Write-Host "`n==> $Message" -ForegroundColor White -BackgroundColor DarkGray }

function Test-Command { param([string]$Name) return [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal $identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
if ($Help) {
    @"
Usage: .\install-windows.ps1 [OPTIONS]

Install OmniLux on Windows.

Options:
  -Port <number>       Server port (default: 4000)
  -DataDir <path>      Data directory (default: %LOCALAPPDATA%\OmniLux)
  -SkipService         Don't create the Windows Service
  -SkipBuild           Don't run pnpm install/build
  -SkipOptional        Don't show optional dependency info
  -Help                Show this help message

Environment variables:
  PORT                 Server port (default: 4000)
  OMNILUX_DATA_DIR     Data directory path
  OMNILUX_DB_PATH      Database file path
  OMNILUX_LIBRARY_ROOT Media library root path
  OMNILUX_DOWNLOAD_PATH Download directory path
"@
    exit 0
}

# ---------------------------------------------------------------------------
# Detect package manager
# ---------------------------------------------------------------------------
$HasWinget = Test-Command "winget"
$HasChoco = Test-Command "choco"

if (-not $HasWinget -and -not $HasChoco) {
    Write-Warn "Neither winget nor chocolatey found."
    Write-Info "winget is included with Windows 10/11. If unavailable, install Chocolatey:"
    Write-Info "  https://chocolatey.org/install"
    Write-Err "No package manager available. Install winget or chocolatey first."
}

$PkgManager = if ($HasWinget) { "winget" } else { "choco" }

# ---------------------------------------------------------------------------
# Start
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "  ___                  _ _                " -ForegroundColor Green
Write-Host " / _ \ _ __ ___  _ __ (_) |   _   ___  __" -ForegroundColor Green
Write-Host "| | | | '_ `` _ \| '_ \| | |  | | | \ \/ /" -ForegroundColor Green
Write-Host "| |_| | | | | | | | | | | |__| |_| |>  < " -ForegroundColor Green
Write-Host " \___/|_| |_| |_|_| |_|_|_____\__,_/_/\_\" -ForegroundColor Green
Write-Host ""

Write-Step "Installing OmniLux on Windows"
Write-Info "Repo root:       $RepoRoot"
Write-Info "Data dir:        $DataDir"
Write-Info "Port:            $Port"
Write-Info "Package manager: $PkgManager"

# ---------------------------------------------------------------------------
# Node.js 22
# ---------------------------------------------------------------------------
Write-Step "Checking Node.js 22"

$NeedNode = $true

if (Test-Command "node") {
    $NodeVersion = & node --version 2>$null
    $NodeMajor = [int]($NodeVersion -replace 'v(\d+)\..*', '$1')
    if ($NodeMajor -eq 22) {
        Write-Ok "Node.js $NodeVersion is installed"
        $NeedNode = $false
    } else {
        Write-Warn "Node.js $NodeVersion found, but 22.x is required"
    }
}

if ($NeedNode) {
    Write-Info "Installing Node.js 22..."
    if ($PkgManager -eq "winget") {
        winget install --id OpenJS.NodeJS.LTS --version "22.*" --accept-source-agreements --accept-package-agreements --silent
    } else {
        choco install nodejs-lts --version=22 -y
    }

    # Refresh PATH
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")

    if (-not (Test-Command "node")) {
        Write-Err "Node.js installation failed. Please install Node.js 22 manually from https://nodejs.org"
    }

    $NodeVersion = & node --version
    $NodeMajor = [int]($NodeVersion -replace 'v(\d+)\..*', '$1')
    if ($NodeMajor -ne 22) {
        Write-Err "Node.js 22 required but $NodeVersion is installed"
    }
    Write-Ok "Node.js $NodeVersion installed"
}

# ---------------------------------------------------------------------------
# pnpm
# ---------------------------------------------------------------------------
Write-Step "Checking pnpm"

if (Test-Command "pnpm") {
    $PnpmVersion = & pnpm --version 2>$null
    Write-Ok "pnpm $PnpmVersion is installed"
} else {
    Write-Info "Enabling pnpm via corepack..."
    try {
        corepack enable
        corepack prepare pnpm@latest --activate 2>$null
    } catch {
        Write-Info "corepack failed, installing pnpm via npm..."
        npm install -g pnpm
    }

    # Refresh PATH
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")

    if (-not (Test-Command "pnpm")) {
        Write-Err "pnpm installation failed. Install manually: npm install -g pnpm"
    }
    Write-Ok "pnpm $(& pnpm --version) installed"
}

# ---------------------------------------------------------------------------
# FFmpeg
# ---------------------------------------------------------------------------
Write-Step "Checking FFmpeg"

if (Test-Command "ffmpeg") {
    Write-Ok "FFmpeg is installed"
} else {
    Write-Info "Installing FFmpeg..."
    try {
        if ($PkgManager -eq "winget") {
            winget install --id Gyan.FFmpeg --accept-source-agreements --accept-package-agreements --silent
        } else {
            choco install ffmpeg -y
        }

        # Refresh PATH
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")

        if (Test-Command "ffmpeg") {
            Write-Ok "FFmpeg installed"
        } else {
            Write-Warn "FFmpeg installed but not in PATH. You may need to restart your terminal."
        }
    } catch {
        Write-Warn "FFmpeg installation failed (optional -- streaming/transcoding will be limited)"
    }
}

# ---------------------------------------------------------------------------
# Optional dependencies
# ---------------------------------------------------------------------------
if (-not $SkipOptional) {
    Write-Step "Optional dependencies"
    Write-Info "The following are optional and NOT required for basic operation:"
    if ($PkgManager -eq "winget") {
        Write-Info "  - WireGuard:  winget install WireGuard.WireGuard"
        Write-Info "  - Chromium:   winget install Hibbiki.Chromium"
    } else {
        Write-Info "  - WireGuard:  choco install wireguard -y"
        Write-Info "  - Chromium:   choco install chromium -y"
    }
    Write-Info "  - ClamAV:    Download from https://www.clamav.net/downloads"
    Write-Info ""
    Write-Info "Skipping optional dependencies. Install manually if needed."
}

# ---------------------------------------------------------------------------
# Data directories
# ---------------------------------------------------------------------------
Write-Step "Creating data directories"

$Dirs = @(
    $DataDir
    (Join-Path $DataDir "downloads")
    (Join-Path $DataDir "library")
    (Join-Path $DataDir "logs")
)

foreach ($Dir in $Dirs) {
    if (-not (Test-Path $Dir)) {
        New-Item -ItemType Directory -Path $Dir -Force | Out-Null
    }
}
Write-Ok "Data directories created at: $DataDir"

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
if (-not $SkipBuild) {
    Write-Step "Installing dependencies and building"

    Push-Location $RepoRoot
    try {
        Write-Info "Running pnpm install..."
        & pnpm install --frozen-lockfile 2>$null
        if ($LASTEXITCODE -ne 0) {
            & pnpm install
        }
        Write-Ok "Dependencies installed"

        Write-Info "Running pnpm build..."
        & pnpm build
        if ($LASTEXITCODE -ne 0) {
            Write-Err "Build failed"
        }
        Write-Ok "Build complete"
    } finally {
        Pop-Location
    }
} else {
    Write-Info "Skipping build (-SkipBuild)"
}

# ---------------------------------------------------------------------------
# Environment variables (persistent, user-level)
# ---------------------------------------------------------------------------
Write-Step "Setting environment variables"

$OmniluxDbPath = if ($env:OMNILUX_DB_PATH) { $env:OMNILUX_DB_PATH } else { Join-Path $DataDir "omnilux.db" }
$OmniluxLibraryRoot = if ($env:OMNILUX_LIBRARY_ROOT) { $env:OMNILUX_LIBRARY_ROOT } else { Join-Path $DataDir "library" }
$OmniluxDownloadPath = if ($env:OMNILUX_DOWNLOAD_PATH) { $env:OMNILUX_DOWNLOAD_PATH } else { Join-Path $DataDir "downloads" }

$EnvVars = @{
    "OMNILUX_DATA_DIR"     = $DataDir
    "OMNILUX_DB_PATH"      = $OmniluxDbPath
    "OMNILUX_LIBRARY_ROOT" = $OmniluxLibraryRoot
    "OMNILUX_DOWNLOAD_PATH" = $OmniluxDownloadPath
}

foreach ($Key in $EnvVars.Keys) {
    $Existing = [System.Environment]::GetEnvironmentVariable($Key, "User")
    if (-not $Existing) {
        [System.Environment]::SetEnvironmentVariable($Key, $EnvVars[$Key], "User")
        Write-Info "Set $Key = $($EnvVars[$Key])"
    } else {
        Write-Info "$Key already set: $Existing"
    }
}
Write-Ok "Environment variables configured"

# ---------------------------------------------------------------------------
# Windows Service (optional, requires admin)
# ---------------------------------------------------------------------------
$ServiceName = "OmniLux"

if (-not $SkipService) {
    Write-Step "Windows Service setup"

    if (-not (Test-Admin)) {
        Write-Warn "Not running as Administrator. Skipping service creation."
        Write-Info "To create the service, re-run this script as Administrator."
        Write-Info "Or run OmniLux manually:"
        Write-Info "  cd $RepoRoot"
        Write-Info "  node apps\server\dist\index.js"
    } else {
        $NodeExe = (Get-Command node).Source

        # Check if NSSM is available for better service management
        if (Test-Command "nssm") {
            Write-Info "Creating service via NSSM..."

            # Remove existing service if present
            & nssm status $ServiceName 2>$null
            if ($LASTEXITCODE -eq 0) {
                & nssm stop $ServiceName 2>$null
                & nssm remove $ServiceName confirm 2>$null
            }

            & nssm install $ServiceName $NodeExe "apps\server\dist\index.js"
            & nssm set $ServiceName AppDirectory $RepoRoot
            & nssm set $ServiceName AppEnvironmentExtra "NODE_ENV=production" "PORT=$Port" "OMNILUX_DB_PATH=$OmniluxDbPath" "OMNILUX_LIBRARY_ROOT=$OmniluxLibraryRoot" "OMNILUX_DOWNLOAD_PATH=$OmniluxDownloadPath"
            & nssm set $ServiceName DisplayName "OmniLux Media Server"
            & nssm set $ServiceName Description "All-in-one media automation platform"
            & nssm set $ServiceName Start SERVICE_AUTO_START
            & nssm set $ServiceName AppStdout (Join-Path $DataDir "logs\omnilux.log")
            & nssm set $ServiceName AppStderr (Join-Path $DataDir "logs\omnilux-error.log")
            & nssm set $ServiceName AppRotateFiles 1
            & nssm set $ServiceName AppRotateBytes 10485760

            & nssm start $ServiceName
            Write-Ok "Service created and started via NSSM"
        } else {
            Write-Info "NSSM not found. Creating service via sc.exe..."
            Write-Info "For better service management, install NSSM: choco install nssm -y"

            # sc.exe requires the full command as a single binPath argument
            $BinPath = "`"$NodeExe`" `"$(Join-Path $RepoRoot 'apps\server\dist\index.js')`""

            # Remove existing service
            $ExistingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
            if ($ExistingService) {
                Write-Info "Removing existing service..."
                Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
                & sc.exe delete $ServiceName 2>$null
                Start-Sleep -Seconds 2
            }

            & sc.exe create $ServiceName binPath= $BinPath start= auto DisplayName= "OmniLux Media Server"
            & sc.exe description $ServiceName "All-in-one media automation platform"

            # Note: sc.exe services don't support WorkingDirectory natively.
            # The service will need a wrapper script or NSSM for proper directory handling.
            Write-Warn "sc.exe services have limited support for WorkingDirectory."
            Write-Warn "For production use, install NSSM (choco install nssm -y) and re-run."

            try {
                Start-Service -Name $ServiceName
                Write-Ok "Service created and started"
            } catch {
                Write-Warn "Service created but failed to start. This is expected with sc.exe."
                Write-Info "Recommended: install NSSM and re-run this script."
            }
        }
    }
} else {
    Write-Info "Skipping service creation (-SkipService)"
}

# ---------------------------------------------------------------------------
# Firewall rule
# ---------------------------------------------------------------------------
if (Test-Admin) {
    Write-Step "Configuring firewall"
    $RuleName = "OmniLux Server (TCP $Port)"
    $ExistingRule = Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue
    if (-not $ExistingRule) {
        New-NetFirewallRule -DisplayName $RuleName -Direction Inbound -Protocol TCP -LocalPort $Port -Action Allow | Out-Null
        Write-Ok "Firewall rule created for port $Port"
    } else {
        Write-Ok "Firewall rule already exists for port $Port"
    }
}

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "  ___                  _ _                " -ForegroundColor Green
Write-Host " / _ \ _ __ ___  _ __ (_) |   _   ___  __" -ForegroundColor Green
Write-Host "| | | | '_ `` _ \| '_ \| | |  | | | \ \/ /" -ForegroundColor Green
Write-Host "| |_| | | | | | | | | | | |__| |_| |>  < " -ForegroundColor Green
Write-Host " \___/|_| |_| |_|_| |_|_|_____\__,_/_/\_\" -ForegroundColor Green
Write-Host ""

Write-Ok "OmniLux installed successfully!"
Write-Host ""
Write-Info "Server URL:      http://localhost:$Port"
Write-Info "Data directory:  $DataDir"
Write-Info "Repo root:       $RepoRoot"
Write-Host ""
if (-not $SkipService) {
    if (Test-Admin) {
        Write-Info "Service commands (PowerShell as Admin):"
        Write-Info "  Status:  Get-Service OmniLux"
        Write-Info "  Stop:    Stop-Service OmniLux"
        Write-Info "  Start:   Start-Service OmniLux"
        Write-Info "  Logs:    Get-Content '$DataDir\logs\omnilux.log' -Tail 50 -Wait"
    }
} else {
    Write-Info "Manual start:"
    Write-Info "  cd $RepoRoot"
    Write-Info "  `$env:PORT=$Port; node apps\server\dist\index.js"
}
Write-Host ""
