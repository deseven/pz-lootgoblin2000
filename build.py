#!/usr/bin/env python3
import os
import re
import sys
import zipfile
import shutil
import subprocess
import tempfile

script_dir = os.path.dirname(os.path.abspath(__file__))

# ── Config ────────────────────────────────────────────────────────────────────

STEAM_APP_ID    = 108600
WORKSHOP_ID     = 3694894350
MOD_TITLE       = "Loot Goblin 2000 [B42]"
MOD_TAGS        = "Build 42,QoL,Items,Interface"
UPLOADER_BIN    = os.path.join(script_dir, "_SteamUploader", "build", "bin", "SteamUploader")
PREVIEW_IMAGE   = os.path.join(script_dir, "LootGoblin2000", "42", "poster.png")
CONTENT_DIR     = os.path.join(script_dir, "LootGoblin2000")
README_PATH     = os.path.join(script_dir, "README.md")

# ── Helpers ───────────────────────────────────────────────────────────────────

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

# ── Markdown → BBCode converter ───────────────────────────────────────────────

def md_to_bbcode(text: str) -> str:
    """Convert a subset of Markdown to Steam Workshop BBCode."""
    lines = text.splitlines()
    out = []
    in_list = False

    for line in lines:
        # ── Headings ──────────────────────────────────────────────────────────
        m = re.match(r'^(#{1,6})\s+(.*)', line)
        if m:
            if in_list:
                out.append("[/list]")
                in_list = False
            level = len(m.group(1))
            content = m.group(2).strip()
            content = _inline(content)
            if level == 1:
                out.append(f"[h1]{content}[/h1]")
            elif level == 2:
                out.append(f"[h2]{content}[/h2]")
            elif level == 3:
                out.append(f"[h3]{content}[/h3]")
            else:
                out.append(f"[b]{content}[/b]")
            continue

        # ── Blockquotes ───────────────────────────────────────────────────────
        m = re.match(r'^>\s*(.*)', line)
        if m:
            if in_list:
                out.append("[/list]")
                in_list = False
            content = _inline(m.group(1).strip())
            out.append(f"[quote]{content}[/quote]")
            continue

        # ── Unordered list items ──────────────────────────────────────────────
        m = re.match(r'^[-*+]\s+(.*)', line)
        if m:
            if not in_list:
                out.append("[list]")
                in_list = True
            content = _inline(m.group(1).strip())
            out.append(f"[*]{content}")
            continue

        # ── Horizontal rule ───────────────────────────────────────────────────
        if re.match(r'^[-*_]{3,}\s*$', line):
            if in_list:
                out.append("[/list]")
                in_list = False
            out.append("[hr][/hr]")
            continue

        # ── Blank line ────────────────────────────────────────────────────────
        if line.strip() == "":
            if in_list:
                out.append("[/list]")
                in_list = False
            out.append("")
            continue

        # ── Regular paragraph line ────────────────────────────────────────────
        if in_list:
            out.append("[/list]")
            in_list = False
        out.append(_inline(line))

    if in_list:
        out.append("[/list]")

    return "\n".join(out)


def _inline(text: str) -> str:
    """Apply inline Markdown → BBCode transformations."""
    # Bold+italic: ***text*** or ___text___ (must come before bold/italic)
    text = re.sub(r'\*{3}(.+?)\*{3}', r'[b][i]\1[/i][/b]', text)
    text = re.sub(r'_{3}(.+?)_{3}',   r'[b][i]\1[/i][/b]', text)

    # Bold: **text** or __text__
    text = re.sub(r'\*{2}(.+?)\*{2}', r'[b]\1[/b]', text)
    text = re.sub(r'_{2}(.+?)_{2}',   r'[b]\1[/b]', text)

    # Italic: *text* or _text_
    text = re.sub(r'\*(.+?)\*', r'[i]\1[/i]', text)
    text = re.sub(r'_(.+?)_',   r'[i]\1[/i]', text)

    # Strikethrough: ~~text~~
    text = re.sub(r'~~(.+?)~~', r'[strike]\1[/strike]', text)

    # Inline code: `code` — Steam doesn't support [code] inline, use bold instead.
    # Must come after bold/italic so **`x`** doesn't double-wrap.
    text = re.sub(r'`([^`]+)`', r'[b]\1[/b]', text)

    # Links with label: [label](url) — also handles outer literal brackets [[label](url)]
    text = re.sub(r'\[\[([^\]]+)\]\(([^)]+)\)\]', r'[url=\2]\1[/url]', text)
    text = re.sub(r'\[([^\]]+)\]\(([^)]+)\)', r'[url=\2]\1[/url]', text)

    # Bare URLs (not already inside a tag)
    text = re.sub(r'(?<!\[url=)(?<!\[/url\])\bhttps?://\S+', lambda m: f'[url]{m.group(0)}[/url]', text)

    return text

# ── Build (zip) ───────────────────────────────────────────────────────────────

def build_zip():
    zip_path = os.path.join(script_dir, f"PZ-LootGoblin2000-{version}.zip")
    src_dir  = os.path.join(script_dir, "LootGoblin2000")

    print("Packing LootGoblin2000 into zip...")
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for root, dirs, files in os.walk(src_dir):
            for file in files:
                abs_path = os.path.join(root, file)
                arc_name = os.path.join("LootGoblin2000", os.path.relpath(abs_path, src_dir))
                zf.write(abs_path, arc_name)

    print(f"Created: {zip_path}")

# ── Workshop upload ───────────────────────────────────────────────────────────

def upload_workshop():
    if not os.path.isfile(UPLOADER_BIN):
        print(f"Error: SteamUploader binary not found at {UPLOADER_BIN}")
        print("Build it first: cd _SteamUploader && cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release && cmake --build build")
        raise SystemExit(1)

    # Convert README.md to BBCode and write to a temp file
    print("Converting README.md to BBCode...")
    with open(README_PATH, "r", encoding="utf-8") as f:
        md_content = f.read()
    bbcode = md_to_bbcode(md_content)

    with tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False, encoding="utf-8") as tmp:
        tmp.write(bbcode)
        desc_path = tmp.name

    # Build staging dir: staging/mods/LootGoblin2000/ → uploader sees mods/LootGoblin2000/42/...
    staging_dir = os.path.join(script_dir, "staging")
    staging_mod_dir = os.path.join(staging_dir, "mods", "LootGoblin2000")
    if os.path.exists(staging_dir):
        shutil.rmtree(staging_dir)
    shutil.copytree(CONTENT_DIR, staging_mod_dir)

    try:
        print(f"Uploading to Steam Workshop (item {WORKSHOP_ID})...")
        cmd = [
            UPLOADER_BIN,
            "-a", str(STEAM_APP_ID),
            "-w", str(WORKSHOP_ID),
            "-t", MOD_TITLE,
            "-d", desc_path,
            "-p", PREVIEW_IMAGE,
            "-c", staging_dir,
            "-T", MOD_TAGS,
            "-v", "0",
        ]
        print("Running:", " ".join(cmd))
        result = subprocess.run(cmd, cwd=os.path.dirname(UPLOADER_BIN))
        if result.returncode != 0:
            print(f"Error: SteamUploader exited with code {result.returncode}")
            raise SystemExit(result.returncode)
        print("Workshop upload complete!")
    finally:
        os.unlink(desc_path)
        shutil.rmtree(staging_dir, ignore_errors=True)

def convert_description():
    with open(README_PATH, "r", encoding="utf-8") as f:
        md_content = f.read()
    print(md_to_bbcode(md_content))

# ── Entry point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    args = sys.argv[1:]

    if "description-convert" in args:
        convert_description()
    elif "workshop" in args:
        build_zip()
        upload_workshop()
    else:
        build_zip()
