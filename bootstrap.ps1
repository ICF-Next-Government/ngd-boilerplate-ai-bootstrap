# NGD AI Boilerplate — public bootstrap for private repo access.
#
# Usage:
#   irm https://raw.githubusercontent.com/ICF-Next-Government/ngd-boilerplate-ai-bootstrap/main/bootstrap.ps1 | iex
#
# What it does:
#   1. Installs GitHub CLI via winget (if missing)
#   2. Authenticates with GitHub (browser-based login)
#   3. Downloads and runs the real installer from the private repo
#   4. Cleans up anything it installed
#
# The real installer handles everything else (git, uv, Python,
# practice selection, tool config). This script only bridges
# the authentication gap.

$ErrorActionPreference = "Stop"

$Repo = "ICF-Next-Government/ngd-boilerplate-ai"

# Track what we install so we can clean up
$script:InstalledGh = $false

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Write-Info($msg)  { Write-Host "==> " -ForegroundColor Blue -NoNewline; Write-Host $msg }
function Write-Err($msg)   { Write-Host "Error: " -ForegroundColor Red -NoNewline; Write-Host $msg }
function Write-Bold($msg)  { Write-Host $msg -ForegroundColor White }

function Test-Command($name) { $null -ne (Get-Command $name -ErrorAction SilentlyContinue) }

function Cleanup-Deps {
    if ($script:InstalledGh) {
        Write-Info "Removing GitHub CLI (installed temporarily)..."
        winget uninstall --id GitHub.cli --silent 2>$null
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

function Main {
    Write-Host ""
    Write-Bold "NGD AI Boilerplate — Bootstrap"
    Write-Host ""

    # 1. Ensure winget is available
    if (-not (Test-Command winget)) {
        Write-Err "winget is required but not found. It should be pre-installed on Windows 10/11."
        Write-Host "  Install 'App Installer' from the Microsoft Store if missing."
        exit 1
    }

    # 2. Ensure GitHub CLI
    if (-not (Test-Command gh)) {
        Write-Info "Installing GitHub CLI..."
        winget install --id GitHub.cli -e --source winget `
            --accept-package-agreements --accept-source-agreements --silent
        # Refresh PATH so we can find gh
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                     [System.Environment]::GetEnvironmentVariable("Path", "User")
        if (-not (Test-Command gh)) {
            Write-Err "GitHub CLI installation failed. Please restart PowerShell and try again."
            exit 1
        }
        $script:InstalledGh = $true
    }

    # 3. Authenticate
    $authStatus = gh auth status 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Info "You need to log in to GitHub. A browser window will open."
        Write-Host ""
        gh auth login --git-protocol https
    } else {
        Write-Info "GitHub authentication found."
    }

    # 4. Download and run the real installer
    Write-Info "Downloading installer..."
    $tmp = New-TemporaryFile
    try {
        $content = gh api "repos/$Repo/contents/bin/install.ps1" --jq '.content'
        if ($LASTEXITCODE -ne 0) {
            throw "API call failed"
        }
        if (-not $content -or $content -eq "null") {
            throw "Empty or null content returned"
        }
        [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($content)) |
            Set-Content -Path $tmp.FullName -Encoding UTF8
    } catch {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        Write-Err "Failed to download the installer. Do you have access to the $Repo repository?"
        exit 1
    }

    # Validate the downloaded script. The GitHub Contents API returns null
    # content for files over 1MB, which would produce garbage or an empty file.
    $fileSize = (Get-Item $tmp.FullName).Length
    if ($fileSize -lt 100) {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        Write-Err "Downloaded installer is too small ($fileSize bytes); likely truncated or empty."
        exit 1
    }

    Write-Host ""
    Write-Info "Handing off to the main installer..."
    Write-Host ""

    # Run as a subprocess (not dot-source). Each script tracks what it
    # installed and cleans up only those items. Subprocess isolation keeps
    # the two cleanup scopes independent.
    try {
        & powershell -ExecutionPolicy Bypass -File $tmp.FullName
    } finally {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }

    # 5. Clean up what we installed (success path only)
    Cleanup-Deps
}

Main
