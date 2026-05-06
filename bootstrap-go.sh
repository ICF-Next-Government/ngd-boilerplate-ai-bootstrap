#!/usr/bin/env bash
# NGD AI Boilerplate — Go-path bootstrap (additive; experimental).
#
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/ICF-Next-Government/ngd-boilerplate-ai-bootstrap/main/bootstrap-go.sh) [practice]
#
# What it does:
#   1. Installs dependencies if missing (Homebrew, git, gh) — same as
#      bootstrap.sh, minus uv
#   2. Authenticates with GitHub (browser-based login)
#   3. Downloads a single Go install binary from the framework repo
#   4. Clones the framework + runs the binary
#
# Differs from bootstrap.sh: no uv, no Python adapters. Single Go binary
# does the whole install. Intended for users whose IT policy blocks uv.exe
# or Python package installation. Currently supports claude only;
# use bootstrap.sh for codex/copilot.

set -euo pipefail

REPO="ICF-Next-Government/ngd-boilerplate-ai"
TOOL="claude"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info()  { printf '🔹 %s\n' "$1"; }
warn()  { printf '⚠️  %s\n' "$1"; }
error() { printf '❌ %s\n' "$1" >&2; }
bold()  { printf '\033[1m%s\033[0m\n' "$1"; }

has() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    echo ""
    bold "NGD AI Boilerplate — Bootstrap (Go path)"
    echo ""

    case "$(uname -s)" in
        Darwin) os=darwin ;;
        *)
            error "Unsupported OS for bootstrap-go.sh; use bootstrap-go.ps1 on Windows or bootstrap.sh on Linux."
            exit 1
            ;;
    esac

    case "$(uname -m)" in
        arm64|aarch64) arch=arm64 ;;
        x86_64|amd64)  arch=amd64 ;;
        *)
            error "Unsupported architecture: $(uname -m)"
            exit 1
            ;;
    esac

    info "Checking dependencies..."

    # 1. Ensure Homebrew (macOS only)
    if ! has git || ! has gh; then
        if ! has brew; then
            info "Installing Homebrew..."
            # Unpinned HEAD URL follows Homebrew's own install guidance.
            /bin/bash -c \
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
        fi
    fi

    # 2. Ensure git
    if ! has git; then
        info "Installing git..."
        brew install --quiet git
        if ! has git; then
            error "git installation failed."
            exit 1
        fi
    fi

    # 3. Ensure GitHub CLI
    if ! has gh; then
        info "Installing GitHub CLI..."
        brew install --quiet gh
        if ! has gh; then
            error "GitHub CLI installation failed."
            exit 1
        fi
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

    # 5. Clone framework + download install binary
    local work bin asset tag
    work=$(mktemp -d)
    bin=$(mktemp)
    trap 'rm -rf "$work" "$bin"' EXIT

    info "Cloning framework..."
    gh repo clone "$REPO" "$work" -- --depth 1 --quiet

    # 6. Pick practice (positional arg or interactive)
    local practice="${1:-}"
    if [ -z "$practice" ]; then
        echo ""
        echo "Available practices:"
        awk '/^practices:/{flag=1; next} flag && /^  [a-z][a-z-]*:$/{gsub(/:/,""); print "  - " $1}' "$work/practices.yaml"
        echo ""
        read -r -p "Practice: " practice
    fi
    if [ -z "$practice" ]; then
        error "No practice selected."
        exit 1
    fi

    # 7. Download the matching install binary from latest installer-v* release
    asset="install-${os}-${arch}"
    info "Fetching latest install binary ($asset)..."
    tag=$(gh release list --repo "$REPO" --limit 50 --json tagName --jq '.[].tagName' \
        | grep -m1 '^installer-v' || true)
    if [ -z "$tag" ]; then
        error "No installer-v* release found. Has the install binary been released yet?"
        exit 1
    fi
    gh release download "$tag" --repo "$REPO" --pattern "$asset" --output "$bin" --clobber
    chmod +x "$bin"

    # 8. Run the installer
    echo ""
    info "Installing $TOOL ($practice)..."
    echo ""
    "$bin" "$TOOL" --practice "$practice" --repo-dir "$work"
}

main "$@"
