"""
claude-usage-export.py — Windows analytics export, DRY RUN ONLY.

PURPOSE
  Stdlib-only port of the Go usage analytics binary (analytics/src/main.go)
  for Windows machines that block unsigned executables under AppLocker/WDAC.

DRY-RUN GUARANTEE
  This version does NOT push, commit, or clone anything. It reads local
  files and runs two read-only subprocesses (`dsregcmd /status` to test
  WDAC clearance, and `git --version` as a smoke test for the eventual
  push step). The analytics repo is never touched. Safe to re-run.

USAGE
  python claude-usage-export.py

WHAT IT REPORTS
  - Whether `dsregcmd` runs and identifies this as an ICF Azure AD machine
  - Whether `git` is reachable via subprocess
  - How many session transcripts and prompts WOULD be exported on a real run
  - A sample of the extracted metadata

OUTPUT
  Prints to stdout and appends to ~/.claude/logs/nightly.log so the result
  can be pasted back for review.
"""

from __future__ import annotations

import json
import logging
import platform
import statistics
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


SCRIPT_VERSION = "1-dryrun"

# ICF's Azure AD tenant ID. Pinned by GUID so a rename can't drift the check.
# Matches analytics/src/main.go:icfTenantID.
ICF_TENANT_ID = "cf90b97b-be46-4a00-9700-81ce4ff1b7f6"


def setup_logging() -> logging.Logger:
    """Tee output to stdout (interactive feedback) and ~/.claude/logs/nightly.log."""
    log_dir = Path.home() / ".claude" / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    log_path = log_dir / "nightly.log"

    logger = logging.getLogger("claude-usage-export")
    logger.setLevel(logging.INFO)
    logger.handlers.clear()  # idempotent on re-runs in the same interpreter

    file_handler = logging.FileHandler(log_path, mode="a", encoding="utf-8")
    file_handler.setFormatter(
        logging.Formatter("%(asctime)s %(message)s", datefmt="%Y/%m/%d %H:%M:%S")
    )
    logger.addHandler(file_handler)

    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setFormatter(logging.Formatter("%(message)s"))
    logger.addHandler(console_handler)

    return logger


# ---------------------------------------------------------------------------
# Work-machine checks (mirror analytics/src/main.go:isICFWindows/isICFMac)
# ---------------------------------------------------------------------------

def is_work_machine(logger: logging.Logger) -> bool:
    system = platform.system()
    if system == "Windows":
        return _is_icf_windows(logger)
    if system == "Darwin":
        return _is_icf_mac(logger)
    logger.info("platform %r is not a recognized work machine, would skip export", system)
    return False


def _is_icf_windows(logger: logging.Logger) -> bool:
    logger.info("checking Azure AD join via `dsregcmd /status` ...")
    try:
        result = subprocess.run(
            ["dsregcmd", "/status"],
            capture_output=True,
            text=True,
            timeout=30,
        )
    except FileNotFoundError:
        logger.info("  FAIL: dsregcmd not found on PATH")
        return False
    except subprocess.TimeoutExpired:
        logger.info("  FAIL: dsregcmd timed out after 30s")
        return False

    if result.returncode != 0:
        logger.info("  FAIL: dsregcmd exited %d (stderr: %s)",
                    result.returncode, result.stderr.strip())
        return False

    out = result.stdout
    joined = "AzureAdJoined : YES" in out
    tenant = f"TenantId : {ICF_TENANT_ID}" in out
    logger.info("  AzureAdJoined : %s", "YES" if joined else "NO")
    logger.info("  TenantId match: %s", "YES" if tenant else "NO")
    if not (joined and tenant):
        logger.info("  -> would skip export (not an ICF Azure AD machine)")
        return False
    logger.info("  -> would proceed (ICF Azure AD-joined)")
    return True


def _is_icf_mac(logger: logging.Logger) -> bool:
    logger.info("checking JAMF MDM enrollment via `profiles status` ...")
    try:
        result = subprocess.run(
            ["profiles", "status", "-type", "enrollment"],
            capture_output=True,
            text=True,
            timeout=30,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired) as e:
        logger.info("  FAIL: profiles command failed: %s", e)
        return False

    out = result.stdout + result.stderr
    enrolled = "MDM enrollment: Yes" in out
    icf = "icfi.com" in out
    logger.info("  MDM enrollment: %s", "Yes" if enrolled else "No")
    logger.info("  ICF MDM server: %s", "Yes" if icf else "No")
    return enrolled and icf


def check_git_subprocess(logger: logging.Logger) -> bool:
    """Smoke-test the git subprocess that the real script would use to push."""
    logger.info("checking `git --version` subprocess ...")
    try:
        result = subprocess.run(
            ["git", "--version"],
            capture_output=True,
            text=True,
            timeout=10,
        )
    except FileNotFoundError:
        logger.info("  FAIL: git not found on PATH (push step would fail)")
        return False
    except subprocess.TimeoutExpired:
        logger.info("  FAIL: git timed out")
        return False

    if result.returncode != 0:
        logger.info("  FAIL: git exited %d", result.returncode)
        return False
    logger.info("  OK: %s", result.stdout.strip())
    return True


# ---------------------------------------------------------------------------
# Session parsing (mirror analytics/src/main.go:parseSessions/parseOneSession)
# ---------------------------------------------------------------------------

def _parse_timestamp(ts: str) -> datetime | None:
    if not ts:
        return None
    ts = ts.replace("Z", "+00:00")
    try:
        return datetime.fromisoformat(ts)
    except ValueError:
        try:
            return datetime.fromisoformat(ts.split(".")[0])
        except ValueError:
            return None


def parse_sessions(claude_dir: Path, logger: logging.Logger) -> list[dict[str, Any]]:
    """
    No state filter — the real run would dedupe against the analytics repo's
    {user_id}/_state.json. Dry-run reports the full count instead.
    """
    projects_dir = claude_dir / "projects"
    if not projects_dir.is_dir():
        logger.info("no projects/ at %s — nothing to parse", projects_dir)
        return []

    sessions: list[dict[str, Any]] = []
    for transcript in sorted(projects_dir.glob("*/*.jsonl")):
        if "subagents" in transcript.parts:
            continue  # matches Go: skip subagent transcripts
        session = _parse_one_session(transcript, transcript.stem, logger)
        if session is None:
            continue
        if session["user_messages"] == 0:
            continue  # matches Go: skip empty sessions
        sessions.append(session)
    return sessions


def _parse_one_session(
    path: Path, session_id: str, logger: logging.Logger
) -> dict[str, Any] | None:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as e:
        logger.info("  skipping %s: %s", path.name, e)
        return None

    s: dict[str, Any] = {
        "session_id": session_id,
        "cwd": "",
        "version": "",
        "entrypoint": "",
        "git_branch": "",
        "user_messages": 0,
        "assistant_messages": 0,
        "tool_uses": {},
        "tool_errors": 0,
        "total_input_tokens": 0,
        "total_output_tokens": 0,
        "total_cache_read_tokens": 0,
        "total_cache_create_tokens": 0,
        "models": {},
        "subagent_count": 0,
        "skills_used": [],
    }

    timestamps: list[datetime] = []
    user_timestamps: list[datetime] = []

    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue

        msg_type = obj.get("type", "")
        ts_str = obj.get("timestamp", "")
        if ts_str:
            t = _parse_timestamp(ts_str)
            if t is not None:
                timestamps.append(t)

        # First-write-wins on metadata fields (matches Go behavior).
        for field, key in (
            ("cwd", "cwd"),
            ("version", "version"),
            ("entrypoint", "entrypoint"),
            ("git_branch", "gitBranch"),
        ):
            if not s[field]:
                v = obj.get(key)
                if isinstance(v, str) and v:
                    s[field] = v

        if msg_type == "user":
            s["user_messages"] += 1
            if ts_str:
                t = _parse_timestamp(ts_str)
                if t is not None:
                    user_timestamps.append(t)
            msg = obj.get("message")
            if isinstance(msg, dict):
                content = msg.get("content")
                if isinstance(content, list):
                    for block in content:
                        if isinstance(block, dict) and block.get("is_error") is True:
                            s["tool_errors"] += 1

        elif msg_type == "assistant":
            s["assistant_messages"] += 1
            msg = obj.get("message")
            if not isinstance(msg, dict):
                continue

            model = msg.get("model")
            if isinstance(model, str) and model:
                s["models"][model] = s["models"].get(model, 0) + 1

            usage = msg.get("usage")
            if isinstance(usage, dict):
                s["total_input_tokens"]        += int(usage.get("input_tokens") or 0)
                s["total_output_tokens"]       += int(usage.get("output_tokens") or 0)
                s["total_cache_read_tokens"]   += int(usage.get("cache_read_input_tokens") or 0)
                s["total_cache_create_tokens"] += int(usage.get("cache_creation_input_tokens") or 0)

            content = msg.get("content")
            if isinstance(content, list):
                for block in content:
                    if not isinstance(block, dict):
                        continue
                    if block.get("type") != "tool_use":
                        continue
                    tool_name = block.get("name") or "unknown"
                    s["tool_uses"][tool_name] = s["tool_uses"].get(tool_name, 0) + 1
                    if tool_name == "Agent":
                        s["subagent_count"] += 1
                    if tool_name == "Skill":
                        tool_input = block.get("input")
                        if isinstance(tool_input, dict):
                            skill = tool_input.get("skill")
                            if isinstance(skill, str):
                                s["skills_used"].append(skill)

    if timestamps:
        timestamps.sort()
        start, end = timestamps[0], timestamps[-1]
        s["start_time"] = start.isoformat()
        s["end_time"] = end.isoformat()
        s["duration_minutes"] = round((end - start).total_seconds() / 60.0, 1)
        local_start = start.astimezone()
        s["start_date"] = local_start.strftime("%Y-%m-%d")
        s["start_hour"] = local_start.hour

    if len(user_timestamps) > 1:
        user_timestamps.sort()
        gaps = [
            (user_timestamps[i] - user_timestamps[i - 1]).total_seconds()
            for i in range(1, len(user_timestamps))
        ]
        s["avg_user_gap_seconds"] = round(sum(gaps) / len(gaps), 1)
        s["median_user_gap_seconds"] = round(statistics.median(gaps), 1)

    return s


# ---------------------------------------------------------------------------
# Prompt history (mirror analytics/src/main.go:parseHistory)
# ---------------------------------------------------------------------------

def parse_history(claude_dir: Path, logger: logging.Logger) -> list[dict[str, Any]]:
    history_path = claude_dir / "history.jsonl"
    if not history_path.is_file():
        return []

    try:
        text = history_path.read_text(encoding="utf-8")
    except OSError as e:
        logger.info("cannot read history: %s", e)
        return []

    prompts: list[dict[str, Any]] = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue

        ts_millis = obj.get("timestamp")
        if not isinstance(ts_millis, (int, float)):
            continue
        ts = datetime.fromtimestamp(ts_millis / 1000, tz=timezone.utc).astimezone()
        display = obj.get("display") or ""
        pasted = obj.get("pastedContents") or {}

        prompts.append({
            "session_id": obj.get("sessionId") or "",
            "project": obj.get("project") or "",
            "timestamp": ts.isoformat(),
            "hour": ts.hour,
            "date": ts.strftime("%Y-%m-%d"),
            "weekday": ts.strftime("%A"),
            "prompt_length": len(display),
            "has_paste": isinstance(pasted, dict) and len(pasted) > 0,
        })
    return prompts


# ---------------------------------------------------------------------------
# Summary + main
# ---------------------------------------------------------------------------

def summarize(
    sessions: list[dict[str, Any]],
    prompts: list[dict[str, Any]],
    logger: logging.Logger,
) -> None:
    logger.info("")
    logger.info("--- EXPORT SUMMARY (dry run) ---")
    logger.info("sessions: %d", len(sessions))
    logger.info("prompts:  %d", len(prompts))
    if not sessions:
        return
    total_input = sum(s["total_input_tokens"] for s in sessions)
    total_output = sum(s["total_output_tokens"] for s in sessions)
    total_minutes = sum(s.get("duration_minutes", 0.0) for s in sessions)
    logger.info("total input tokens:    %d", total_input)
    logger.info("total output tokens:   %d", total_output)
    logger.info("total session minutes: %.1f", total_minutes)

    sample = sessions[0]
    sample_fields = (
        "session_id", "start_date", "start_hour", "duration_minutes",
        "user_messages", "assistant_messages", "tool_uses", "models",
    )
    logger.info("")
    logger.info("first session sample:")
    logger.info(json.dumps(
        {k: sample.get(k) for k in sample_fields},
        indent=2,
        default=str,
    ))


def main() -> int:
    logger = setup_logging()
    logger.info("")
    logger.info("claude-usage-export.py v%s (dry run; no network activity)",
                SCRIPT_VERSION)

    home = Path.home()
    claude_dir = home / ".claude"
    logger.info("home dir: %s", home)
    logger.info("user id:  %s", home.name)
    logger.info("claude:   %s", claude_dir)
    logger.info("")

    work_ok = is_work_machine(logger)
    git_ok = check_git_subprocess(logger)

    if claude_dir.is_dir():
        sessions = parse_sessions(claude_dir, logger)
        prompts = parse_history(claude_dir, logger)
        summarize(sessions, prompts, logger)
    else:
        logger.info("")
        logger.info("no ~/.claude/ directory — nothing local to parse")

    logger.info("")
    logger.info("--- DRY RUN COMPLETE ---")
    logger.info("work-machine check: %s", "PASS" if work_ok else "FAIL")
    logger.info("git subprocess:     %s", "PASS" if git_ok else "FAIL")
    logger.info("nothing was sent. log: %s",
                home / ".claude" / "logs" / "nightly.log")
    return 0


if __name__ == "__main__":
    sys.exit(main())
