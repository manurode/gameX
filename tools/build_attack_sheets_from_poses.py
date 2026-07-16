"""Build attack/work sheets from AI poses at idle-matched size.

Delegates to normalize_anim_sheets.py so characters don't grow during attack.
"""

from __future__ import annotations

import shutil
from pathlib import Path

CURSOR = Path(r"C:\Users\Manu\.cursor\projects\c-Repos-gameX\assets")
POSE_DIR = Path(r"C:\Repos\gameX\tools\ai_poses")


def collect_poses() -> None:
    POSE_DIR.mkdir(parents=True, exist_ok=True)
    names = [
        "knight_pose_windup.png",
        "knight_pose_slash.png",
        "knight_pose_follow.png",
        "archer_pose_draw.png",
        "archer_pose_aim.png",
        "archer_pose_release.png",
        "builder_pose_raise.png",
        "builder_pose_strike.png",
    ]
    for name in names:
        src = CURSOR / name
        if src.exists():
            shutil.copy2(src, POSE_DIR / name)
            print("copied", name)
        else:
            print("MISSING", name)


def main() -> None:
    collect_poses()
    from normalize_anim_sheets import main as normalize_main

    normalize_main()


if __name__ == "__main__":
    main()
