# NGD AI Boilerplate — Go-path bootstrap (additive; experimental).
#
# Usage:
#   irm https://raw.githubusercontent.com/ICF-Next-Government/ngd-boilerplate-ai-bootstrap/main/bootstrap-go.ps1 | iex
#
# What it does:
#   1. Installs dependencies (git, gh) via winget if missing — same as
#      bootstrap.ps1, minus uv
#   2. Authenticates with GitHub (browser-based login)
#   3. Downloads a single Go install binary from the framework repo
#   4. Clones the framework + runs the binary
#
# Differs from bootstrap.ps1: no uv, no Python adapters. Single Go binary
# does the whole install. Intended for users whose IT policy blocks uv.exe
# or Python package installation. Currently supports claude only;
# use bootstrap.ps1 for codex/copilot.

$ErrorActionPreference = "Stop"

$Repo = "ICF-Next-Government/ngd-boilerplate-ai"
$Tool = "claude"

function Write-Info($msg) { Write-Host "🔹 $msg" }
function Write-Warn($msg) { Write-Host "⚠️  $msg" }
function Write-Err($msg)  { Write-Host "❌ $msg" -ForegroundColor Red }
function Write-Bold($msg) { Write-Host $msg -ForegroundColor White }

function Test-Command($name) { $null -ne (Get-Command $name -ErrorAction SilentlyContinue) }

function Refresh-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")
}

function Main {
    Write-Host ""
    Write-Bold "NGD AI Boilerplate — Bootstrap (Go path)"
    Write-Host ""

    # Windows release artifact uses amd64. ARM64 Windows users would need a
    # windows/arm64 build — not currently in the release matrix.
    $os    = "windows"
    $arch  = "amd64"
    $asset = "install-$os-$arch.exe"

    # 1. Ensure winget
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
        Refresh-Path
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
        Refresh-Path
        if (-not (Test-Command gh)) {
            Write-Err "GitHub CLI installation failed. Please restart PowerShell and try again."
            exit 1
        }
    }

    # 4. Authenticate
    & { $ErrorActionPreference = "Continue"; gh auth status 2>$null }
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Info "You need to log in to GitHub. A browser window will open."
        Write-Host ""
        gh auth login --git-protocol https
    } else {
        Write-Info "GitHub authentication found."
    }
    gh auth setup-git

    # 5. Clone framework + download install binary
    $WorkDir = New-Item -ItemType Directory -Path (Join-Path $env:TEMP ("ngd-go-" + [System.Guid]::NewGuid().ToString())) | Select-Object -ExpandProperty FullName
    $BinPath = Join-Path $env:TEMP ("install-" + [System.Guid]::NewGuid().ToString() + ".exe")

    try {
        Write-Info "Cloning framework..."
        gh repo clone $Repo $WorkDir -- --depth 1 --quiet
        if ($LASTEXITCODE -ne 0) { throw "framework clone failed" }

        # 6. Pick practice (positional arg or interactive)
        $Practice = $args[0]
        if (-not $Practice) {
            Write-Host ""
            Write-Host "Available practices:"
            Get-Content (Join-Path $WorkDir "practices.yaml") |
                Where-Object { $_ -match "^  [a-z][a-z-]*:$" } |
                ForEach-Object { Write-Host ("  - " + ($_.Trim().TrimEnd(":"))) }
            Write-Host ""
            $Practice = Read-Host "Practice"
        }
        if (-not $Practice) {
            Write-Err "No practice selected."
            exit 1
        }

        # 7. Download the matching install binary from latest installer-v* release
        Write-Info "Fetching latest install binary ($asset)..."
        $Tag = (gh release list --repo $Repo --limit 50 --json tagName --jq '.[].tagName' |
            Select-String -Pattern '^installer-v' |
            Select-Object -First 1).Line
        if (-not $Tag) {
            Write-Err "No installer-v* release found. Has the install binary been released yet?"
            exit 1
        }
        gh release download $Tag --repo $Repo --pattern $asset --output $BinPath --clobber
        if ($LASTEXITCODE -ne 0) { throw "binary download failed" }

        # 8. Run the installer
        Write-Host ""
        Write-Info "Installing $Tool ($Practice)..."
        Write-Host ""
        & $BinPath $Tool --practice $Practice --repo-dir $WorkDir
        if ($LASTEXITCODE -ne 0) { throw "install failed" }
    }
    finally {
        if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue }
        if (Test-Path $BinPath) { Remove-Item -Force $BinPath -ErrorAction SilentlyContinue }
    }
}

Main
