# NGD AI Boilerplate — Bootstrap

Public entry point for installing AI guidance from the private [ngd-boilerplate-ai](https://github.com/ICF-Next-Government/ngd-boilerplate-ai) repository.

## Quick Start

### macOS / Linux

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ICF-Next-Government/ngd-boilerplate-ai-bootstrap/main/bootstrap.sh)
```

### Windows

Windows installs go through a signed-interpreter zip rather than this bootstrap. Download `claude-windows-<tag>.zip` from the [latest release](https://github.com/ICF-Next-Government/ngd-boilerplate-ai/releases/latest), then follow the bundled `README-windows.txt`:

1. Right-click the zip, choose **Extract All** (don't run from inside the zip).
2. Right-click `install.cmd` in the extracted folder, choose **Run as Administrator** (don't double-click).

Skipping either step is the most common cause of failed installs.

## What it does (macOS / Linux)

1. Installs dependencies (git, GitHub CLI, uv) if you don't have them.
2. Opens a browser window so you can log in to GitHub.
3. Downloads and runs the real installer from the private repo.
4. Cleans up uv (temporary); git and GitHub CLI persist for ongoing use.

You need **read access** to the [ngd-boilerplate-ai](https://github.com/ICF-Next-Government/ngd-boilerplate-ai) repository. If you can see it in the GitHub UI, you're good.

## Prerequisites

- **macOS**: None. Homebrew is installed automatically if needed.
- **Linux**: git available on PATH; the bootstrap installs the rest.
- **Windows**: not applicable to this bootstrap. See the zip path above.

## What persists after install

Git and GitHub CLI remain on your machine. They're used by nightly usage analytics to push anonymized metrics. See the [analytics README](https://github.com/ICF-Next-Government/ngd-boilerplate-ai/tree/main/analytics) for details on what's collected.
