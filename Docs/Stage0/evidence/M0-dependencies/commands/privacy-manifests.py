"""ADR-0014 evidence: the privacy manifests (PrivacyInfo.xcprivacy) that pinned packages ship, and whether the SwiftPM
target that holds each one declares it as a resource, so the App Store obligations of plan 18.2 (privacy manifest,
required-reason APIs, third-party SDK declarations) can be stated per package.

  python3 -I privacy-manifests.py <checkouts dir> [<checkouts dir> ...]

For every PrivacyInfo.xcprivacy under each checkout (outside .git and .build): tracking flag, tracking domains,
collected data types, and accessed API categories with their reason codes. Packages with no manifest are listed too.
Reads files only; no network.
"""
import os
import plistlib
import sys

for top in sys.argv[1:]:
    # Each directory is a different package graph's checkouts; two packages may share a directory name (the two
    # ZIPFoundations), so nothing is de-duplicated and every result names the checkout it was read from.
    print(f'## {top}')
    for pkg in sorted(os.listdir(top)):
        root = os.path.join(top, pkg)
        if not os.path.isdir(root):
            continue
        found = []
        for dp, dns, fns in os.walk(root):
            dns[:] = sorted(d for d in dns if d not in {'.git', '.build'})
            for fn in fns:
                if fn == 'PrivacyInfo.xcprivacy':
                    found.append(os.path.join(dp, fn))
        if not found:
            print(f'== {pkg}: no PrivacyInfo.xcprivacy')
            continue
        manifest = open(os.path.join(root, 'Package.swift'), encoding='utf-8').read() if os.path.exists(
            os.path.join(root, 'Package.swift')) else ''
        for path in sorted(found):
            rel = os.path.relpath(path, root)
            with open(path, 'rb') as f:
                d = plistlib.load(f)
            apis = []
            for entry in d.get('NSPrivacyAccessedAPITypes', []):
                cat = entry.get('NSPrivacyAccessedAPIType', '?').replace('NSPrivacyAccessedAPICategory', '')
                apis.append(f"{cat} ({', '.join(entry.get('NSPrivacyAccessedAPITypeReasons', [])) or 'no reason'})")
            declared = 'PrivacyInfo.xcprivacy' in manifest
            print(f'== {pkg}: {rel}')
            print(f'   tracking: {d.get("NSPrivacyTracking")}; tracking domains: {d.get("NSPrivacyTrackingDomains") or "none"};'
                  f' collected data types: {len(d.get("NSPrivacyCollectedDataTypes") or [])};'
                  f' Package.swift names PrivacyInfo.xcprivacy: {"yes" if declared else "no"}')
            print(f'   accessed API types: {"; ".join(apis) or "none"}')
