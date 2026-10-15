#!/usr/bin/env python3
"""Summarize EPUBHarness crash reports for a test run (G0.1 EPUB spike).

    summarize-crashes.py <marker-file> <output.txt> [<simulator-udid>]

Reads every ~/Library/Logs/DiagnosticReports/EPUBHarness-*.ips and keeps those whose crash happened during the run
(the report's own captureTime is at or after the mtime of <marker-file>, which the CI drop-in touches before the tests
start). For each it writes the pid, the exception, the termination reason and the crashing thread's frames with
repeated frames collapsed.

Reports whose crash is older but whose file was modified during the run are listed by name only. In this
environment macOS did not always write a new report for an expected crash: on 7 Oct 2026 four Readium-alone crashes
left no new file, and on 12 Oct 2026 one of two in one run and both in the next did. Each time, an older EPUBHarness
report's modification time changed at that moment while its contents stayed those of the older crash (on 12 Oct once
a report from another simulator, once this simulator's report from the run before). Why is not known; the
DiagnosticReports folder held 25 EPUBHarness reports, which may be a per-app limit (not verified). See
Docs/Stage0/evidence/G01-EPUB/observations/README.md. So a crashed process may have no report of its own;
DeepNestingUITests decides that the app crashed from the process itself, not from these files, and what kind of crash
it was from the app's own signal record (Harness/CrashSignalRecorder.c).

With <simulator-udid>, only reports from that simulator are kept (the report's procPath or coalition names the
simulator device), so an EPUBHarness crash in another checkout's simulator on the same Mac, which writes to the same
DiagnosticReports folder, is not mistaken for one of this run's.

Expected crashes come from DeepNestingUITests (Readium alone on 10,000 nested elements); the CI drop-in fails on any
other. Exits 0 even when there are no reports.
"""
import json
import sys
from datetime import datetime
from pathlib import Path


def load(path: Path):
    text = path.read_text(errors="replace")
    header, _, body = text.partition("\n")
    return json.loads(header), json.loads(body)


def capture_epoch(report) -> float | None:
    raw = report.get("captureTime")
    if not raw:
        return None
    try:
        date, time, zone = raw.split(" ")
        time = time.split(".")[0]
        return datetime.strptime(f"{date} {time} {zone}", "%Y-%m-%d %H:%M:%S %z").timestamp()
    except ValueError:
        return None


def summarize(path: Path, meta, report) -> str:
    lines = [f"== {path.name}",
             f"app: {meta.get('app_name')} {meta.get('bundleID')}  os: {meta.get('os_version')}  pid: {report.get('pid')}  "
             f"captured: {report.get('captureTime')}"]
    exc = report.get("exception", {})
    lines.append(f"exception: {exc.get('type')} {exc.get('signal')} - {exc.get('message', exc.get('subtype', ''))}")
    term = report.get("termination", {})
    lines.append(f"termination: {term.get('indicator', '')}")
    thread = report["threads"][report["faultingThread"]]
    images = report.get("usedImages", [])
    frames = [f"{images[f['imageIndex']].get('name', '?') if f.get('imageIndex') is not None and f['imageIndex'] < len(images) else '?'}  {f.get('symbol', '?')}"
              for f in thread.get("frames", [])]
    lines.append(f"crashing thread: {len(frames)} frames (repeats collapsed)")
    previous, count = None, 0
    for frame in frames + [None]:
        if frame == previous:
            count += 1
            continue
        if previous is not None:
            lines.append(f"  {previous}" + (f"   x{count}" if count > 1 else ""))
        previous, count = frame, 1
    return "\n".join(lines)


def from_simulator(report, udid: str) -> bool:
    return f"/Devices/{udid}/" in (report.get("procPath") or "") or (report.get("coalitionName") or "").endswith(udid)


def main() -> int:
    marker, output = Path(sys.argv[1]), Path(sys.argv[2])
    udid = sys.argv[3] if len(sys.argv) > 3 else None
    since = marker.stat().st_mtime
    new, touched = [], []
    other_simulators = 0
    for p in (Path.home() / "Library/Logs/DiagnosticReports").glob("EPUBHarness-*.ips"):
        try:
            meta, report = load(p)
        except (OSError, ValueError):
            continue
        if udid and not from_simulator(report, udid):
            if p.stat().st_mtime >= since:
                other_simulators += 1
            continue
        captured = capture_epoch(report)
        if captured is not None and captured >= since:
            new.append((captured, p, meta, report))
        elif p.stat().st_mtime >= since:
            touched.append(p.name)
    new.sort(key=lambda t: t[0])
    scope = f" on simulator {udid}" if udid else ""
    parts = [f"EPUBHarness crash reports for crashes during this run{scope}: {len(new)}"]
    if other_simulators:
        parts.append(f"Reports from other simulators written or modified during this run (ignored): {other_simulators}")
    if touched:
        parts.append("Older reports modified during this run (no new report written for a repeated crash): " + ", ".join(sorted(touched)))
    parts += [summarize(p, meta, report) for _, p, meta, report in new]
    output.write_text("\n\n".join(parts) + "\n")
    print(parts[0])
    return 0


if __name__ == "__main__":
    sys.exit(main())
