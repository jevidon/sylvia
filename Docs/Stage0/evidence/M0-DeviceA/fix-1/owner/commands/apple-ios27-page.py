#!/usr/bin/env python3
"""Checks, in Apple's iPhone User Guide page "iPhone models compatible with iOS 27" as fetched by apple-ios27-page.sh
beside this file, the text the runbook's 1.1 row A now rests on (the fix of the owner-readability findings of the review
of the update of 24 October 2026, its finding OWN-DA-07): the page's title, and its list of compatible models, which
starts at the iPhone 11 family and holds the iPhone 13 mini, as the finding quotes it; and, so that the list is read as a
list of models and not as one long name, that the iPhone SE (2nd generation), the other oldest iPhone iOS 26 supports,
is on it too. Each page's text is read as data: script and style blocks and HTML tags removed, entities decoded, runs of
whitespace made one space, and the Unicode hyphens U+2010 and U+2011 made "-", as the records part's
commands/apple-device-pages.py reads its pages. Read-only; standard library only.

    python3 -I apple-ios27-page.py <fetched page>

Exit status 1 if a quote is missing or the page was not fetched.
"""
import html
import re
import sys
from pathlib import Path

PAGE = Path(sys.argv[1])
URL = "https://support.apple.com/guide/iphone/iphone-models-compatible-with-ios-27-iphe3fa5df43/27/ios/27"
QUOTES = [
    "iPhone models compatible with iOS 27",
    # The list as OWN-DA-07 quotes it, up to the iPhone 13: it starts at the iPhone 11 family and holds the iPhone 13 mini.
    "iOS 27, which is compatible with the following models: iPhone 11 iPhone 11 Pro iPhone 11 Pro Max iPhone 12 mini "
    "iPhone 12 iPhone 12 Pro iPhone 12 Pro Max iPhone 13 mini iPhone 13",
    "iPhone SE (2nd generation) iPhone SE (3rd generation)",
]


def normalized(text):
    text = text.replace("‐", "-").replace("‑", "-").replace(" ", " ")
    text = text.replace("’", "'").replace("“", '"').replace("”", '"')
    return re.sub(r"\s+", " ", text)


def html_text(raw):
    raw = re.sub(r"<(script|style)\b.*?</\1>", " ", raw, flags=re.S | re.I)
    return normalized(html.unescape(re.sub(r"<[^>]+>", " ", raw)))


problems = 0
print(f"-- {URL}")
if not PAGE.exists() or PAGE.stat().st_size == 0:
    print(f"   PROBLEM: not fetched ({PAGE.name})")
    problems += 1
else:
    text = html_text(PAGE.read_text(encoding="utf-8", errors="replace"))
    print(f"   fetched: {PAGE.stat().st_size} bytes; text read: {len(text)} characters")
    for quote in QUOTES:
        found = normalized(quote) in text
        problems += 0 if found else 1
        print(f"   {'present' if found else 'PROBLEM missing'}: \"{quote}\"")
print(f"result: {'pass' if problems == 0 else 'FAIL'} ({problems} problem(s))")
sys.exit(1 if problems else 0)
