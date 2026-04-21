#!/usr/bin/env bash
# NGD AI Boilerplate — public bootstrap for private repo access.
#
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/ICF-Next-Government/ngd-boilerplate-ai-bootstrap/main/bootstrap.sh)
#
# What it does:
#   1. Installs Homebrew and GitHub CLI (if missing)
#   2. Authenticates with GitHub (browser-based login)
#   3. Downloads and runs the real installer from the private repo
#   4. Cleans up anything it installed
#
# The real installer handles everything else (git, uv, Python,
# practice selection, tool config). This script only bridges
# the authentication gap.

set -euo pipefail

REPO="ICF-Next-Government/ngd-boilerplate-ai"

# Track what we install so we can clean up
INSTALLED_BREW=false
INSTALLED_GH=false

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info()  { printf '\033[1;34m==>\033[0m %s\n' "$1"; }
warn()  { printf '\033[1;33mWarning:\033[0m %s\n' "$1"; }
error() { printf '\033[1;31mError:\033[0m %s\n' "$1" >&2; }
bold()  { printf '\033[1m%s\033[0m\n' "$1"; }

has() { command -v "$1" >/dev/null 2>&1; }

cleanup_deps() {
    if [ "$INSTALLED_GH" = true ] && has brew; then
        info "Removing GitHub CLI (installed temporarily)..."
        brew uninstall --quiet gh 2>/dev/null || true
    fi

    if [ "$INSTALLED_BREW" = true ]; then
        info "Removing Homebrew (installed temporarily)..."
        NONINTERACTIVE=1 /bin/bash -c \
            "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)" 2>/dev/null || true
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    echo ""
    bold "NGD AI Boilerplate — Bootstrap"
    echo ""

    # Ensure we're on a supported OS
    case "$(uname -s)" in
        Darwin) ;;
        Linux)  ;;
        *)
            error "Unsupported operating system. Use bootstrap.ps1 for Windows."
            exit 1
            ;;
    esac

    # 1. Ensure Homebrew (macOS only; Linux uses native package managers)
    case "$(uname -s)" in
        Darwin)
            if ! has brew; then
                info "Installing Homebrew..."
                NONINTERACTIVE=1 /bin/bash -c \
                    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
                if [ -f /opt/homebrew/bin/brew ]; then
                    eval "$(/opt/homebrew/bin/brew shellenv)"
                elif [ -f /usr/local/bin/brew ]; then
                    eval "$(/usr/local/bin/brew shellenv)"
                fi
                if ! has brew; then
                    error "Homebrew installation failed."
                    exit 1
                fi
                INSTALLED_BREW=true
            fi
            ;;
    esac

    # 2. Ensure GitHub CLI
    if ! has gh; then
        if [ "$(uname -s)" = "Linux" ]; then
            warn "Installing the GitHub CLI requires administrator access. You may be prompted for your password."
        fi
        info "Installing GitHub CLI..."
        case "$(uname -s)" in
            Darwin)
                brew install --quiet gh
                ;;
            Linux)
                if has apt-get; then
                    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
                        | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
                    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
                        | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
                    sudo apt-get update -qq && sudo apt-get install -y -qq gh
                elif has dnf; then
                    sudo dnf install -y -q gh
                else
                    error "No supported package manager found (brew, apt-get, or dnf)."
                    exit 1
                fi
                ;;
        esac
        if ! has gh; then
            error "GitHub CLI installation failed."
            exit 1
        fi
        INSTALLED_GH=true
    fi

    # 3. Authenticate
    if ! gh auth status >/dev/null 2>&1; then
        echo ""
        info "You need to log in to GitHub. A browser window will open."
        echo ""
        gh auth login --git-protocol https
    else
        info "GitHub authentication found."
    fi

    # 4. Download and run the real installer
    info "Downloading installer..."
    local tmp
    tmp=$(mktemp)
    if ! gh api "repos/$REPO/contents/bin/install.sh" --jq '.content' | base64 -d > "$tmp"; then
        rm -f "$tmp"
        error "Failed to download the installer. Do you have access to the $REPO repository?"
        exit 1
    fi

    # Validate the downloaded script. The GitHub Contents API returns null
    # content for files over 1MB, which base64 decodes to garbage.
    if ! head -1 "$tmp" | grep -q '^#!/'; then
        rm -f "$tmp"
        error "Downloaded installer failed validation (missing shebang)."
        exit 1
    fi
    if [ "$(wc -c < "$tmp")" -lt 100 ]; then
        rm -f "$tmp"
        error "Downloaded installer is too small; likely truncated or empty."
        exit 1
    fi

    echo ""
    info "Handing off to the main installer..."
    echo ""

    # Run as a subprocess (not source/exec). Each script tracks what it
    # installed and cleans up only those items. Subprocess isolation keeps
    # the two cleanup scopes independent.
    bash "$tmp"
    rm -f "$tmp"

    # 5. Clean up what we installed (success path only)
    cleanup_deps
}

main "$@"
