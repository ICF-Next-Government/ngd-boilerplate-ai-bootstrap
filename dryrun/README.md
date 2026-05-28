# Dry-run distribution

Temporary public mirror of `analytics/python/claude-usage-export.py` from the [private framework repo](https://github.com/ICF-Next-Government/ngd-boilerplate-ai). Exists only so non-technical Windows testers can run the dry-run script via a single PowerShell line without cloning anything.

The script has no secrets. It reads local Claude Code transcripts, runs `dsregcmd /status` and `git --version` as subprocess smoke tests, prints a summary, and exits. **It does not push, commit, or clone anything.**

## One-liner (PowerShell)

```powershell
irm https://raw.githubusercontent.com/ICF-Next-Government/ngd-boilerplate-ai-bootstrap/main/dryrun/claude-usage-export.py | python -
```

Prerequisite: `python` on `PATH`. Install via winget if needed:

```powershell
winget install Python.Python.3
```

## Lifecycle

This directory will be deleted once the Python analytics path is wired into the Windows zip flow. The canonical home for the script is `analytics/python/` in the framework repo.
