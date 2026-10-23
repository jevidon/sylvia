#!/usr/bin/env python3
"""Checks, in Apple's own pages as fetched by apple-pages.sh beside this file, each text the records of 24 October 2026
quote about device A (the iPhone 13 mini, the iPhone 11 Pro, the iPhones iOS 26 supports) and about Xcode 27.1 (that
27A9275 is the release build). Each page's text is read as data (HTML tags removed, entities decoded; for the release
notes, the JSON document's "text" values joined), runs of whitespace made one space and Unicode hyphens (U+2010,
U+2011) made "-"; each quote must occur in it as written, and each "absent" text must not, in any letter case.

    python3 -I apple-pages.py <folder of fetched pages>

Read-only; standard library only. Exit status 1 if a quote is missing, an absent text is present or a page is missing.
"""
import html
import json
import re
import sys
from pathlib import Path

FOLDER = Path(sys.argv[1])

# file -> (URL, quotes that must be present, texts that must be absent)
PAGES = {
    "iphone-13-mini-specs.html": ("https://support.apple.com/en-nz/111873", [
        "iPhone 13 mini - Technical Specifications",
        "5.4-inch (diagonal) all-screen OLED display",
        "2340-by-1080-pixel resolution at 476 ppi",
        "A15 Bionic chip",
        "6-core CPU with 2 performance and 4 efficiency cores",
        "4-core GPU",
        "16-core Neural Engine",
        "Lightning connector",
        "Enabled by TrueDepth camera for facial recognition",
        "Ring/Silent switch",
    ], ["Action button"]),
    "iphone-11-pro-specs.html": ("https://support.apple.com/en-nz/111879", [
        "iPhone 11 Pro - Technical Specifications",
        "5.8-inch (diagonal) all-screen OLED Multi-Touch display",
        "2436-by-1125-pixel resolution at 458 ppi",
        "A13 Bionic chip",
        "Lightning connector",
    ], []),
    "ios-26-models.html": ("https://support.apple.com/guide/iphone/iphone-models-compatible-with-ios-26-iphe3fa5df43/26/ios/26", [
        "iPhone models compatible with iOS 26",
        "which is compatible with the following models: iPhone 11 iPhone 11 Pro iPhone 11 Pro Max iPhone 12 mini "
        "iPhone 12 iPhone 12 Pro iPhone 12 Pro Max iPhone 13 mini iPhone 13",
        "iPhone SE (2nd generation) iPhone SE (3rd generation)",
    ], []),
    "xcode-27.1-release.html": ("https://developer.apple.com/news/releases/?id=10152026a", [
        "Xcode 27.1 (27A9275)",
        "October 15, 2026",
    ], ["Xcode 27.1 beta (27A9275)", "Xcode 27.1 RC (27A9275)", "Xcode 27.1 Release Candidate (27A9275)"]),
    "xcode-27.1-beta.html": ("https://developer.apple.com/news/releases/?id=09182026a", [
        "Xcode 27.1 beta (27A9269)",
        "September 18, 2026",
    ], []),
    "xcode-27.1-release-notes.json": ("https://developer.apple.com/tutorials/data/documentation/xcode-release-notes/"
                                      "xcode-27_1-release-notes.json (the data of "
                                      "https://developer.apple.com/documentation/xcode-release-notes/xcode-27_1-release-notes)", [
        "Xcode 27.1 Release Notes",
        "Xcode 27.1 includes Swift 6.4 and SDKs for iOS 27.1, iPadOS 27, tvOS 27, watchOS 27, macOS 27, and visionOS 27.",
        "Xcode 27.1 supports on-device debugging in iOS 17 and later, tvOS 17 and later, watchOS 10 and later, and visionOS.",
        "Xcode 27.1 requires a Mac running macOS Tahoe 26.6 or later.",
        "Projects that use APIs specific to iOS 27.1 show compile errors when building for Mac Catalyst",
        "Projects that target iOS 27.1 show no Mac Catalyst run destination available.",
        "Initial Simulator launch can take several minutes.",
        "StandBy is unavailable in the iPhone Duo Simulator runtime.",
    ], ["Beta Release Notes"]),
}


def normalized(text):
    text = text.replace("‐", "-").replace("‑", "-").replace(" ", " ")
    text = text.replace("’", "'").replace("“", '"').replace("”", '"')
    return re.sub(r"\s+", " ", text)


def html_text(raw):
    raw = re.sub(r"<(script|style)\b.*?</\1>", " ", raw, flags=re.S | re.I)
    return normalized(html.unescape(re.sub(r"<[^>]+>", " ", raw)))


def json_text(raw):
    out = []

    def walk(node):
        if isinstance(node, dict):
            for key, value in node.items():
                if key in ("text", "title", "code") and isinstance(value, str):
                    out.append(value)
                else:
                    walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)
    walk(json.loads(raw))
    return normalized(" ".join(out))


problems = 0
for name, (url, quotes, absent) in PAGES.items():
    path = FOLDER / name
    print(f"-- {url}")
    if not path.exists() or path.stat().st_size == 0:
        print(f"   PROBLEM: not fetched ({name})")
        problems += 1
        continue
    raw = path.read_text(encoding="utf-8", errors="replace")
    text = json_text(raw) if name.endswith(".json") else html_text(raw)
    print(f"   fetched: {path.stat().st_size} bytes; text read: {len(text)} characters")
    for quote in quotes:
        found = normalized(quote) in text
        problems += 0 if found else 1
        print(f"   {'present' if found else 'PROBLEM missing'}: \"{quote}\"")
    for quote in absent:  # in any letter case, so that a capitalized form is found too
        found = normalized(quote).lower() in text.lower()
        problems += 1 if found else 0
        print(f"   {'PROBLEM present' if found else 'absent, as required (any letter case)'}: \"{quote}\"")
print(f"result: {'pass' if problems == 0 else 'FAIL'} ({problems} problem(s))")
sys.exit(1 if problems else 0)
