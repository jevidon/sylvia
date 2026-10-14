"""Turns the lift probe lines of a simulator log (see lift_probe_instrument.py) into the Markdown table of
large-content-viewer-timing-probe-simulator.md.

Usage: python lift_probe_table.py <probe-run.txt> <requested durations, comma separated, per launch>
       e.g. "0.1,0.12,0.15,0.2,0.35,3,0.1,0.12,0.15,0.2,0.35,3,3,tap"
The requested list applies to each app launch (press numbering restarts at 1 per launch).
"""
import re
import sys
from datetime import datetime
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
requested = sys.argv[2].split(",")
events = []
for line in text.split("\n"):
    m = re.match(r"^(\S+ \S+) .*\] probe (\w+) (.*)$", line)
    if not m:
        continue
    t = datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S.%f")
    events.append((t, m.group(2), m.group(3)))

launches, current, last_press = [], None, 0
for t, kind, rest in events:
    press = int(re.search(r"(?:press|lifted|owner)=(\d+)", rest).group(1))
    if kind == "touchBegan" and (current is None or press < last_press):
        current = {}
        launches.append(current)
    if kind == "touchBegan":
        last_press = press
    entry = current.setdefault(press, {})
    entry.setdefault(kind, (t, rest))

rows = ["| Launch | Press | Requested | Measured (down to lift) | Button action | Lift activation | Activations |",
        "| --- | --- | --- | --- | --- | --- | --- |"]
for n, launch in enumerate(launches, start=1):
    for press in sorted(launch):
        e = launch[press]
        down, up = e["touchBegan"][0], e["touchLifted"][0]
        measured = (up - down).total_seconds()
        req = requested[press - 1] if press - 1 < len(requested) else "?"
        action = "none"
        count = 0
        if "buttonAction" in e:
            at, rest = e["buttonAction"]
            ms = (at - up).total_seconds() * 1000
            dropped = "DROPPED" in rest
            action = f"{'dropped' if dropped else 'ran'}, {ms:.0f} ms after the lift"
            count += 0 if dropped else 1
        lift = "not scheduled"
        if "liftScheduled" in e:
            lift = "scheduled"
            if "liftSettled" in e:
                at, rest = e["liftSettled"]
                ms = (at - up).total_seconds() * 1000
                ran = rest.endswith("ran")
                lift = f"{'ran' if ran else 'skipped'}, {ms:.0f} ms after the lift"
                count += 1 if ran else 0
        req = "tap (XCUITest tap())" if req == "tap" else f"{req} s"
        rows.append(f"| {n} | {press} | {req} | {measured:.3f} s | {action} | {lift} | {count} |")
print("\n".join(rows))
