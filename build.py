#!/usr/bin/env python3
import os
import re
import zipfile

script_dir = os.path.dirname(os.path.abspath(__file__))

mod_info_path = os.path.join(script_dir, "LootGoblin2000", "42", "mod.info")
version = None
with open(mod_info_path) as f:
    for line in f:
        m = re.match(r"modversion\s*=\s*(.+)", line.strip())
        if m:
            version = m.group(1).strip()
            break

if not version:
    print("Error: could not find modversion in mod.info")
    raise SystemExit(1)

zip_path = os.path.join(script_dir, f"PZ-LootGoblin2000-{version}.zip")
src_dir = os.path.join(script_dir, "LootGoblin2000")

print("Packing LootGoblin2000 into zip...")
with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
    for root, dirs, files in os.walk(src_dir):
        for file in files:
            abs_path = os.path.join(root, file)
            arc_name = os.path.join("LootGoblin2000", os.path.relpath(abs_path, src_dir))
            zf.write(abs_path, arc_name)

print(f"Created: {zip_path}")
