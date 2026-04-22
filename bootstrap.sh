#!/usr/bin/env bash
# NGD AI Boilerplate — public bootstrap for private repo access.
#
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/ICF-Next-Government/ngd-boilerplate-ai-bootstrap/main/bootstrap.sh)
#
# What it does:
#   1. Installs dependencies if missing (Homebrew, git, gh, uv)
#   2. Authenticates with GitHub (browser-based login)
#   3. Downloads and runs the real installer from the private repo
#   4. Cleans up anything it installed
#
# The real installer does the work (practice selection, content
# merging, tool config). This script owns the environment.

set -euo pipefail

REPO="ICF-Next-Government/ngd-boilerplate-ai"

# Track what we install so we can clean up
INSTALLED_BREW=false
INSTALLED_GIT=false
INSTALLED_GH=false
INSTALLED_UV=false

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info()  { printf '\033[1;34m==>\033[0m %s\n' "$1"; }
warn()  { printf '\033[1;33mWarning:\033[0m %s\n' "$1"; }
error() { printf '\033[1;31mError:\033[0m %s\n' "$1" >&2; }
bold()  { printf '\033[1m%s\033[0m\n' "$1"; }

has() { command -v "$1" >/dev/null 2>&1; }

cleanup_deps() {
    if [ "$INSTALLED_BREW" = false ] && [ "$INSTALLED_GIT" = false ] \
        && [ "$INSTALLED_GH" = false ] && [ "$INSTALLED_UV" = false ]; then
        return 0
    fi

    echo ""
    info "Cleaning up temporary dependencies..."

    if [ "$INSTALLED_UV" = true ]; then
        rm -f "$HOME/.local/bin/uv" "$HOME/.local/bin/uvx"
        rm -f "$HOME/.cargo/bin/uv" "$HOME/.cargo/bin/uvx"
        rm -rf "$HOME/.local/share/uv"
    fi

    if [ "$INSTALLED_GH" = true ]; then
        case "$(uname -s)" in
            Darwin) brew uninstall --quiet gh 2>/dev/null || true ;;
            Linux)
                if has apt-get; then
                    sudo apt-get remove -y -qq gh 2>/dev/null || true
                    sudo rm -f /etc/apt/sources.list.d/github-cli.list
                    sudo rm -f /usr/share/keyrings/githubcli-archive-keyring.gpg
                elif has dnf; then
                    sudo dnf remove -y -q gh 2>/dev/null || true
                fi
                ;;
        esac
    fi

    if [ "$INSTALLED_GIT" = true ]; then
        case "$(uname -s)" in
            Darwin) brew uninstall --quiet git 2>/dev/null || true ;;
            Linux)
                if has apt-get; then
                    sudo apt-get remove -y -qq git 2>/dev/null || true
                elif has dnf; then
                    sudo dnf remove -y -q git 2>/dev/null || true
                fi
                ;;
        esac
    fi

    if [ "$INSTALLED_BREW" = true ]; then
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

    # On Linux, package installation requires sudo.
    if [ "$(uname -s)" = "Linux" ] && { ! has git || ! has gh; }; then
        warn "Some dependencies require administrator access. You may be prompted for your password."
    fi

    info "Checking dependencies..."

    # 1. Ensure Homebrew (macOS only; Linux uses native package managers)
    if ! has git || ! has gh; then
        case "$(uname -s)" in
            Darwin)
                if ! has brew; then
                    info "Installing Homebrew..."
                    # Unpinned HEAD URL follows Homebrew's own install guidance.
                    # Accepted risk: Homebrew is temporary and removed after install.
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
            Linux)
                if ! has apt-get && ! has dnf; then
                    error "No supported package manager found (apt-get or dnf)."
                    exit 1
                fi
                ;;
        esac
    fi

    # 2. Ensure git
    if ! has git; then
        info "Installing git..."
        case "$(uname -s)" in
            Darwin) brew install --quiet git ;;
            Linux)
                if has apt-get; then
                    sudo apt-get update -qq && sudo apt-get install -y -qq git
                elif has dnf; then
                    sudo dnf install -y -q git
                fi
                ;;
        esac
        if ! has git; then
            error "git installation failed."
            exit 1
        fi
        INSTALLED_GIT=true
    fi

    # 3. Ensure GitHub CLI
    if ! has gh; then
        info "Installing GitHub CLI..."
        case "$(uname -s)" in
            Darwin) brew install --quiet gh ;;
            Linux)
                if has apt-get; then
                    # Follows GitHub's official install docs for gh on Linux.
                # Accepted risk: keyring is temporary and removed after install.
                curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
                        | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
                    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
                        | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
                    sudo apt-get update -qq && sudo apt-get install -y -qq gh
                elif has dnf; then
                    sudo dnf install -y -q gh
                fi
                ;;
        esac
        if ! has gh; then
            error "GitHub CLI installation failed."
            exit 1
        fi
        INSTALLED_GH=true
    fi

    # 4. Authenticate
    if ! gh auth status >/dev/null 2>&1; then
        echo ""
        info "You need to log in to GitHub. A browser window will open."
        echo ""
        gh auth login --git-protocol https
    else
        info "GitHub authentication found."
    fi
    gh auth setup-git

    # 5. Ensure uv
    if ! has uv; then
        info "Installing uv..."
        curl -fsSL https://astral.sh/uv/install.sh | sh 2>/dev/null
        export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
        if ! has uv; then
            error "uv installation failed."
            exit 1
        fi
        INSTALLED_UV=true
    fi

    echo ""

    # 6. Download and run the real installer
    info "Downloading installer..."
    local tmp
    tmp=$(mktemp) && chmod 600 "$tmp"
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

    # Run as a subprocess. The installer does the work; this wrapper
    # owns all dependency management and cleanup.
    local rc=0
    bash "$tmp" || rc=$?
    rm -f "$tmp"

    if [ "$rc" -ne 0 ]; then
        echo ""
        error "The installer exited with an error (code $rc)."
        if [ "$INSTALLED_BREW" = true ] || [ "$INSTALLED_GIT" = true ] \
            || [ "$INSTALLED_GH" = true ] || [ "$INSTALLED_UV" = true ]; then
            warn "Dependencies installed temporarily were left in place for debugging."
        fi
        exit "$rc"
    fi

    # 5. Clean up what we installed (success path only)
    cleanup_deps
}

main "$@"
