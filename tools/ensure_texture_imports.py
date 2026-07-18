"""Create stub .import files for new character PNGs (Godot regenerates hashes on open)."""

from __future__ import annotations

import hashlib
from pathlib import Path

CHARS = Path(r"C:\Repos\gameX\assets\tilesets\mediterranean\Characters")
ROOT = Path(r"C:\Repos\gameX")

TEMPLATE = """[remap]

importer="texture"
type="CompressedTexture2D"
uid="uid://{uid}"
path="res://.godot/imported/{name}-{digest}.ctex"
metadata={{
"vram_texture": false
}}

[deps]

source_file="{source}"
dest_files=["res://.godot/imported/{name}-{digest}.ctex"]

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=false
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=1
"""


def main() -> None:
    created = 0
    for png in CHARS.rglob("chr_*.png"):
        imp = Path(str(png) + ".import")
        if imp.exists():
            continue
        rel = "res://" + png.relative_to(ROOT).as_posix()
        digest = hashlib.md5(rel.encode()).hexdigest()
        uid = "d" + digest[:13]
        imp.write_text(
            TEMPLATE.format(uid=uid, name=png.name, digest=digest, source=rel),
            encoding="utf-8",
        )
        created += 1
        print("created", imp.relative_to(ROOT))
    print(f"done ({created} new imports)")


if __name__ == "__main__":
    main()
