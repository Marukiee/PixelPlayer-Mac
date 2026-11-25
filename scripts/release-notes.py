#!/usr/bin/env python3
"""Prints the release notes for one version from changelog.json, as Markdown.

Usage: scripts/release-notes.py 0.1.0
The same text the app shows on its update card. Without an entry for the version it prints a plain line, so the release
never fails over it.
"""
import json
import sys
from pathlib import Path

version = sys.argv[1].lstrip("v") if len(sys.argv) > 1 else ""
entries = json.loads((Path(__file__).resolve().parent.parent / "changelog.json").read_text())
entry = next((e for e in entries if e["version"] == version), None)
if entry is None:
    print(f"## PixelPlayer {version}")
else:
    text = entry["en"]
    print(f"## {text['title']}\n")
    for key, label in (("new", "New"), ("better", "Better"), ("fixed", "Fixed")):
        items = text.get(key)
        if items:
            print(f"**{label}**\n")
            print("\n".join(f"- {item}" for item in items))
            print()

print(f"""---

| File | For |
| --- | --- |
| `PixelPlayer-v{version}-macOS.zip` | Mac with Apple silicon, macOS 26 or newer |

Open the zip and move PixelPlayer to Applications. The first time, right click the app and choose Open: it is signed with a certificate of its own, not by Apple. After that it updates itself.""")
