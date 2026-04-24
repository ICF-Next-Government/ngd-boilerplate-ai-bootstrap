# NGD AI Boilerplate — public bootstrap for private repo access.
#
# Usage:
#   irm https://raw.githubusercontent.com/ICF-Next-Government/ngd-boilerplate-ai-bootstrap/main/bootstrap.ps1 | iex
#
# What it does:
#   1. Installs dependencies (git, gh, uv) via winget if missing
#   2. Authenticates with GitHub (browser-based login)
#   3. Downloads and runs the real installer from the private repo
#   4. Cleans up uv (temporary); git, gh, and auth persist for ongoing use

$ErrorActionPreference = "Stop"

$Repo = "ICF-Next-Government/ngd-boilerplate-ai"

# Track what we install so we can clean up selectively
$script:InstalledUv = $false

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Write-Info($msg)  { Write-Host "🔹 $msg" }
function Write-Err($msg)   { Write-Host "❌ $msg" }
function Write-Bold($msg)  { Write-Host $msg -ForegroundColor White }

function Test-Command($name) { $null -ne (Get-Command $name -ErrorAction SilentlyContinue) }

function Cleanup-Deps {
    if (-not $script:InstalledUv) { return }

    Write-Info "Cleaning up temporary dependencies..."
    $uvPaths = @(
        (Join-Path $env:USERPROFILE ".local\bin\uv.exe"),
        (Join-Path $env:USERPROFILE ".local\bin\uvx.exe"),
        (Join-Path $env:USERPROFILE ".cargo\bin\uv.exe"),
        (Join-Path $env:USERPROFILE ".cargo\bin\uvx.exe")
    )
    foreach ($p in $uvPaths) {
        if (Test-Path $p) { Remove-Item $p -Force }
    }
    $uvData = Join-Path $env:LOCALAPPDATA "uv"
    if (Test-Path $uvData) { Remove-Item -Recurse -Force $uvData }

    # git, gh, and gh auth are kept intentionally.
    # The nightly usage analytics export requires git + gh credentials.
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

    # 2. Ensure git
    if (-not (Test-Command git)) {
        Write-Info "Installing git..."
        winget install --id Git.Git -e --source winget `
            --accept-package-agreements --accept-source-agreements --silent
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                     [System.Environment]::GetEnvironmentVariable("Path", "User")
        if (-not (Test-Command git)) {
            Write-Err "git installation failed. Please restart PowerShell and try again."
            exit 1
        }
    }

    # 3. Ensure GitHub CLI
    if (-not (Test-Command gh)) {
        Write-Info "Installing GitHub CLI..."
        winget install --id GitHub.cli -e --source winget `
            --accept-package-agreements --accept-source-agreements --silent
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                     [System.Environment]::GetEnvironmentVariable("Path", "User")
        if (-not (Test-Command gh)) {
            Write-Err "GitHub CLI installation failed. Please restart PowerShell and try again."
            exit 1
        }
    }

    # 4. Authenticate
    $authStatus = gh auth status 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Info "You need to log in to GitHub. A browser window will open."
        Write-Host ""
        gh auth login --git-protocol https
    } else {
        Write-Info "GitHub authentication found."
    }
    gh auth setup-git

    # 5. Ensure uv
    if (-not (Test-Command uv)) {
        Write-Info "Installing uv..."
        irm https://astral.sh/uv/install.ps1 | iex
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "User") + ";" + $env:Path
        if (-not (Test-Command uv)) {
            Write-Err "uv installation failed. Please restart PowerShell and try again."
            exit 1
        }
        $script:InstalledUv = $true
    }

    # 6. Download and run the real installer
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
    $head = Get-Content $tmp.FullName -TotalCount 5 -Raw
    if ($head -notmatch 'ErrorActionPreference|param\(') {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        Write-Err "Downloaded installer failed validation (not a PowerShell script)."
        exit 1
    }

    Write-Host ""
    Write-Info "Handing off to the main installer..."
    Write-Host ""

    $installFailed = $false
    try {
        & powershell -ExecutionPolicy Bypass -File $tmp.FullName
        if ($LASTEXITCODE -ne 0) { $installFailed = $true }
    } catch {
        $installFailed = $true
    } finally {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }

    if ($installFailed) {
        Write-Host ""
        Write-Err "The installer exited with an error."
        exit 1
    }

    # 7. Clean up temporary dependencies (success path only)
    Cleanup-Deps
}

Main
