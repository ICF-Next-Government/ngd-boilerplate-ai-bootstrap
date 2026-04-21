# NGD AI Boilerplate — Bootstrap

Public entry point for installing AI guidance from the private [ngd-boilerplate-ai](https://github.com/ICF-Next-Government/ngd-boilerplate-ai) repository.

## Quick Start

### macOS / Linux

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ICF-Next-Government/ngd-boilerplate-ai-bootstrap/main/bootstrap.sh)
```

### Windows (PowerShell)

```powershell
irm https://raw.githubusercontent.com/ICF-Next-Government/ngd-boilerplate-ai-bootstrap/main/bootstrap.ps1 | iex
```

## What it does

1. Installs the GitHub CLI if you don't have it (via Homebrew on macOS, winget on Windows, or apt/dnf on Linux)
2. Opens a browser window so you can log in to GitHub
3. Downloads and runs the real installer from the private repo
4. Cleans up anything it installed

You need **read access** to the [ngd-boilerplate-ai](https://github.com/ICF-Next-Government/ngd-boilerplate-ai) repository. If you can see it in the GitHub UI, you're good.

## Prerequisites

- **macOS**: None. Homebrew is installed automatically if needed.
- **Linux**: A supported package manager (apt-get or dnf).
- **Windows**: PowerShell 5.1+ and [winget](https://learn.microsoft.com/en-us/windows/package-manager/winget/) (pre-installed on Windows 10/11).
