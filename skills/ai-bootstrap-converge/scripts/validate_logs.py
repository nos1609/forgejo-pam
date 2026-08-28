#!/usr/bin/env python3
"""Validate assistant JSONL logs without accepting timestamp-shaped text."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


ISO_UTC = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
PLACEHOLDER_TIME = "YYYY-MM-DDTHH:MM:SSZ"


def reject_duplicate_keys(pairs: list[tuple[str, object]]) -> dict[str, object]:
    entry: dict[str, object] = {}
    for key, value in pairs:
        if key in entry:
            raise ValueError(f"duplicate JSON key: {key}")
        entry[key] = value
    return entry


def require_fields(entry: dict[str, object], fields: set[str], source: str) -> None:
    missing = sorted(fields.difference(entry))
    if missing:
        raise ValueError(f"{source}: missing fields: {', '.join(missing)}")


def validate_session(entry: dict[str, object], assistant: str, source: str) -> None:
    fields = {"session_id", "started_at", "assistant", "language", "gender", "logging_precision"}
    require_fields(entry, fields, source)
    if entry["assistant"] != assistant:
        raise ValueError(f"{source}: assistant must equal directory name '{assistant}'")
    if not isinstance(entry["session_id"], str) or not entry["session_id"]:
        raise ValueError(f"{source}: session_id must be a non-empty string")
    for field in ("language", "gender", "logging_precision"):
        if not isinstance(entry[field], str) or not entry[field]:
            raise ValueError(f"{source}: {field} must be a non-empty string")

    started_at = entry["started_at"]
    if started_at == PLACEHOLDER_TIME:
        expected = {
            "session_id": f"sample-{assistant}-session",
            "started_at": PLACEHOLDER_TIME,
            "assistant": assistant,
            "language": "<lang>",
            "gender": "<f/m/neutral>",
            "logging_precision": "ISO8601Z",
        }
        if entry != expected:
            raise ValueError(f"{source}: placeholder session entry must match the canonical sample exactly")
    elif not isinstance(started_at, str) or not ISO_UTC.fullmatch(started_at):
        raise ValueError(f"{source}: started_at must use ISO 8601 UTC")


def validate_request(entry: dict[str, object], assistant: str, source: str) -> None:
    fields = {"timestamp", "request_id", "assistant", "summary", "tools", "status"}
    require_fields(entry, fields, source)
    if entry["assistant"] != assistant:
        raise ValueError(f"{source}: assistant must equal directory name '{assistant}'")
    if not isinstance(entry["request_id"], str) or not entry["request_id"]:
        raise ValueError(f"{source}: request_id must be a non-empty string")
    if not isinstance(entry["summary"], str) or not entry["summary"]:
        raise ValueError(f"{source}: summary must be a non-empty string")
    if not isinstance(entry["tools"], list):
        raise ValueError(f"{source}: tools must be an array")
    if not isinstance(entry["status"], str) or not entry["status"]:
        raise ValueError(f"{source}: status must be a non-empty string")

    timestamp = entry["timestamp"]
    if timestamp == PLACEHOLDER_TIME:
        expected = {
            "timestamp": PLACEHOLDER_TIME,
            "request_id": f"sample-{assistant}-req-001",
            "assistant": assistant,
            "summary": "placeholder summary",
            "tools": [],
            "status": "success",
        }
        if entry != expected:
            raise ValueError(f"{source}: placeholder request entry must match the canonical sample exactly")
    elif not isinstance(timestamp, str) or not ISO_UTC.fullmatch(timestamp):
        raise ValueError(f"{source}: timestamp must use ISO 8601 UTC")


def validate_file(path: Path) -> None:
    assistant = path.parent.name
    kind = path.name
    if kind not in {"sessions.log", "requests.log"}:
        raise ValueError(f"{path}: unsupported log filename")

    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines:
        raise ValueError(f"{path}: log is empty")
    for number, line in enumerate(lines, start=1):
        source = f"{path}:{number}"
        if not line.strip():
            raise ValueError(f"{source}: blank JSONL line")
        try:
            entry = json.loads(line, object_pairs_hook=reject_duplicate_keys)
        except json.JSONDecodeError as exc:
            raise ValueError(f"{source}: invalid JSON: {exc.msg}") from exc
        if not isinstance(entry, dict):
            raise ValueError(f"{source}: entry must be a JSON object")
        if kind == "sessions.log":
            validate_session(entry, assistant, source)
        else:
            validate_request(entry, assistant, source)


def main(argv: list[str]) -> int:
    if not argv:
        print("usage: validate_logs.py <sessions.log|requests.log>...", file=sys.stderr)
        return 2
    try:
        for value in argv:
            validate_file(Path(value))
    except (OSError, ValueError) as exc:
        print(exc, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
