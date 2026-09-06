"""Small shared helpers for the iOS Simulator transport probe runners."""

from __future__ import annotations

import argparse
import importlib.util
import os
import sys
from pathlib import Path
from types import ModuleType


def add_stage_argument(parser: argparse.ArgumentParser) -> None:
    environment_stage = os.environ.get("IRPLAYER_FFMPEG_SIM_STAGE")
    parser.add_argument(
        "--stage",
        type=Path,
        default=Path(environment_stage) if environment_stage else None,
        help="candidate stage root (or set IRPLAYER_FFMPEG_SIM_STAGE)",
    )


def require_stage(
    parser: argparse.ArgumentParser, arguments: argparse.Namespace
) -> Path:
    stage = arguments.stage
    if stage is None:
        parser.error("--stage or IRPLAYER_FFMPEG_SIM_STAGE is required")
    return stage


def load_transport_fixture(module_name: str) -> ModuleType:
    source = Path(__file__).resolve().parents[1] / "test_transport_security.py"
    spec = importlib.util.spec_from_file_location(module_name, source)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"unable to load transport fixture: {source}")
    module = importlib.util.module_from_spec(spec)
    # dataclasses resolves postponed annotations through the module registry.
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def expected_raw_headers(raw_headers: str) -> dict[str, str]:
    return {
        name.lower(): value
        for line in raw_headers.strip().split("\r\n")
        for name, value in [line.split(": ", 1)]
    }
