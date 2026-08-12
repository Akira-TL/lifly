from __future__ import annotations

import argparse
from datetime import datetime
import json
from typing import Sequence

from app.modules.tasks.time_reasoning import (
    AiTaskTimingProposal,
    build_time_facts,
    parse_duration_seconds,
    sum_duration_seconds,
    task_time_ai_contract,
    validate_ai_task_timing,
)


def main(argv: Sequence[str] | None = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)
    try:
        return _execute(args)
    except ValueError as exc:
        _print_json({"valid": False, "errors": [str(exc)]})
        return 0


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="lifly-task-time")
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("contract")

    inspect_parser = subparsers.add_parser("inspect")
    _add_time_arguments(inspect_parser)

    sum_parser = subparsers.add_parser("sum-durations")
    sum_parser.add_argument("--duration", nargs="+", required=True)

    validate_parser = subparsers.add_parser("validate")
    _add_time_arguments(validate_parser)
    validate_parser.add_argument("--important", required=True, type=_parse_bool)
    validate_parser.add_argument("--urgent-lead-seconds", type=int)
    validate_parser.add_argument("--super-urgent-lead-seconds", type=int)
    validate_parser.add_argument("--minimum-urgent-lead-seconds", type=int)
    return parser


def _execute(args: argparse.Namespace) -> int:
    if args.command == "contract":
        _print_json(task_time_ai_contract())
        return 0
    if args.command == "sum-durations":
        raw_parts = list(args.duration)
        parts = [parse_duration_seconds(value) for value in raw_parts]
        _print_json(
            {
                "parts": raw_parts,
                "parts_seconds": parts,
                "total_seconds": sum_duration_seconds(parts),
            }
        )
        return 0

    facts = build_time_facts(
        now=_parse_datetime(args.now),
        due_at=_parse_nullable_datetime(args.due_at),
    )
    if args.command == "inspect":
        _print_json(facts.to_ai_payload())
        return 0

    validation = validate_ai_task_timing(
        facts,
        AiTaskTimingProposal(
            important=args.important,
            urgent_lead_seconds=args.urgent_lead_seconds,
            super_urgent_lead_seconds=args.super_urgent_lead_seconds,
        ),
        minimum_urgent_lead_seconds=args.minimum_urgent_lead_seconds,
    )
    _print_json(
        {
            "valid": validation.valid,
            "errors": list(validation.errors),
            "stage": validation.stage,
            "urgent_start_at_utc": (
                validation.urgent_start_at_utc.isoformat()
                if validation.urgent_start_at_utc
                else None
            ),
            "super_urgent_start_at_utc": (
                validation.super_urgent_start_at_utc.isoformat()
                if validation.super_urgent_start_at_utc
                else None
            ),
        }
    )
    return 0


def _add_time_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--now", required=True)
    parser.add_argument("--due-at")


def _parse_datetime(value: str) -> datetime:
    normalized = value.strip()
    if normalized.endswith("Z"):
        normalized = f"{normalized[:-1]}+00:00"
    return datetime.fromisoformat(normalized)


def _parse_nullable_datetime(value: str | None) -> datetime | None:
    if value is None or value.strip().lower() in {"", "null", "none"}:
        return None
    return _parse_datetime(value)


def _parse_bool(value: str) -> bool:
    normalized = value.strip().lower()
    if normalized in {"true", "1", "yes"}:
        return True
    if normalized in {"false", "0", "no"}:
        return False
    raise argparse.ArgumentTypeError("important 必须是 true 或 false")


def _print_json(payload: object) -> None:
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))


if __name__ == "__main__":
    raise SystemExit(main())
