from PIL import Image
from pathlib import Path

root = Path(r"C:\Repos\gameX\assets\tilesets\mediterranean\Characters")
out = Path(r"C:\Repos\gameX\tools\anim_refs")
out.mkdir(parents=True, exist_ok=True)

units = {
    "villager": "villager/chr_villager_idle.png",
    "villager_back": "villager/chr_villager_idle_back.png",
    "knight": "knight/chr_knight_idle.png",
    "knight_back": "knight/chr_knight_idle_back.png",
    "archer": "archer/chr_archer_idle.png",
    "archer_back": "archer/chr_archer_idle_back.png",
    "builder": "builder/chr_builder_idle.png",
    "builder_back": "builder/chr_builder_idle_back.png",
    "enemy": "enemy/chr_enemy_idle.png",
    "enemy_back": "enemy/chr_enemy_idle_back.png",
}

for name, rel in units.items():
    src = root / rel
    if not src.exists():
        print("missing", src)
        continue
    im = Image.open(src).convert("RGBA")
    frame = im.crop((0, 0, 80, 80))
    frame.save(out / f"{name}_base.png")
    print(name, frame.size, "saved")

print("done", out)
