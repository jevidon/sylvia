#!/usr/bin/env python3
"""Checks the harness app's event log after a terminate-and-relaunch UI test (G0.2 part 2, T41).

    analyze-relaunch.py EVENTS_JSONL SOURCE_OUT_LOG JOB_TITLE_FILE_HINT

Splits the app's events at each `app_launch`, and reports for the transfer job:
- parts verified before the termination and parts requested after each relaunch (must be disjoint: a verified
  part is never fetched again);
- trust challenges with the app state at the time (when the background session asked the app);
- source requests that arrived while the app was not running (between its last event before a launch and that
  launch), i.e. work the system's background session did on its own.
Exits 1 if a verified part was requested again or the job never reached `imported`.
"""
import json
import sys
from datetime import datetime


def parse_time(text):
    return datetime.fromisoformat(text.replace("Z", "+00:00"))


def main():
    events_path, source_log = sys.argv[1], sys.argv[2]
    events = [json.loads(line) for line in open(events_path) if line.strip()]
    launches = [i for i, e in enumerate(events) if e["event"] == "app_launch"]
    segments = []
    for n, start in enumerate(launches):
        end = launches[n + 1] if n + 1 < len(launches) else len(events)
        segments.append(events[start:end])
    jobs = sorted({e["fields"]["job"] for e in events if e["event"] == "job_created"})
    print(f"app launches: {len(launches)}; jobs: {len(jobs)}")
    failed = False
    if len(jobs) != 1:
        print("CHECK FAILED: expected exactly one job")
        return 1
    job = jobs[0]
    verified_so_far = set()
    for n, segment in enumerate(segments):
        launch = segment[0]
        state = launch["fields"].get("application_state")
        system = any(e["event"] == "background_events_launch" for e in segment)
        foreground = any(e["fields"].get("app_state") == "foreground" for e in segment)
        kind = ("system background relaunch (handleEventsForBackgroundURLSession, no scene became active)"
                if system and not foreground else "launch by the test (scene became active)" if foreground
                else "launch without background events or an active scene")
        print(f"launch {n + 1} at {launch['time']}: {kind}; UIKit applicationState at didFinishLaunching: {state}")
        for e in segment:
            f = e["fields"]
            if e["event"] == "launch_reconciliation":
                print("  reconciliation: " + " ".join(f"{k}={v}" for k, v in sorted(f.items())))
            if e["event"] in ("background_events_launch", "background_events_finished", "background_events_other_session"):
                print(f"  {e['time']} {e['event']} " + " ".join(f"{k}={v}" for k, v in sorted(f.items())))
        requested = [e for e in segment if e["event"] == "part_requested" and e["fields"].get("job") == job]
        verified = [e for e in segment if e["event"] == "part_verified" and e["fields"].get("job") == job]
        challenges = [e for e in segment if e["event"] == "trust_challenge"]
        again = sorted({e["fields"]["part"] for e in requested} & verified_so_far)
        print(f"  parts requested: {len(requested)}; verified: {len(verified)}; "
              f"trust challenges: {len(challenges)} (app states {sorted({c['fields'].get('app_state') for c in challenges})}, "
              f"results {sorted({c['fields'].get('result') for c in challenges})})")
        by_state = {}
        for e in verified:
            by_state[e["fields"].get("app_state")] = by_state.get(e["fields"].get("app_state"), 0) + 1
        print(f"  parts verified by app state: {by_state}")
        if again:
            print(f"  CHECK FAILED: parts verified earlier were requested again: {again}")
            failed = True
        verified_so_far |= {e["fields"]["part"] for e in verified}
        if n + 1 < len(segments):
            print(f"  last event before the next launch: {segment[-1]['time']} {segment[-1]['event']}")
    imported = [e for e in events if e["event"] == "imported" and e["fields"].get("job") == job]
    print(f"imported events for the job: {len(imported)}" + (f" (completions={imported[0]['fields'].get('completions')})" if imported else ""))
    if len(imported) != 1 or imported[0]["fields"].get("completions") != "1":
        print("CHECK FAILED: the job was not imported exactly once")
        failed = True

    # Source requests and accepted connections while the app was not running.
    requests = []
    connections = []
    accepted_so_far = 0
    for line in open(source_log):
        parts = line.split()
        if len(parts) >= 3 and parts[0] == "request" and "/content" in line:
            requests.append((parse_time(parts[1]), line.strip()))
        if len(parts) >= 3 and parts[0] == "connections":
            # The line is printed when the accepted count or the decrypted byte count changes; only a higher
            # accepted count is a new connection.
            fields = dict(p.split("=", 1) for p in parts[2:] if "=" in p)
            accepted_now = int(fields.get("accepted", accepted_so_far))
            if accepted_now > accepted_so_far:
                connections.append((parse_time(parts[1]), line.strip()))
            accepted_so_far = accepted_now
    for n in range(1, len(segments)):
        gap_start = parse_time(segments[n - 1][-1]["time"])
        gap_end = parse_time(segments[n][0]["time"])
        during = [r for r in requests if gap_start < r[0] < gap_end]
        print(f"gap before launch {n + 1}: {gap_start.isoformat()} to {gap_end.isoformat()} "
              f"({(gap_end - gap_start).total_seconds():.1f} s): {len(during)} content requests reached the source")
        for _, text in during:
            print(f"  {text}")
        accepted = [c for c in connections if gap_start < c[0] < gap_end]
        print(f"  log lines with a higher accepted TCP connection count during the gap: {len(accepted)}")
        for _, text in accepted:
            print(f"  {text}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
