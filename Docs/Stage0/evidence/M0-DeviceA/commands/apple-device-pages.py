#!/usr/bin/env python3
"""Checks, in Apple's own pages as fetched by apple-device-pages.sh beside this file, each text the records of the
device-A change (24 October 2026) quote about the phones: the iPhone 13 mini's and the iPhone 11 Pro's technical
specifications (facts 1 and 2 of the README), the A13 of the other oldest iPhones iOS 26 supports (the iPhone 11, the
iPhone 11 Pro Max and the iPhone SE (2nd generation)), and the iPhones iOS 26 supports (fact 6: the list starts at the
iPhone 11 family and holds the iPhone 13 mini, and names neither the iPhone XS nor the iPhone XR). For fact 7, it checks that
neither specification page gives a memory (RAM) size: the word "RAM" must be absent, and every sentence that holds the
word "memory" is printed so that a reader can see what it is about.

Each page's text is read as data: script and style blocks and HTML tags removed, entities decoded, runs of whitespace
made one space, and the Unicode hyphens U+2010 and U+2011 made "-". Each quote must occur in it as written; each
"absent" text must not, in any letter case. Read-only; standard library only.

    python3 -I apple-device-pages.py <folder of fetched pages>

Exit status 1 if a quote is missing, an absent text is present or a page was not fetched.
"""
import html
import re
import sys
from pathlib import Path

FOLDER = Path(sys.argv[1])

# file -> (URL, quotes that must be present, texts that must be absent in any letter case, list "memory" sentences)
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
    ], ["Action button"], True),
    "iphone-11-pro-specs.html": ("https://support.apple.com/en-nz/111879", [
        "iPhone 11 Pro - Technical Specifications",
        "5.8-inch (diagonal) all-screen OLED Multi-Touch display",
        "2436-by-1125-pixel resolution at 458 ppi",
        "A13 Bionic chip",
        "Lightning connector",
        "Ring/Silent switch",
    ], ["Action button"], True),
    # The other oldest iPhones iOS 26 supports: each has the A13, as the records say of "the oldest iPhones iOS 26
    # supports, the iPhone 11 family and the iPhone SE (2nd generation)".
    "iphone-11-specs.html": ("https://support.apple.com/en-nz/111865", [
        "iPhone 11 - Technical Specifications",
        "1792-by-828-pixel resolution at 326 ppi",
        "A13 Bionic chip",
    ], [], False),
    "iphone-11-pro-max-specs.html": ("https://support.apple.com/en-nz/111878", [
        "iPhone 11 Pro Max - Technical Specifications",
        "2688-by-1242-pixel resolution at 458 ppi",
        "A13 Bionic chip",
    ], [], False),
    "iphone-se-2nd-generation-specs.html": ("https://support.apple.com/en-nz/111882", [
        "iPhone SE (2nd generation) - Technical Specifications",
        "1334-by-750-pixel resolution at 326 ppi",
        "A13 Bionic chip",
    ], [], False),
    "ios-26-models.html": (
        "https://support.apple.com/guide/iphone/iphone-models-compatible-with-ios-26-iphe3fa5df43/26/ios/26", [
            "iPhone models compatible with iOS 26",
            # The list starts at the iPhone 11 family and holds the iPhone 13 mini.
            "which is compatible with the following models: iPhone 11 iPhone 11 Pro iPhone 11 Pro Max iPhone 12 mini "
            "iPhone 12 iPhone 12 Pro iPhone 12 Pro Max iPhone 13 mini iPhone 13",
            "iPhone SE (2nd generation) iPhone SE (3rd generation)",
        ], ["iPhone XS", "iPhone XR"], False),
}


def normalized(text):
    text = text.replace("‐", "-").replace("‑", "-").replace(" ", " ")
    text = text.replace("’", "'").replace("“", '"').replace("”", '"')
    return re.sub(r"\s+", " ", text)


def html_text(raw):
    raw = re.sub(r"<(script|style)\b.*?</\1>", " ", raw, flags=re.S | re.I)
    return normalized(html.unescape(re.sub(r"<[^>]+>", " ", raw)))


problems = 0
for name, (url, quotes, absent, memory) in PAGES.items():
    path = FOLDER / name
    print(f"-- {url}")
    if not path.exists() or path.stat().st_size == 0:
        print(f"   PROBLEM: not fetched ({name})")
        problems += 1
        continue
    text = html_text(path.read_text(encoding="utf-8", errors="replace"))
    print(f"   fetched: {path.stat().st_size} bytes; text read: {len(text)} characters")
    for quote in quotes:
        found = normalized(quote) in text
        problems += 0 if found else 1
        print(f"   {'present' if found else 'PROBLEM missing'}: \"{quote}\"")
    for quote in absent:
        found = normalized(quote).lower() in text.lower()
        problems += 1 if found else 0
        print(f"   {'PROBLEM present' if found else 'absent, as required (any letter case)'}: \"{quote}\"")
    if memory:
        ram = re.findall(r"\bRAM\b", text)
        problems += 1 if ram else 0
        print(f"   {'PROBLEM present' if ram else 'absent, as required'}: the word \"RAM\" ({len(ram)} occurrences)")
        hits = [m.start() for m in re.finditer(r"memory", text, flags=re.I)]
        print(f"   the word \"memory\", any letter case: {len(hits)} occurrence(s)")
        for start in hits:
            print(f"     ...{text[max(0, start - 90):start + 90]}...")
print(f"result: {'pass' if problems == 0 else 'FAIL'} ({problems} problem(s))")
sys.exit(1 if problems else 0)
