#!/usr/bin/env python3
"""Batch-normalize all generated raw sheets into game asset paths."""

from __future__ import annotations

from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
RAW = Path(__file__).resolve().parent / "raw"
PROC = Path(__file__).resolve().parent / "process_sheet.py"

CHAR_OUT = {
    "mage": ROOT / "assets/tilesets/mediterranean/Characters/mage",
    "ember": ROOT / "assets/tilesets/mediterranean/Characters/ember",
    "mire": ROOT / "assets/tilesets/mediterranean/Characters/mire",
    "hexwing": ROOT / "assets/tilesets/mediterranean/Characters/hexwing",
}

# raw stem suffix -> final filename suffix (without chr_TYPE_)
ACTIONS = [
    "idle",
    "idle_back",
    "idle_side",
    "run_upward",
    "run_downward",
    "run_side",
    "attack",
    "attack_back",
    "attack_side",
    "deploy",
    "deploy_back",
]

BUILDINGS = {
    "arcanum_raw.png": "arcanum.png",
    "arcanum_plot_raw.png": "arcanum_plot.png",
    "arcanum_construction_raw.png": "arcanum_construction.png",
    "arcanum_damaged_raw.png": "arcanum_damaged.png",
}


def run(cmd: list[str]) -> None:
    print(">", " ".join(cmd))
    subprocess.check_call(cmd)


def main() -> int:
    py = sys.executable
    missing: list[str] = []

    for unit, out_dir in CHAR_OUT.items():
        out_dir.mkdir(parents=True, exist_ok=True)
        for action in ACTIONS:
            raw = RAW / f"{unit}_{action}_raw.png"
            if not raw.exists():
                missing.append(str(raw))
                continue
            out = out_dir / f"chr_{unit}_{action}.png"
            run([py, str(PROC), str(raw), str(out)])

    build_dir = ROOT / "assets/tilesets/mediterranean/Buildings"
    for raw_name, out_name in BUILDINGS.items():
        raw = RAW / raw_name
        # also accept refs folder for complete building
        if not raw.exists() and raw_name == "arcanum_raw.png":
            raw = Path(__file__).resolve().parent / "refs" / "arcanum_raw.png"
        if not raw.exists():
            missing.append(str(raw))
            continue
        out = build_dir / out_name
        run([py, str(PROC), str(raw), str(out), "--building"])

    if missing:
        print("MISSING:")
        for m in missing:
            print(" ", m)
        return 1
    print("All assets processed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
