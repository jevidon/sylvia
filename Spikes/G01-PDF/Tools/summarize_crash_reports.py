#!/usr/bin/env python3
"""Summarizes macOS/simulator crash reports (.ips, JSON) for Stage 0 evidence: capture time, process, build slice,
exception, and the top frames of the crashed thread. Holds no user data: the harness only ever opens the generated
fixtures. Python 3 standard library only.

    python3 Spikes/G01-PDF/Tools/summarize_crash_reports.py ~/Library/Logs/DiagnosticReports/PDFSpikeHarness-*.ips
"""

import json
import os
import sys


def summarize(path, frames=8):
    with open(path, encoding="utf-8") as f:
        head = json.loads(f.readline())
        body = json.loads(f.read())
    out = ["== " + os.path.basename(path)]
    out.append("  captured %s; process %s (%s); host %s; build slice %s" % (
        body.get("captureTime"), head.get("app_name"), head.get("bundleID"), head.get("os_version"),
        head.get("slice_uuid")))
    exc = body.get("exception", {})
    out.append("  exception %s %s %s" % (exc.get("type"), exc.get("signal"), exc.get("subtype") or ""))
    images = body.get("usedImages", [])
    index = body.get("faultingThread", 0)
    thread = body["threads"][index]
    out.append("  crashed thread %d%s" % (index, (", queue " + thread["queue"]) if thread.get("queue") else ""))
    for frame in thread.get("frames", [])[:frames]:
        i = frame.get("imageIndex")
        image = images[i].get("name", "?") if i is not None and i < len(images) else "?"
        where = ""
        if frame.get("sourceFile"):
            where = " (%s:%s)" % (frame["sourceFile"], frame.get("sourceLine", "?"))
        out.append("    %s  %s%s" % (image, frame.get("symbol", "?"), where))
    return "\n".join(out)


def main(paths):
    for path in sorted(paths):
        print(summarize(path))


if __name__ == "__main__":
    main(sys.argv[1:])
