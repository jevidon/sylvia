#!/usr/bin/env python3
"""Render the design boards in canvas/ to PNGs in images/ with headless Chrome.

Usage:
  python3 Docs/Design/render.py                 # every board listed in canvas/canvas.json
  python3 Docs/Design/render.py Library.dc.html # one or more named boards

Environment:
  CHROME  path to a Chrome or Chromium binary (default: Google Chrome on macOS)
  SCALE   device scale factor (default: 2, so a 390x844 board becomes 780x1688)

Each board is a self-contained HTML file; its size comes from canvas.json. Web fonts
load from Google Fonts, so a network connection is needed for Literata to appear.
"""
import json
import os
import pathlib
import subprocess
import sys

here = pathlib.Path(__file__).resolve().parent
canvas = json.loads((here / "canvas" / "canvas.json").read_text())
chrome = os.environ.get("CHROME", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
scale = os.environ.get("SCALE", "2")
out = here / "images"
out.mkdir(exist_ok=True)

names = sys.argv[1:] or canvas["order"]
for name in names:
    board = canvas["boards"][name]
    png = out / (name.replace(".dc.html", "") + ".png")
    src = (here / "canvas" / name).as_uri()
    cmd = [
        chrome,
        "--headless=new",
        "--disable-gpu",
        "--hide-scrollbars",
        f"--force-device-scale-factor={scale}",
        "--virtual-time-budget=5000",
        f"--window-size={board['w']},{board['h']}",
        f"--screenshot={png}",
        src,
    ]
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print(f"{png.name}  {board['w']}x{board['h']} at {scale}x")
